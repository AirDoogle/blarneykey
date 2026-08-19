import Foundation
import Combine

/// Drives the Settings "Test microphone" flow. Whisper works on a file, not a stream, so a
/// live feel comes from recording in short chunks: close one off, start the next straight
/// away, and transcribe the finished clip in the background. Text keeps arriving while you
/// talk, and it all stays on the Mac — same recorder and same model as real dictation.
@MainActor
final class MicTester: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var level: Double = 0
    @Published private(set) var transcript = ""
    /// A microphone-open failure, surfaced to the view. Nil the rest of the time.
    @Published private(set) var error: String?

    private let recorder = Recorder(filename: "mic-test.wav")
    private var levelTimer: Timer?
    private var chunkTimer: Timer?
    private var settings = Settings()
    private var chunkIndex = 0

    /// Long enough to catch a phrase, short enough to feel live.
    private let chunkSeconds: TimeInterval = 4

    func toggle(settings: Settings) {
        isRunning ? stop() : start(settings)
    }

    /// Re-open the microphone from scratch — used when the input device changes out from
    /// under a running test (the one it was listening to was unplugged, so macOS moved the
    /// default) so it picks up the new default instead of a device that is gone.
    func restart(settings: Settings) {
        guard isRunning else { return }
        stop()
        start(settings)
    }

    func start(_ settings: Settings) {
        guard !isRunning else { return }
        self.settings = settings
        transcript = ""
        error = nil
        chunkIndex = 0

        guard recorder.start() else {
            error = "Could not open the microphone. Check System Settings → Privacy & Security → Microphone."
            return
        }
        isRunning = true

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.level = self.recorder.level }
        }
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rollChunk() }
        }
    }

    func stop() {
        guard isRunning else { return }
        levelTimer?.invalidate(); levelTimer = nil
        chunkTimer?.invalidate(); chunkTimer = nil
        isRunning = false
        level = 0

        // Transcribe the final partial clip so the last words are not lost.
        if recorder.isRecording, recorder.stop() != nil {
            transcribe(recorder.fileURL, temporary: false)
        }
    }

    /// Close off the current clip, resume capture immediately, and transcribe the clip that
    /// just finished. The finished WAV is copied aside first, because the recorder reuses
    /// its one file and the next `start()` would overwrite it before transcription reads it.
    private func rollChunk() {
        guard isRunning, recorder.isRecording, recorder.stop() != nil else { return }
        let source = recorder.fileURL
        let copy = source.deletingLastPathComponent()
            .appendingPathComponent("mic-test-\(chunkIndex).wav")
        chunkIndex += 1
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: source, to: copy)
        _ = recorder.start()
        transcribe(copy, temporary: true)
    }

    private func transcribe(_ url: URL, temporary: Bool) {
        let settings = self.settings
        Task.detached(priority: .userInitiated) {
            let text = (try? Transcriber.transcribe(url, settings: settings)) ?? ""
            if temporary { try? FileManager.default.removeItem(at: url) }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            await MainActor.run {
                self.transcript = self.transcript.isEmpty ? trimmed : self.transcript + " " + trimmed
            }
        }
    }
}
