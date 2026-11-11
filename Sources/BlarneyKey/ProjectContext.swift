import AppKit

/// Works out which code project you are dictating into, so spoken filenames can become
/// `@path` references and the speech model can expect the project's own names.
enum ProjectContext {
    /// Only where an `@path` means something. In a document it would just be odd text.
    private static let codingApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "dev.zed.Zed"
    ]

    /// The folder shown by the focused window, read through Accessibility. Terminal reports
    /// the shell's working directory here; editors report the open file.
    static func folder(of app: NSRunningApplication?) -> URL? {
        guard let app, let id = app.bundleIdentifier, codingApps.contains(id) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXDocumentAttribute as CFString, &document) == .success,
              let text = document as? String, let url = URL(string: text), url.isFileURL else { return nil }
        return url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }
}

/// The tracked files of one git repository, as seen from the folder you are working in.
struct ProjectFiles {
    /// Paths relative to the working folder, using `../` to climb when needed.
    var paths: [String]
    /// Names from recently changed files, for the speech model to expect.
    var names: [String]

    private static let cacheSeconds: TimeInterval = 60
    private static let maxNames = 15
    private static let lock = NSLock()
    private static var cache: [String: (loaded: Date, files: ProjectFiles)] = [:]

    /// Nil outside a git repository. Blocks on git, so call it off the main thread.
    static func load(folder: URL) -> ProjectFiles? {
        let key = folder.path
        lock.lock()
        if let hit = cache[key], Date().timeIntervalSince(hit.loaded) < cacheSeconds {
            lock.unlock()
            return hit.files
        }
        lock.unlock()

        guard let root = git(["rev-parse", "--show-toplevel"], in: folder)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty,
              let listing = git(["ls-files"], in: URL(fileURLWithPath: root)) else { return nil }

        let working = URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let paths = listing.split(separator: "\n").map {
            relative(path: resolvedRoot + "/" + String($0), from: working)
        }
        let recent = git(["log", "-n", "30", "--name-only", "--format="],
                         in: URL(fileURLWithPath: root)) ?? ""
        let files = ProjectFiles(paths: paths, names: distinctiveNames(from: recent))

        lock.lock(); cache[key] = (Date(), files); lock.unlock()
        return files
    }

    /// File stems that are not plain words, such as `DictationController` or `hq_panel`.
    /// A plain word like `store` gains nothing from being listed.
    static func distinctiveNames(from listing: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for line in listing.split(separator: "\n") {
            let stem = ((String(line) as NSString).lastPathComponent as NSString).deletingPathExtension
            let distinctive = stem.contains("_") || stem.dropFirst().contains(where: \.isUppercase)
            guard stem.count >= 4, distinctive, !stem.hasPrefix("."), stem != stem.uppercased(),
                  seen.insert(stem).inserted else { continue }
            names.append(stem)
            if names.count == maxNames { break }
        }
        return names
    }

    static func relative(path: String, from folder: String) -> String {
        let target = path.split(separator: "/")
        let base = folder.split(separator: "/")
        var shared = 0
        while shared < target.count, shared < base.count, target[shared] == base[shared] { shared += 1 }
        let climbs = Array(repeating: "..", count: base.count - shared)
        return (climbs + target[shared...].map(String.init)).joined(separator: "/")
    }

    private static func git(_ arguments: [String], in folder: URL) -> String? {
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Turns a spoken filename into an `@path` reference.
///
/// It needs a clear signal, because "at" is an ordinary word: "at kb.py" and "at kb dot py"
/// count, as does "at file vocabulary" for a name with no extension. "Look at the store"
/// is left alone even when the project has a Store.swift.
enum FileTagger {
    private static let maxWords = 6

    static func apply(to text: String, paths: [String]) -> String {
        guard !paths.isEmpty,
              let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}_\\-./@]+") else { return text }
        let index = Index(paths)
        let source = text as NSString
        let tokens = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            trimmedRange($0.range, in: source)
        }
        let words = tokens.map { source.substring(with: $0) }

        var replacements: [(NSRange, String)] = []
        var position = 0
        while position < words.count {
            if let found = match(at: position, words: words, index: index) {
                let range = NSUnionRange(tokens[position], tokens[found.lastWord])
                replacements.append((range, "@" + found.path))
                position = found.lastWord + 1
            } else {
                position += 1
            }
        }

        let result = NSMutableString(string: text)
        for (range, value) in replacements.reversed() {
            result.replaceCharacters(in: range, with: value)
        }
        return result as String
    }

    private static func match(at position: Int, words: [String], index: Index)
        -> (lastWord: Int, path: String)? {
        var names = words
        var start = position
        if words[position].hasPrefix("@"), words[position].count > 1 {
            names[position] = String(words[position].dropFirst())
        } else if ["at", "@"].contains(words[position].lowercased()) {
            start = position + 1
            if start < words.count, words[start].lowercased() == "file" {
                return longest(from: start + 1, names: names, lookup: index.byStem, requireDot: false)
            }
        } else {
            return nil
        }
        return longest(from: start, names: names, lookup: index.byName, requireDot: true)
    }

    /// Tries the longest run of words first, so "store view" beats "store".
    private static func longest(from start: Int, names: [String], lookup: [String: [String]],
                                requireDot: Bool) -> (lastWord: Int, path: String)? {
        guard start < names.count else { return nil }
        let last = min(start + maxWords, names.count) - 1
        for end in stride(from: last, through: start, by: -1) {
            let phrase = names[start...end]
            if requireDot, !phrase.contains(where: { $0.contains(".") || $0.lowercased() == "dot" }) {
                continue
            }
            let key = normalise(phrase.filter { $0.lowercased() != "dot" }.joined())
            if let candidates = lookup[key], let path = best(candidates) { return (end, path) }
        }
        return nil
    }

    /// Prefers files inside the working folder, then the shallowest. A tie is a guess, so
    /// it picks nothing and leaves your words as spoken.
    private static func best(_ candidates: [String]) -> String? {
        func rank(_ path: String) -> (Int, Int) {
            (path.hasPrefix("../") ? 1 : 0, path.split(separator: "/").count)
        }
        let sorted = candidates.sorted { rank($0) < rank($1) }
        if sorted.count > 1, rank(sorted[0]) == rank(sorted[1]) { return nil }
        return sorted.first
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Drops sentence punctuation the token pattern picked up, such as the end of "kb.py."
    private static func trimmedRange(_ range: NSRange, in source: NSString) -> NSRange {
        var length = range.length
        while length > 1, source.substring(with: NSRange(location: range.location + length - 1, length: 1)) == "." {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private struct Index {
        var byName: [String: [String]] = [:]
        var byStem: [String: [String]] = [:]

        init(_ paths: [String]) {
            for path in paths {
                let name = (path as NSString).lastPathComponent
                let stem = (name as NSString).deletingPathExtension
                byName[normalise(name), default: []].append(path)
                byStem[normalise(stem), default: []].append(path)
            }
        }
    }
}
