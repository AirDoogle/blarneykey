import AVFoundation

/// Records the microphone straight to a 16 kHz mono WAV, which is exactly the format
/// Whisper wants. AVAudioRecorder does the sample-rate conversion for us, so there is
/// no AVAudioConverter plumbing to get wrong.
final class Recorder {
    private var recorder: AVAudioRecorder?
    private(set) var startedAt: Date?

    /// Each Recorder writes to its own file, so dictation and the Settings mic test can
    /// run their own captures without trampling each other's WAV.
    let fileURL: URL

    init(filename: String = "utterance.wav") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blarneykey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
    }

    /// Returns false if the microphone could not be opened.
    func start() -> Bool {
        stop()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let r = try AVAudioRecorder(url: fileURL, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { return false }
            recorder = r
            startedAt = Date()
            return true
        } catch {
            NSLog("BlarneyKey: could not start recording — \(error.localizedDescription)")
            return false
        }
    }

    /// Stops and returns how long we recorded for, or nil if we were not recording.
    @discardableResult
    func stop() -> TimeInterval? {
        guard let r = recorder, let began = startedAt else { return nil }
        let duration = r.currentTime > 0 ? r.currentTime : Date().timeIntervalSince(began)
        r.stop()
        recorder = nil
        startedAt = nil
        return duration
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Input level from 0 to 1, for the level meter. Decibels are logarithmic and
    /// bottom out around -60, so map that range onto something that looks alive.
    var level: Double {
        guard let r = recorder, r.isRecording else { return 0 }
        r.updateMeters()
        let db = Double(r.averagePower(forChannel: 0))
        guard db.isFinite else { return 0 }
        let floor = -55.0
        guard db > floor else { return 0 }
        return min(1, (db - floor) / -floor)
    }
}
