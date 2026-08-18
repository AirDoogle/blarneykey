import AppKit
import AVFoundation

/// Drives one dictation: record, transcribe, expand snippets, tidy up, paste, log.
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(locked: Bool)
        case transcribing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let store = Store.shared
    private let recorder = Recorder()

    /// Whichever app had focus when recording began — not when it ended, since the
    /// transcript has to go back where the cursor was.
    private var targetApp: NSRunningApplication?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isLocked: Bool {
        if case .recording(let locked) = state { return locked }
        return false
    }

    var level: Double { recorder.level }

    // MARK: - Recording

    func begin(locked: Bool) {
        guard case .idle = state else { return }

        // Skip our own window, otherwise dictating into the settings UI pastes into
        // whatever was behind it.
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApp = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost

        guard recorder.start() else {
            fail("Could not open the microphone. Check Privacy & Security → Microphone.")
            return
        }
        state = .recording(locked: locked)
        play("Tink")
    }

    /// Called on key release. Ignored in locked mode, which is the whole point of it.
    func endIfHolding() {
        guard case .recording(let locked) = state, !locked else { return }
        finish()
    }

    /// Called by a tap in locked mode, Escape, or the pill's stop button.
    func stop() {
        guard isRecording else { return }
        finish()
    }

    func toggleLocked() {
        if isRecording { stop() } else { begin(locked: true) }
    }

    private func finish() {
        let wasLocked = isLocked
        guard let duration = recorder.stop() else { state = .idle; return }
        play("Pop")

        // A stray brush of the key is not dictation. Held mode only; if you
        // deliberately locked it on, a short clip was still deliberate.
        if !wasLocked, duration < store.settings.minimumDuration {
            state = .idle
            return
        }

        state = .transcribing
        let audio = recorder.fileURL
        let settings = store.settings
        let app = targetApp
        let bundleID = app?.bundleIdentifier ?? ""
        let appName = app?.localizedName ?? "Unknown"

        Task { [weak self] in
            guard let self else { return }
            do {
                let transcribeStart = Date()
                let raw = try await Task.detached(priority: .userInitiated) {
                    try Transcriber.transcribe(audio, settings: settings)
                }.value
                let transcribeSeconds = Date().timeIntervalSince(transcribeStart)

                guard !raw.isEmpty else {
                    await MainActor.run { self.state = .idle }
                    return
                }

                var finalText = raw
                var cleanedText: String? = nil
                var cleanSeconds: TimeInterval? = nil
                var cleanModel: String? = nil

                // A snippet replaces the utterance wholesale, so no tidying afterwards.
                if let expansion = SnippetEngine.expand(raw, using: self.store.snippets) {
                    finalText = expansion
                } else if self.store.shouldFormat(bundleID: bundleID) {
                    let cleanStart = Date()
                    finalText = await Cleanup.polish(raw)
                    cleanSeconds = Date().timeIntervalSince(cleanStart)
                    cleanedText = finalText
                    cleanModel = Cleanup.modelName
                }

                let session = Session(
                    date: Date(), text: finalText, appName: appName, bundleID: bundleID,
                    duration: duration, failure: nil,
                    rawText: raw, cleanedText: cleanedText,
                    transcribeModel: settings.speechModelName, cleanModel: cleanModel,
                    destination: nil,
                    transcribeSeconds: transcribeSeconds, cleanSeconds: cleanSeconds,
                    pasteSeconds: nil
                )
                await MainActor.run { self.deliver(session) }
            } catch {
                await MainActor.run {
                    self.store.record(Session(
                        date: Date(), text: "", appName: appName, bundleID: bundleID,
                        duration: duration, failure: error.localizedDescription
                    ))
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Delivery

    private func deliver(_ session: Session) {
        var session = session
        let text = session.text

        // Pasting needs a live Accessibility grant. Without one, CGEvent.post silently
        // does nothing — so check first and say so, rather than recording a success for
        // text that never arrived anywhere.
        guard AXIsProcessTrusted() else {
            copyToClipboard(text)
            session.destination = "clipboard"
            session.failure = "accessibilityNotGranted"
            store.record(session)
            fail("No Accessibility permission, so BlarneyKey cannot paste. Copied to the clipboard instead.")
            return
        }

        guard store.allows(bundleID: session.bundleID) else {
            // Do not lose the words: put them on the clipboard and say so.
            copyToClipboard(text)
            session.destination = "clipboard"
            session.failure = "appNotAllowlisted(bundleID: \"\(session.bundleID)\")"
            store.record(session)
            fail("\(session.appName) is not in your allowlist — copied to the clipboard instead.")
            return
        }

        // Put focus back where it was, in case the pill or menu stole it. Activation is
        // asynchronous, so give it a moment before sending keystrokes at the app.
        targetApp?.activate()
        let mode = store.settings.insertionMode
        session.destination = mode == .paste ? "paste" : "type"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            let pasteStart = Date()
            TextInserter.insert(text, mode: mode)
            session.pasteSeconds = Date().timeIntervalSince(pasteStart)
            self?.store.record(session)
        }
        state = .idle
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func fail(_ message: String) {
        NSLog("BlarneyKey: \(message)")
        state = .failed(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if case .failed = self?.state { self?.state = .idle }
        }
    }

    private func play(_ name: String) {
        guard store.settings.playSounds else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Permissions

    func requestMicrophoneAccess() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }
}
