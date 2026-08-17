import SwiftUI

struct HomeView: View {
    @ObservedObject var store: Store
    @ObservedObject var dictation: DictationController
    @State private var appFilter: String? = nil

    private var stats: Store.Stats { store.weekStats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                statGrid
                activity
            }
            .padding(20)
        }
        .navigationTitle("BlarneyKey")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("100% ON-DEVICE")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))

            Text(greeting)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            Text("Hold \(store.settings.binding.shortLabel) and talk. It types where you're focused — privately, on your Mac.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(store.settings.binding.shortLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                    .foregroundStyle(.white)
                Text(store.settings.doubleTapToLock
                     ? "hold to dictate · double-tap to lock on"
                     : "hold to dictate")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.13, blue: 0.32),
                         Color(red: 0.36, green: 0.26, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
        return "Good \(part), \(name)"
    }

    // MARK: - Stats

    private var statGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(
                    title: "TIME SAVED",
                    value: Format.hours(stats.timeSaved(typingWPM: store.settings.typingWPM)),
                    caption: "this week",
                    footnote: "vs typing at \(Int(store.settings.typingWPM)) wpm",
                    symbol: "hourglass",
                    colors: [Color(red: 0.55, green: 0.36, blue: 0.93),
                             Color(red: 0.70, green: 0.48, blue: 0.98)]
                )
                StatCard(
                    title: "SPEAKING SPEED",
                    value: String(format: "%.1f×", stats.speedMultiple(typingWPM: store.settings.typingWPM)),
                    caption: "this week",
                    footnote: "faster than typing · ≈\(Int(stats.wordsPerMinute)) wpm",
                    symbol: "bolt.fill",
                    colors: [Color(red: 0.90, green: 0.60, blue: 0.28),
                             Color(red: 0.95, green: 0.72, blue: 0.38)]
                )
            }
            HStack(spacing: 12) {
                StatCard(
                    title: "SESSIONS",
                    value: "\(stats.sessions)",
                    caption: "this week",
                    footnote: stats.streakDays > 0 ? "🔥 \(stats.streakDays)-day streak" : nil,
                    symbol: "mic",
                    colors: [Color(red: 0.31, green: 0.46, blue: 0.90),
                             Color(red: 0.45, green: 0.60, blue: 0.96)]
                )
                StatCard(
                    title: "WORDS",
                    value: Format.count(stats.words),
                    caption: "this week",
                    footnote: nil,
                    symbol: "text.alignleft",
                    colors: [Color(red: 0.80, green: 0.34, blue: 0.48),
                             Color(red: 0.88, green: 0.47, blue: 0.58)]
                )
                StatCard(
                    title: "AVG. SESSION",
                    value: Format.seconds(stats.averageSession),
                    caption: "this week",
                    footnote: nil,
                    symbol: "clock",
                    colors: [Color(red: 0.28, green: 0.62, blue: 0.62),
                             Color(red: 0.42, green: 0.74, blue: 0.72)]
                )
            }
        }
    }

    // MARK: - Recent activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent activity").font(.title3.weight(.semibold))
                Spacer()
                Text("\(store.sessions.count) total")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !store.appsInHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", selected: appFilter == nil) { appFilter = nil }
                        ForEach(store.appsInHistory.prefix(8), id: \.self) { name in
                            chip(name, selected: appFilter == name) { appFilter = name }
                        }
                    }
                }
            }

            if filtered.isEmpty {
                Text("Nothing yet. Hold \(store.settings.binding.shortLabel) and say something.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(days, id: \.self) { day in
                    DayGroup(day: day, sessions: grouped[day] ?? [],
                             expanded: day == Calendar.current.startOfDay(for: Date()))
                }
            }
        }
    }

    private var filtered: [Session] {
        guard let appFilter else { return store.sessions }
        return store.sessions.filter { $0.appName == appFilter }
    }

    private var grouped: [Date: [Session]] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
    }

    private var days: [Date] { grouped.keys.sorted(by: >) }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? AnyShapeStyle(.tint.opacity(0.18))
                                     : AnyShapeStyle(.quaternary.opacity(0.6)),
                            in: Capsule())
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pieces

private struct DayGroup: View {
    let day: Date
    let sessions: [Session]
    let expanded: Bool
    @State private var isOpen: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isOpen ?? expanded },
            set: { isOpen = $0 }
        )) {
            VStack(spacing: 0) {
                ForEach(sessions) { SessionRow(session: $0) }
            }
        } label: {
            HStack {
                Text(Format.day(day)).font(.callout.weight(.medium))
                Spacer()
                Text("\(sessions.count)")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Format.time(session.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Image(systemName: session.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(session.succeeded ? Color.green : Color.orange)
                .font(.caption)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.text.isEmpty ? "(no text)" : session.text)
                    .font(.callout)
                    .foregroundStyle(session.succeeded ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    tag(session.appName, tint: .secondary)
                    Text("\(Format.seconds(session.duration)) · \(session.wordCount) words")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let failure = session.failure {
                        tag(failure, tint: .orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(tint == .orange ? Color.orange : Color.secondary)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    let footnote: String?
    let symbol: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: symbol).foregroundStyle(.white.opacity(0.8))
            }
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 4)
            Text(caption).font(.caption).foregroundStyle(.white.opacity(0.85))
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

// MARK: - Formatting

enum Format {
    static func hours(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%.1f h", seconds / 3600)
    }

    static func seconds(_ value: TimeInterval) -> String {
        value >= 60
            ? String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
            : String(format: "%.1f s", value)
    }

    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today · " + date.formatted(.dateTime.month(.wide).day())
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday · " + date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day())
    }
}
