import SwiftUI

struct HomeView: View {
    @ObservedObject var store: Store
    @ObservedObject var dictation: DictationController
    @State private var appFilter: String? = nil

    private var stats: Store.Stats { store.weekStats }

    var body: some View {
        ScrollView {
            // Tiles stack edge to edge with no gap. The surface change is the divider —
            // no rules, no borders and no shadows between sections.
            VStack(spacing: 0) {
                heroTile
                statsTile
                activityTile
            }
        }
        .background(Theme.Colour.canvas)
        .navigationTitle("BlarneyKey")
    }

    // MARK: - Hero (dark tile)

    private var heroTile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("100% ON-DEVICE")
                .eyebrow(onDark: true)
                .reveal(0, aboveFold: true)

            Text(greeting)
                .font(Theme.Text.heroDisplay())
                .tracking(Theme.Text.Track.hero)
                .foregroundStyle(Theme.Colour.onDark)
                .reveal(1, aboveFold: true, blurred: true)

            Text("Hold \(store.settings.binding.shortLabel) and talk. It types where you're focused, privately, on your Mac.")
                .font(Theme.Text.lead())
                .tracking(Theme.Text.Track.body)
                .foregroundStyle(Theme.Colour.bodyMuted)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(2, aboveFold: true, blurred: true)

            HStack(spacing: Theme.Space.sm) {
                Text(store.settings.binding.shortLabel)
                    .font(Theme.Text.captionStrong())
                    .foregroundStyle(Theme.Colour.onDark)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.Colour.tile2))
                    .overlay(Capsule().strokeBorder(Theme.Colour.onDarkFaint.opacity(0.3)))

                Text(store.settings.doubleTapToLock
                     ? "hold to dictate · double-tap to lock on"
                     : "hold to dictate")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.onDarkFaint)
            }
            .padding(.top, Theme.Space.xxs)
            .reveal(3, aboveFold: true)
        }
        .padding(Theme.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colour.tile1)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
        return "Good \(part), \(name)"
    }

    // MARK: - Stats (light tile)

    private var statsTile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("THIS WEEK").eyebrow().reveal(0)

            HStack(alignment: .top, spacing: Theme.Space.md) {
                StatCard(
                    label: "TIME SAVED",
                    value: Format.hours(stats.timeSaved(typingWPM: store.settings.typingWPM)),
                    footnote: "against typing at \(Int(store.settings.typingWPM)) wpm"
                )
                .reveal(1)

                StatCard(
                    label: "SPEAKING SPEED",
                    value: String(format: "%.1f×", stats.speedMultiple(typingWPM: store.settings.typingWPM)),
                    footnote: "≈\(Int(stats.wordsPerMinute)) words a minute"
                )
                .reveal(2)

                StatCard(
                    label: "WORDS",
                    value: Format.count(stats.words),
                    footnote: stats.sessions == 1 ? "across 1 session" : "across \(stats.sessions) sessions"
                )
                .reveal(3)
            }

            HStack(alignment: .top, spacing: Theme.Space.md) {
                StatCard(
                    label: "AVERAGE SESSION",
                    value: Format.seconds(stats.averageSession),
                    footnote: "of speaking per go"
                )
                .reveal(4)

                StatCard(
                    label: "STREAK",
                    value: stats.streakDays > 0 ? "\(stats.streakDays) days" : "—",
                    footnote: stats.streakDays > 0 ? "consecutive days dictating" : "no streak yet"
                )
                .reveal(5)

                StatCard(
                    label: "TODAY",
                    value: "\(store.sessionsToday)",
                    footnote: store.sessionsToday == 1 ? "session so far" : "sessions so far"
                )
                .reveal(6)
            }
        }
        .padding(Theme.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colour.canvas)
    }

    // MARK: - Activity (parchment tile)

    private var activityTile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent activity")
                    .font(Theme.Text.displayMd())
                    .tracking(Theme.Text.Track.display)
                    .foregroundStyle(Theme.Colour.ink)
                Spacer()
                Text("\(store.sessions.count) total")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }
            .reveal(0)

            if !store.appsInHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.xs) {
                        chip("All", selected: appFilter == nil) { appFilter = nil }
                        ForEach(store.appsInHistory.prefix(8), id: \.self) { name in
                            chip(name, selected: appFilter == name) { appFilter = name }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .reveal(1)
            }

            if filtered.isEmpty {
                Text("Nothing yet. Hold \(store.settings.binding.shortLabel) and say something.")
                    .font(Theme.Text.body())
                    .foregroundStyle(Theme.Colour.inkMuted48)
                    .padding(.vertical, Theme.Space.lg)
                    .reveal(2)
            } else {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(Array(days.enumerated()), id: \.element) { offset, day in
                        DayGroup(
                            day: day,
                            sessions: grouped[day] ?? [],
                            startsOpen: offset == 0
                        )
                        .reveal(min(offset + 2, 5))
                    }
                }
            }
        }
        .padding(Theme.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colour.parchment)
    }

    private var filtered: [Session] {
        guard let appFilter else { return store.sessions }
        return store.sessions.filter { $0.appName == appFilter }
    }

    private var grouped: [Date: [Session]] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
    }

    private var days: [Date] { grouped.keys.sorted(by: >) }

    /// The configurator option chip: pill, white, ink text. Selecting upgrades the ring to
    /// 2pt Focus Blue rather than filling the chip with colour.
    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Text.caption())
                .foregroundStyle(Theme.Colour.ink)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.Colour.canvas))
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Theme.Colour.primaryFocus : Theme.Colour.hairline,
                        lineWidth: selected ? 2 : 1
                    )
                )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Stat card

/// The store utility card: white, 18pt radius, 1pt hairline, 24pt padding, no shadow.
/// The number carries the weight through type, not through a coloured fill.
struct StatCard: View {
    let label: String
    let value: String
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(label).eyebrow()

            Text(value)
                .font(Theme.Text.statNumber())
                .tracking(Theme.Text.Track.hero)
                .foregroundStyle(Theme.Colour.ink)
                .monospacedDigit()
                .padding(.top, 2)

            if let footnote {
                Text(footnote)
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .cardSurface()
    }
}

// MARK: - Activity rows

private struct DayGroup: View {
    let day: Date
    let sessions: [Session]
    let startsOpen: Bool
    @State private var isOpen: Bool?

    var body: some View {
        let open = isOpen ?? startsOpen

        VStack(spacing: 0) {
            Button {
                withAnimation(Theme.Motion.stateChange) { isOpen = !open }
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(Format.day(day))
                        .font(Theme.Text.bodyStrong())
                        .tracking(Theme.Text.Track.body)
                        .foregroundStyle(Theme.Colour.ink)
                    Spacer()
                    Text("\(sessions.count)")
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .monospacedDigit()
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.Colour.dividerSoft)
                                .frame(height: 1)
                                .padding(.leading, Theme.Space.md)
                        }
                        SessionRow(session: session)
                    }
                }
            }
        }
        .cardSurface()
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(Format.time(session.date))
                .font(Theme.Text.caption())
                .monospacedDigit()
                .foregroundStyle(Theme.Colour.inkMuted48)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(session.text.isEmpty ? "No text" : session.text)
                    .font(Theme.Text.body())
                    .tracking(Theme.Text.Track.body)
                    .foregroundStyle(session.succeeded ? Theme.Colour.ink : Theme.Colour.inkMuted48)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Text(session.appName)
                    Text("·").foregroundStyle(Theme.Colour.hairline)
                    Text("\(Format.seconds(session.duration)) · \(session.wordCount) words")
                        .monospacedDigit()
                }
                .font(Theme.Text.caption())
                .foregroundStyle(Theme.Colour.inkMuted48)

                // Colour is rationed: a successful row gets no status glyph at all, so the
                // eye only stops where something actually needs attention.
                if let failure = session.failure {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(failure).font(Theme.Text.caption())
                    }
                    .foregroundStyle(Theme.Colour.warn)
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }
}

// MARK: - Formatting

enum Format {
    static func hours(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        return String(format: "%.1f h", seconds / 3600)
    }

    static func seconds(_ value: TimeInterval) -> String {
        value >= 60
            ? String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
            : String(format: "%.1fs", value)
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
