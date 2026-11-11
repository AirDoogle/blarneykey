import AVFoundation

/// How much sound a recording actually holds. Whisper invents text for near-silence,
/// most often "Thank you.", so a transcript alone cannot say whether anyone spoke.
struct AudioCheck {
    /// Loudest 30ms frame, in dBFS.
    var peakDB: Double
    /// Total time spent above the speech threshold.
    var voicedSeconds: Double

    static let frameSeconds = 0.03
    /// Roughly where a voice sits clear of a quiet room on a laptop microphone.
    static let speechDB = -42.0
    /// Below this the input is effectively dead: muted, or the wrong device.
    static let deadDB = -70.0
    /// A real "thank you" holds sound for longer than a key click does.
    static let minimumVoicedSeconds = 0.25

    /// Phrases Whisper produces from nothing. Each is dropped only when the audio backs
    /// that up, because all of them are also things people really say.
    private static let phantoms: Set<String> = [
        "thank you", "thanks", "thanks for watching", "thank you for watching",
        "thank you very much", "you", "bye", "okay"
    ]

    var isDead: Bool { peakDB < Self.deadDB }

    /// True for a stock phrase from a recording with almost no voice in it.
    func isPhantom(_ text: String) -> Bool {
        guard voicedSeconds < Self.minimumVoicedSeconds else { return false }
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted)
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return Self.phantoms.contains(words)
    }

    /// Measures samples in the range -1...1.
    static func measure(samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> AudioCheck {
        let frame = max(1, Int(sampleRate * frameSeconds))
        var peak = -Double.infinity
        var voicedFrames = 0
        var start = 0
        while start < samples.count {
            let end = min(start + frame, samples.count)
            var sum = 0.0
            for index in start..<end { sum += Double(samples[index] * samples[index]) }
            let rms = (sum / Double(end - start)).squareRoot()
            let db = rms > 0 ? 20 * log10(rms) : -160
            peak = max(peak, db)
            if db > speechDB { voicedFrames += 1 }
            start = end
        }
        return AudioCheck(peakDB: peak.isFinite ? peak : -160,
                          voicedSeconds: Double(voicedFrames) * Double(frame) / sampleRate)
    }

    /// Nil when the file cannot be read, which callers treat as "assume someone spoke".
    static func analyse(_ url: URL) -> AudioCheck? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        return measure(samples: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)),
                       sampleRate: file.processingFormat.sampleRate)
    }
}
