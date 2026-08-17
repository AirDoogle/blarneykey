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
                var text = try await Task.detached(priority: .userInitiated) {
                    try Transcriber.transcribe(audio, settings: settings)
                }.value

                guard !text.isEmpty else {
                    await MainActor.run { self.state = .idle }
                    return
                }

                // A snippet replaces the utterance wholesale, so no tidying afterwards.
                if let expansion = SnippetEngine.expand(text, using: self.store.snippets) {
                    text = expansion
                } else if self.store.shouldFormat(bundleID: bundleID) {
                    text = await Cleanup.polish(text)
                }

                let finalText = text
                await MainActor.run {
                    self.deliver(finalText, duration: duration,
                                 bundleID: bundleID, appName: appName)
                }
            } catch {
                await MainActor.run {
                    self.log(text: "", duration: duration, bundleID: bundleID,
                             appName: appName, failure: error.localizedDescription)
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Delivery

    private func deliver(_ text: String, duration: TimeInterval,
                         bundleID: String, appName: String) {
        guard store.allows(bundleID: bundleID) else {
            // Do not lose the words: put them on the clipboard and say so.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log(text: text, duration: duration, bundleID: bundleID, appName: appName,
                failure: "appNotAllowlisted(bundleID: \"\(bundleID)\")")
            fail("\(appName) is not in your allowlist — copied to the clipboard instead.")
            return
        }

        // Put focus back where it was, in case the pill or menu stole it. Activation is
        // asynchronous, so give it a moment before sending keystrokes at the app.
        targetApp?.activate()
        let mode = store.settings.insertionMode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            TextInserter.insert(text, mode: mode)
        }
        log(text: text, duration: duration, bundleID: bundleID, appName: appName, failure: nil)
        state = .idle
    }

    private func log(text: String, duration: TimeInterval, bundleID: String,
                     appName: String, failure: String?) {
        store.record(Session(
            date: Date(), text: text, appName: appName, bundleID: bundleID,
            duration: duration, failure: failure
        ))
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
