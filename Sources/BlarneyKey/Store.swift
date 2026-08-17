import AppKit
import Combine

/// Everything the app remembers, in one JSON file under
/// ~/Library/Application Support/BlarneyKey/state.json
final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings = Settings()
    @Published var allowedApps: [AllowedApp] = []
    @Published var snippets: [Snippet] = []
    @Published private(set) var sessions: [Session] = []

    /// Keep the history bounded so the file stays small and the UI stays quick.
    private let historyLimit = 5_000
    private var saveWorkItem: DispatchWorkItem?

    private struct Persisted: Codable {
        var settings: Settings
        var allowedApps: [AllowedApp]
        var snippets: [Snippet]
        var sessions: [Session]
    }

    private static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlarneyKey", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            allowedApps = Self.defaultAllowlist()
            snippets = Self.defaultSnippets()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(Persisted.self, from: data) else {
            NSLog("BlarneyKey: state.json could not be read; starting fresh")
            allowedApps = Self.defaultAllowlist()
            snippets = Self.defaultSnippets()
            return
        }
        settings = state.settings
        allowedApps = state.allowedApps
        snippets = state.snippets
        sessions = state.sessions
    }

    /// Coalesces rapid changes — SwiftUI toggles fire a lot.
    func save() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func writeNow() {
        let state = Persisted(
            settings: settings,
            allowedApps: allowedApps,
            snippets: snippets,
            sessions: Array(sessions.prefix(historyLimit))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(state)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("BlarneyKey: could not save state — \(error.localizedDescription)")
        }
    }

    // MARK: - Mutations

    /// Newest first, which is the order every view wants.
    func record(_ session: Session) {
        sessions.insert(session, at: 0)
        if sessions.count > historyLimit { sessions.removeLast(sessions.count - historyLimit) }
        save()
    }

    func allows(bundleID: String) -> Bool {
        if settings.allowAllApps { return true }
        return allowedApps.contains { $0.bundleID == bundleID }
    }

    func shouldFormat(bundleID: String) -> Bool {
        if settings.cleanupEverywhere { return true }
        return allowedApps.first { $0.bundleID == bundleID }?.formatEnabled ?? false
    }

    func addApp(bundleID: String, name: String? = nil) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !allowedApps.contains(where: { $0.bundleID == id }) else { return }
        allowedApps.append(AllowedApp(bundleID: id, name: name ?? Self.displayName(for: id) ?? id))
        save()
    }

    func removeApp(_ app: AllowedApp) {
        allowedApps.removeAll { $0.bundleID == app.bundleID }
        save()
    }

    func upsert(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        save()
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func clearHistory() {
        sessions.removeAll()
        writeNow()
    }

    // MARK: - Defaults

    private static func defaultAllowlist() -> [AllowedApp] {
        let seeds = [
            "com.apple.Notes", "com.apple.mail", "com.apple.MobileSMS",
            "com.apple.Safari", "com.google.Chrome", "com.apple.Terminal",
            "com.tinyspeck.slackmacgap", "notion.id"
        ]
        return seeds.map { AllowedApp(bundleID: $0, name: displayName(for: $0) ?? $0) }
    }

    private static func defaultSnippets() -> [Snippet] {
        // The trailing spaces after each dash are deliberate: they leave the cursor ready
        // to type, and are written as escapes so no editor strips them.
        [Snippet(
            trigger: "Get Things Done",
            expansion: """
                ## Whats the next action?

                **Do it now:**
                -\u{0020}

                **Delegate:**
                -\u{0020}

                **Defer:**
                -\u{0020}

                **Archive**
                -\u{0020}
                """
        )]
    }

    /// Ask Launch Services what an app is called, so the list reads properly.
    static func displayName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Stats

extension Store {
    struct Stats {
        var sessions = 0
        var words = 0
        var speakingSeconds: TimeInterval = 0
        var streakDays = 0

        var averageSession: TimeInterval { sessions == 0 ? 0 : speakingSeconds / Double(sessions) }

        var wordsPerMinute: Double {
            speakingSeconds <= 0 ? 0 : Double(words) / (speakingSeconds / 60)
        }

        /// How much longer typing the same words would have taken.
        func timeSaved(typingWPM: Double) -> TimeInterval {
            guard typingWPM > 0, words > 0 else { return 0 }
            let typingSeconds = Double(words) / typingWPM * 60
            return max(0, typingSeconds - speakingSeconds)
        }

        func speedMultiple(typingWPM: Double) -> Double {
            typingWPM <= 0 ? 0 : wordsPerMinute / typingWPM
        }
    }

    /// Stats for the last 7 days, counting only sessions whose text actually landed.
    var weekStats: Stats {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = sessions.filter { $0.date >= cutoff && $0.succeeded }

        var stats = Stats()
        stats.sessions = recent.count
        stats.words = recent.reduce(0) { $0 + $1.wordCount }
        stats.speakingSeconds = recent.reduce(0) { $0 + $1.duration }
        stats.streakDays = currentStreak
        return stats
    }

    var sessionsToday: Int {
        sessions.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    /// Consecutive days up to today (or yesterday, so a quiet morning doesn't reset it).
    var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// App names seen in the history, most used first — the filter chips.
    var appsInHistory: [String] {
        var counts: [String: Int] = [:]
        for session in sessions where !session.appName.isEmpty {
            counts[session.appName, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }
}
