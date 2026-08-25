import AppKit
import Combine

/// Everything the app remembers, in one JSON file under
/// ~/Library/Application Support/BlarneyKey/state.json
final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings = Settings()
    @Published var allowedApps: [AllowedApp] = []
    @Published var prompts: [Prompt] = []
    @Published private(set) var sessions: [Session] = []

    /// Keep the history bounded so the file stays small and the UI stays quick.
    private let historyLimit = 5_000
    private var saveWorkItem: DispatchWorkItem?

    private struct Persisted: Codable {
        var settings: Settings
        var allowedApps: [AllowedApp]
        var prompts: [Prompt]
        var sessions: [Session]

        /// Prompts were called snippets until 2026-08-25. The key on disk keeps the old
        /// name, so an existing state.json still decodes instead of resetting to defaults.
        enum CodingKeys: String, CodingKey {
            case settings, allowedApps, sessions
            case prompts = "snippets"
        }
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
            prompts = Self.defaultPrompts()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(Persisted.self, from: data) else {
            NSLog("BlarneyKey: state.json could not be read; starting fresh")
            allowedApps = Self.defaultAllowlist()
            prompts = Self.defaultPrompts()
            return
        }
        settings = state.settings
        allowedApps = state.allowedApps
        prompts = state.prompts
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
            prompts: prompts,
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

    func upsert(_ prompt: Prompt) {
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
        } else {
            prompts.append(prompt)
        }
        save()
    }

    func remove(_ prompt: Prompt) {
        prompts.removeAll { $0.id == prompt.id }
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

    private static func defaultPrompts() -> [Prompt] {
        // The trailing spaces after each dash are deliberate: they leave the cursor ready
        // to type, and are written as escapes so no editor strips them.
        [Prompt(
            trigger: "Get Things Done",
            expansion: """
                ## What's the next action?

                **Do it now:**
                -\u{0020}

                **Delegate:**
                -\u{0020}

                **Defer:**
                -\u{0020}

                **Archive:**
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

/// The time window the dashboard is currently looking at.
enum StatsRange: String, CaseIterable, Identifiable, Codable {
    case today, week, month, year, allTime
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .allTime: return "All time"
        }
    }

    /// Nil means no cutoff — all history.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.date(byAdding: .day, value: -7, to: now)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .allTime: return nil
        }
    }

    /// The bucket size used when charting this range as a series.
    var bucket: Calendar.Component {
        switch self {
        case .today: return .hour
        case .week, .month: return .day
        case .year, .allTime: return .month
        }
    }

    /// How a hovered point's date is labelled in a chart tooltip.
    func pointLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch bucket {
        case .hour: formatter.dateFormat = "h a"
        case .day: formatter.dateFormat = self == .week ? "EEE d" : "MMM d"
        default: formatter.dateFormat = "MMM yyyy"
        }
        return formatter.string(from: date)
    }
}

/// Which per-session figure a card or sparkline is plotting.
enum StatMetric {
    case words, tokens, wordsPerMinute, timeSaved, sessionCount, averageSession
}

extension Store {
    struct Stats {
        var sessions = 0
        var words = 0
        var tokens = 0
        var speakingSeconds: TimeInterval = 0
        var streakDays = 0

        var averageSession: TimeInterval { sessions == 0 ? 0 : speakingSeconds / Double(sessions) }

        var wordsPerMinute: Double {
            speakingSeconds <= 0 ? 0 : Double(words) / (speakingSeconds / 60)
        }

        func count(for unit: WordUnit) -> Int { unit == .words ? words : tokens }

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

    /// Stats for a given time window, counting only sessions whose text actually landed.
    func stats(for range: StatsRange) -> Stats {
        let now = Date()
        let recent: [Session]
        if let cutoff = range.cutoff(from: now) {
            recent = sessions.filter { $0.date >= cutoff && $0.succeeded }
        } else {
            recent = sessions.filter(\.succeeded)
        }

        var stats = Stats()
        stats.sessions = recent.count
        stats.words = recent.reduce(0) { $0 + $1.wordCount }
        stats.tokens = recent.reduce(0) { $0 + $1.tokenCount }
        stats.speakingSeconds = recent.reduce(0) { $0 + $1.duration }
        stats.streakDays = currentStreak
        return stats
    }

    /// A bucketed trend line for a metric over a range — one point per bucket, oldest
    /// first, each keeping its bucket's start date so a chart can label a hovered
    /// point ("Tue 12", "3 PM", "Mar") instead of just plotting a shape.
    func seriesPoints(for range: StatsRange, metric: StatMetric) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let now = Date()
        let recent = sessions.filter { session in
            session.succeeded && (range.cutoff(from: now).map { session.date >= $0 } ?? true)
        }

        // Buckets align to calendar boundaries (start of hour/day/month) and the last one is
        // always the current period — this hour, today, this month — so today's activity is
        // the final point on every range rather than falling off the end.
        let component = range.bucket
        let end = bucketStart(now, component, calendar)

        let start: Date
        let bucketCount: Int
        switch range {
        case .today:
            // Only the hours elapsed so far, so the last point is the current hour.
            start = calendar.startOfDay(for: now)
            bucketCount = calendar.component(.hour, from: now) + 1
        case .week:
            bucketCount = 7
            start = calendar.date(byAdding: .day, value: -(bucketCount - 1), to: end) ?? end
        case .month:
            // One point per calendar day, spanning the same ~month window as the headline
            // figure and ending on today.
            let from = bucketStart(range.cutoff(from: now) ?? now, .day, calendar)
            bucketCount = (calendar.dateComponents([.day], from: from, to: end).day ?? 29) + 1
            start = from
        case .year:
            bucketCount = 12
            start = calendar.date(byAdding: .month, value: -(bucketCount - 1), to: end) ?? end
        case .allTime:
            start = bucketStart(recent.map(\.date).min() ?? now, .month, calendar)
            bucketCount = (calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1
        }
        let count = max(1, bucketCount)

        var buckets = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)

        for session in recent {
            // Bucket both ends on the same boundary so the difference is a clean bucket count.
            let bucketed = bucketStart(session.date, component, calendar)
            let distance = calendar.dateComponents([component], from: start, to: bucketed)
            let index = (component == .hour ? distance.hour : (component == .day ? distance.day : distance.month)) ?? -1
            guard index >= 0, index < count else { continue }

            switch metric {
            case .words: buckets[index] += Double(session.wordCount)
            case .tokens: buckets[index] += Double(session.tokenCount)
            case .wordsPerMinute:
                buckets[index] += session.duration > 0 ? Double(session.wordCount) / (session.duration / 60) : 0
                counts[index] += 1
            case .timeSaved:
                let typingWPM = settings.typingWPM
                if typingWPM > 0, session.wordCount > 0 {
                    let typingSeconds = Double(session.wordCount) / typingWPM * 60
                    buckets[index] += max(0, typingSeconds - session.duration)
                }
            case .sessionCount: buckets[index] += 1
            case .averageSession:
                buckets[index] += session.duration
                counts[index] += 1
            }
        }

        // Average-based metrics need dividing by how many sessions landed in each bucket.
        if metric == .wordsPerMinute || metric == .averageSession {
            for i in buckets.indices where counts[i] > 0 {
                buckets[i] /= Double(counts[i])
            }
        }

        let dates = (0..<count).map { index in
            calendar.date(byAdding: component, value: index, to: start) ?? start
        }
        return zip(dates, buckets).map { (date: $0, value: $1) }
    }

    /// Truncates a date to the start of its hour, day or month, so buckets line up on real
    /// calendar boundaries instead of drifting with the time of day.
    private func bucketStart(_ date: Date, _ component: Calendar.Component, _ calendar: Calendar) -> Date {
        switch component {
        case .hour: return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        case .day: return calendar.startOfDay(for: date)
        case .month: return calendar.dateInterval(of: .month, for: date)?.start ?? date
        default: return date
        }
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

    /// The longest run of consecutive dictating days ever recorded.
    var longestStreak: Int {
        let calendar = Calendar.current
        let days = Set(sessions.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for i in 1..<days.count {
            if calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
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
