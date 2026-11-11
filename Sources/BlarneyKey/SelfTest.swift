import Foundation

/// Runs one audio file through the real pipeline from the command line, inside the signed
/// app, so the engine can be checked without a microphone.
enum SelfTest {
    static func run(path: String) -> Never {
        let url = URL(fileURLWithPath: path)
        let settings = Store.shared.settings
        SpeechServer.shared.sync(settings)
        for _ in 0..<120 where !SpeechServer.shared.isReady { usleep(250_000) }
        print("engine ready: \(SpeechServer.shared.isReady)")
        if let check = AudioCheck.analyse(url) {
            print("peak \(Int(check.peakDB)) dB, voiced \(check.voicedSeconds)s, dead \(check.isDead)")
        }
        for _ in 0..<3 {
            let start = Date()
            let text = (try? Transcriber.transcribe(url, settings: settings)) ?? "<failed>"
            print(String(format: "%.2fs  ", Date().timeIntervalSince(start)) + text)
        }
        SpeechServer.shared.stop()
        exit(0)
    }
}
