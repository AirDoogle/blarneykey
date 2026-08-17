import Foundation

/// Runs whisperkit-cli on a WAV file. stdout is the transcript and nothing else;
/// all the progress chatter goes to stderr, so parsing is just "trim stdout".
enum Transcriber {
    enum Failure: Error, LocalizedError {
        case cliMissing(String)
        case modelMissing(String)
        case failed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .cliMissing(let path):
                return "whisperkit-cli not found at \(path)"
            case .modelMissing(let path):
                return "no model at \(path)"
            case .failed(let code, let stderr):
                let tail = stderr.split(separator: "\n")
                    .filter { !$0.contains("[ INFO ]") }
                    .suffix(2).joined(separator: " ")
                return "transcription failed (exit \(code)): \(tail)"
            }
        }
    }

    static func transcribe(_ audio: URL, settings: Settings) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: settings.cliPath) else {
            throw Failure.cliMissing(settings.cliPath)
        }
        guard FileManager.default.fileExists(atPath: settings.modelPath) else {
            throw Failure.modelMissing(settings.modelPath)
        }

        var args = [
            "transcribe",
            "--model-path", settings.modelPath,
            "--model-prefix", settings.modelPrefix,
            "--audio-path", audio.path,
            "--without-timestamps",
            "--skip-special-tokens"
        ]
        if let language = settings.language, !language.isEmpty {
            args += ["--language", language]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.cliPath)
        process.arguments = args

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        // Read before waiting, or a full pipe buffer would deadlock the child.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Failure.failed(
                process.terminationStatus,
                String(data: stderr, encoding: .utf8) ?? ""
            )
        }

        let text = String(data: stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Whisper emits these markers when it hears nothing but room noise. Only the
        // bracketed ones are safe to drop — plenty of real dictation is two words long.
        let noise = ["(silence)", "[BLANK_AUDIO]", "[silence]", "[ Silence ]", "..."]
        return noise.contains(text) ? "" : text
    }
}
