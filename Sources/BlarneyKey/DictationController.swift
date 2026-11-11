import AppKit
import AVFoundation

/// Drives one dictation: record, transcribe, expand prompts, tidy up, paste, log.
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

    /// The input device dictation is recording from, captured when recording begins so the
    /// history can show which microphone produced each transcript.
    private var inputDeviceName: String?

    /// The folder the target app is showing, when project awareness applies.
    private var projectFolder: URL?

    /// The highlight as it was when the keys went down.
    private var selectionAtStart: CapturedSelection?

    /// True while recording a spoken command about the selected text.
    private(set) var isCommand = false

    /// Identifies the running dictation, so a cancelled one cannot paste when it finishes.
    private var runID = 0

    /// Seconds of the last ordinary recording still on disk, while it can be retried.
    private var retryableDuration: TimeInterval?

    /// There is a recording to run again. Commands are excluded: by then the selection
    /// they applied to has usually changed.
    var canRetry: Bool {
        guard case .idle = state else { return false }
        return retryableDuration != nil
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Held-down dictation, not locked and not a command: the only time Blarney key + V
    /// means "paste the last one".
    var isHolding: Bool {
        if case .recording(let locked) = state { return !locked && !isCommand }
        return false
    }

    var isLocked: Bool {
        if case .recording(let locked) = state { return locked }
        return false
    }

    var level: Double { recorder.level }

    // MARK: - Recording

    func begin(locked: Bool, command: Bool = false) {
        guard case .idle = state else { return }

        // Skip our own window, otherwise dictating into the settings UI pastes into
        // whatever was behind it.
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApp = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost
        projectFolder = store.settings.projectAware ? ProjectContext.folder(of: targetApp) : nil
        isCommand = command
        // Read now, not after transcribing: a terminal may have cleared it by then. Shift can
        // arrive partway through a hold, so every hold reads it, and it costs a millisecond.
        selectionAtStart = CapturedSelection.read(from: targetApp)
        SpeechServer.shared.sync(store.settings)

        guard recorder.start() else {
            fail("Could not open the microphone. Check Privacy & Security → Microphone.")
            return
        }
        inputDeviceName = AudioDevices.defaultInputName
        state = .recording(locked: locked)
        play("Tink")
    }

    /// Called on key release. Ignored in locked mode, which is the whole point of it.
    func endIfHolding() {
        guard case .recording(let locked) = state, !locked else { return }
        finish()
    }

    /// Called by a tap in locked mode or the pill's stop button.
    func stop() {
        guard isRecording else { return }
        finish()
    }

    /// Escape: throw this dictation away, pasting nothing. The audio stays on disk until
    /// the next recording, so Retry last recording can still bring it back.
    func cancel() {
        switch state {
        case .recording:
            let duration = recorder.stop()
            if !isCommand { retryableDuration = duration }
        case .transcribing:
            runID += 1
        default:
            return
        }
        state = .idle
        play("Basso")
    }

    /// Runs the last recording through again and pastes it into the app it was meant for.
    /// Skips the silence checks, since asking for it says there was something to hear.
    func retryLast() {
        guard canRetry, let duration = retryableDuration else { return }
        process(duration: duration, isRetry: true)
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

        retryableDuration = isCommand ? nil : duration
        process(duration: duration, isRetry: false)
    }

    private func process(duration: TimeInterval, isRetry: Bool) {
        state = .transcribing
        runID += 1
        let run = runID
        let audio = recorder.fileURL
        let settings = store.settings
        let folder = projectFolder
        let command = isCommand && !isRetry
        let captured = selectionAtStart
        let app = targetApp
        let bundleID = app?.bundleIdentifier ?? ""
        let appName = app?.localizedName ?? "Unknown"
        let device = inputDeviceName

        Task { [weak self] in
            guard let self else { return }
            do {
                let check = isRetry ? nil : AudioCheck.analyse(audio)
                if let check, check.isDead, duration >= 0.5 {
                    await MainActor.run {
                        guard run == self.runID else { return }
                        self.fail("No sound reached the microphone. Check it isn't muted, or try another input.")
                    }
                    return
                }

                let transcribeStart = Date()
                let (raw, project) = try await Task.detached(priority: .userInitiated) {
                    let project = folder.flatMap(ProjectFiles.load)
                    let text = try Transcriber.transcribe(audio, settings: settings,
                                                          projectWords: project?.names ?? [])
                    return (text, project)
                }.value
                let transcribeSeconds = Date().timeIntervalSince(transcribeStart)

                guard run == self.runID else { return }

                if raw.isEmpty || check?.isPhantom(raw) == true {
                    NSLog("BlarneyKey: dropped an empty clip (voiced \(check?.voicedSeconds ?? -1)s)")
                    await MainActor.run { self.state = .idle }
                    return
                }

                // `raw` stays as heard in the history; everything pasted is corrected.
                let corrected = Vocabulary.apply(settings.wordFixes, to: raw)
                var finalText = corrected
                var cleanedText: String? = nil
                var cleanSeconds: TimeInterval? = nil
                var cleanModel: String? = nil
                var commandResult: String? = nil

                // A prompt replaces the utterance wholesale, so no tidying afterwards.
                var clearFirst = 0
                if command {
                    // In Claude Code's input box, the whole draft is rewritten and replaced.
                    var source = captured?.text
                    if let captured, let buffer = captured.buffer {
                        let draft = captured.range.map { TerminalDraft.draft(in: buffer, selection: $0) }
                            ?? TerminalDraft.draft(in: buffer, containing: captured.text)
                        if let draft {
                            source = draft.text
                            clearFirst = draft.clearCount
                        }
                    }
                    if source == nil { source = await CommandMode.selectedText(in: app) }
                    guard let source else { throw CommandMode.Failure.noSelection }
                    let start = Date()
                    commandResult = try await CommandMode.rewrite(source, instruction: corrected)
                    cleanSeconds = Date().timeIntervalSince(start)
                    cleanModel = Cleanup.modelName
                    guard run == self.runID else { return }
                } else if let expansion = PromptEngine.expand(corrected, using: self.store.prompts)
                    ?? PromptEngine.expand(raw, using: self.store.prompts) {
                    finalText = expansion
                } else if self.store.shouldFormat(bundleID: bundleID) {
                    let cleanStart = Date()
                    // Corrected after polishing too, in case the model "fixes" a name back.
                    finalText = Vocabulary.apply(settings.wordFixes,
                                                 to: await Cleanup.polish(corrected))
                    cleanSeconds = Date().timeIntervalSince(cleanStart)
                    cleanedText = finalText
                    cleanModel = Cleanup.modelName
                    finalText = self.tagged(finalText, project: project)
                } else {
                    finalText = self.tagged(finalText, project: project)
                }

                let session = Session(
                    date: Date(), text: finalText, appName: appName, bundleID: bundleID,
                    duration: duration, failure: nil,
                    rawText: raw, cleanedText: cleanedText,
                    transcribeModel: settings.speechModelName, cleanModel: cleanModel,
                    destination: nil,
                    transcribeSeconds: transcribeSeconds, cleanSeconds: cleanSeconds,
                    pasteSeconds: nil,
                    inputDevice: device,
                    commandResult: commandResult
                )
                guard run == self.runID else { return }
                let clear = clearFirst
                await MainActor.run { self.deliver(session, clearFirst: clear) }
            } catch {
                guard run == self.runID else { return }
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

    private func tagged(_ text: String, project: ProjectFiles?) -> String {
        guard let project else { return text }
        return FileTagger.apply(to: text, paths: project.paths)
    }

    // MARK: - Delivery

    private func deliver(_ session: Session, clearFirst: Int = 0) {
        var session = session
        let text = session.commandResult ?? session.text

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
            TextInserter.insert(text, mode: mode, deletingFirst: clearFirst)
            session.pasteSeconds = Date().timeIntervalSince(pasteStart)
            self?.store.record(session)
        }
        state = .idle
    }

    /// Shift pressed partway through holding a Blarney key: what you say is a command.
    func upgradeToCommand() {
        guard isHolding else { return }
        isCommand = true
    }

    /// Blarney key + V: drop the recording just started and paste the last dictation once
    /// the key is let go.
    func pasteLastInsteadOfRecording() {
        guard isHolding else { return }
        retryableDuration = recorder.stop()
        state = .idle
        pasteLast()
    }

    /// Pastes the last dictation at the cursor, for when it landed in the wrong place or
    /// nowhere at all. Not recorded, since nothing new was said.
    func pasteLast() {
        switch state {
        case .recording, .transcribing: return
        default: break
        }
        guard let text = Session.lastDelivered(in: store.sessions) else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard AXIsProcessTrusted(), store.allows(bundleID: frontmost?.bundleIdentifier ?? "") else {
            copyToClipboard(text)
            fail("Could not paste here, so the last dictation is on the clipboard.")
            return
        }

        // Keys still held would turn the synthetic ⌘V into something else: in Terminal,
        // ⌃⌘V is Paste Escaped Text. So wait for you to let go, and if you never do, leave
        // it on the clipboard rather than risk the wrong command.
        let mode = store.settings.insertionMode
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
            var released = false
            for _ in 0..<200 {
                if CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: held) {
                    released = true
                    break
                }
                usleep(25_000)
            }
            DispatchQueue.main.async {
                if released {
                    TextInserter.insert(text, mode: mode)
                } else {
                    self?.copyToClipboard(text)
                    self?.fail("Keys were still held, so the last dictation is on the clipboard instead.")
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardWatcher.shared.noteOwnWrite()
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
