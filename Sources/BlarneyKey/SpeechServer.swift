import Foundation

/// Keeps the speech model loaded in a local `whisperkit-cli serve` process, so a dictation
/// does not pay to start the engine and load the model every time.
///
/// Measured on an M4 with a 6-second clip: 1.6s cold through the CLI, 0.6s through this,
/// for about 130 MB of memory. It listens on 127.0.0.1 only, so audio never leaves the Mac.
///
/// Everything here is an optimisation. If the server is off, still starting, or fails,
/// `transcribe` returns nil and the caller uses the CLI.
final class SpeechServer {
    static let shared = SpeechServer()

    /// Longer clips stay on the CLI, whose accuracy on long audio has been measured.
    static let maxSeconds: TimeInterval = 30

    struct Config: Equatable {
        var enabled: Bool
        var cliPath: String
        var modelPath: String
        var modelPrefix: String

        init(_ settings: Settings) {
            enabled = settings.keepEngineLoaded
            cliPath = settings.cliPath
            modelPath = settings.modelPath
            modelPrefix = settings.modelPrefix
        }
    }

    private let queue = DispatchQueue(label: "blarneykey.speech-server")
    private let lock = NSLock()
    private var process: Process?
    private var config: Config?
    private var generation = 0
    private var readyPort: Int?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private static var pidFile: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlarneyKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engine.pid")
    }

    private var port: Int? {
        lock.lock(); defer { lock.unlock() }
        return readyPort
    }

    private func setPort(_ value: Int?) {
        lock.lock(); readyPort = value; lock.unlock()
    }

    var isReady: Bool { port != nil }

    /// Starts, restarts or stops the server to match the settings. Cheap when nothing has
    /// changed, so it also runs before each dictation to revive a server that has died.
    func sync(_ settings: Settings) {
        let wanted = Config(settings)
        queue.async { [self] in
            if wanted == config, process?.isRunning == true { return }
            shutdown()
            config = wanted
            if wanted.enabled { launch(wanted) }
        }
    }

    func stop() {
        queue.sync { shutdown() }
    }

    private func shutdown() {
        generation += 1
        setPort(nil)
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    private func launch(_ config: Config) {
        guard FileManager.default.isExecutableFile(atPath: config.cliPath),
              FileManager.default.fileExists(atPath: config.modelPath) else { return }
        reapStray()

        let port = Int.random(in: 50_100...59_900)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: config.cliPath)
        child.arguments = [
            "serve",
            "--model-path", config.modelPath,
            "--model-prefix", config.modelPrefix,
            "--host", "127.0.0.1",
            "--port", String(port)
        ]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        generation += 1
        let mine = generation
        child.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard let self, self.generation == mine else { return }
                self.setPort(nil)
                self.process = nil
            }
        }
        do {
            try child.run()
        } catch {
            NSLog("BlarneyKey: could not start the speech server — \(error.localizedDescription)")
            return
        }
        process = child
        try? String(child.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)
        waitForHealth(port: port, generation: mine, attemptsLeft: 120)
    }

    private func waitForHealth(port: Int, generation mine: Int, attemptsLeft: Int) {
        guard generation == mine, attemptsLeft > 0,
              let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        session.dataTask(with: url) { [weak self] _, response, _ in
            guard let self else { return }
            self.queue.async {
                guard self.generation == mine else { return }
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    self.setPort(port)
                } else {
                    self.queue.asyncAfter(deadline: .now() + 0.5) {
                        self.waitForHealth(port: port, generation: mine, attemptsLeft: attemptsLeft - 1)
                    }
                }
            }
        }.resume()
    }

    /// A force-quit or crash skips the tidy shutdown, so clear what the last run left.
    /// Checks the command line first, in case the process ID now belongs to something else.
    private func reapStray() {
        guard let text = try? String(contentsOf: Self.pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else { return }
        let ps = Process()
        let out = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "command="]
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let command = String(data: data, encoding: .utf8) ?? ""
        if command.contains(" serve --model-path "), command.contains("--host 127.0.0.1") {
            kill(pid, SIGTERM)
        }
    }

    /// The transcript, or nil when the caller should use the CLI instead. Blocks, so call
    /// it off the main thread.
    func transcribe(_ audio: URL, language: String?, prompt: String?) -> String? {
        guard let port,
              let url = URL(string: "http://127.0.0.1:\(port)/v1/audio/transcriptions"),
              let wav = try? Data(contentsOf: audio) else { return nil }

        let boundary = "blarneykey-\(UUID().uuidString)"
        var fields = ["model": "whisper", "response_format": "json"]
        if let language, !language.isEmpty { fields["language"] = language }
        if let prompt { fields["prompt"] = prompt }

        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let done = DispatchSemaphore(value: 0)
        var result: String?
        session.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                NSLog("BlarneyKey: speech server failed, using the CLI — \(error?.localizedDescription ?? "bad response")")
                return
            }
            result = text
        }.resume()
        done.wait()
        return result
    }
}
