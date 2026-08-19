import SwiftUI

struct HomeView: View {
    @ObservedObject var store: Store
    @ObservedObject var dictation: DictationController
    @State private var appFilter: String? = nil
    @State private var range: StatsRange = .week

    private var stats: Store.Stats { store.stats(for: range) }
    private var unit: WordUnit { store.settings.wordUnit }

    private func points(_ metric: StatMetric) -> [SparklinePoint] {
        store.seriesPoints(for: range, metric: metric).map {
            SparklinePoint(label: range.pointLabel(for: $0.date), value: $0.value)
        }
    }

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
        .background(Theme.Colour.parchment)
        .navigationTitle("BlarneyKey")
    }

    // MARK: - Hero (dark tile)

    private var heroTile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(greeting)
                .font(Theme.Text.heroDisplay())
                .tracking(Theme.Text.Track.hero)
                .foregroundStyle(Theme.Colour.onDark)
                .reveal(0, aboveFold: true, blurred: true)

            Text("\(store.settings.bindingLabel) is your Blarney key. Hold it, talk, and the words land wherever your cursor is.")
                .font(Theme.Text.lead())
                .tracking(Theme.Text.Track.body)
                .foregroundStyle(Theme.Colour.bodyMuted)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(1, aboveFold: true, blurred: true)

            HStack(spacing: Theme.Space.sm) {
                Text(store.settings.bindingLabel)
                    .font(Theme.Text.captionStrong())
                    .foregroundStyle(Theme.Colour.onDark)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.Colour.tile2))
                    .overlay(Capsule().strokeBorder(Theme.Colour.onDarkFaint.opacity(0.3)))

                Text(store.settings.doubleTapToLock
                     ? "your Blarney key · hold to talk · double-tap to lock on"
                     : "your Blarney key · hold to talk")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.onDarkFaint)
            }
            .padding(.top, Theme.Space.xxs)
            .reveal(2, aboveFold: true)
        }
        .padding(Theme.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colour.tile1)
    }

    private var greeting: String {
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
        return "How's the form, \(name)?"
    }

    // MARK: - Stats (light tile)

    private var statsTile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            rangePicker.reveal(0)

            HStack(alignment: .top, spacing: Theme.Space.md) {
                StatCard(
                    label: "TIME SAVED",
                    value: Format.hours(stats.timeSaved(typingWPM: store.settings.typingWPM)),
                    footnote: "against typing at \(Int(store.settings.typingWPM)) wpm",
                    points: points(.timeSaved),
                    valueFormat: { Format.hours($0) },
                    chartKind: .bars
                )
                .reveal(1)

                StatCard(
                    label: "SPEAKING SPEED",
                    value: "\(Int(stats.wordsPerMinute)) wpm",
                    footnote: String(
                        format: "%.1f× faster than typing at %d wpm",
                        stats.speedMultiple(typingWPM: store.settings.typingWPM),
                        Int(store.settings.typingWPM)
                    ),
                    points: points(.wordsPerMinute),
                    valueFormat: { String(format: "%.0f wpm · %.1f×", $0, self.multiple(for: $0)) }
                )
                .reveal(2)

                StatCard(
                    label: unit == .words ? "WORDS" : "TOKENS",
                    value: Format.count(stats.count(for: unit)),
                    footnote: stats.sessions == 1 ? "across 1 session" : "across \(stats.sessions) sessions",
                    points: points(unit == .words ? .words : .tokens),
                    valueFormat: { Format.count(Int($0)) },
                    chartKind: .bars,
                    accessory: AnyView(unitPicker)
                )
                .reveal(3)
            }

            HStack(alignment: .top, spacing: Theme.Space.md) {
                StatCard(
                    label: "AVERAGE SESSION",
                    value: Format.seconds(stats.averageSession),
                    footnote: "of speaking per go",
                    points: points(.averageSession),
                    valueFormat: { Format.seconds($0) }
                )
                .reveal(4)

                StatCard(
                    label: "STREAK",
                    value: stats.streakDays > 0 ? "\(stats.streakDays) days" : "—",
                    footnote: stats.streakDays > 0
                        ? "best ever: \(store.longestStreak) days"
                        : "no streak yet"
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
        .background(Theme.Colour.parchment)
    }

    /// How many times faster than typing a given dictation wpm is — the multiplier
    /// shown next to a hovered Speaking Speed point.
    private func multiple(for wpm: Double) -> Double {
        let typingWPM = store.settings.typingWPM
        return typingWPM <= 0 ? 0 : wpm / typingWPM
    }

    /// Pill segmented control for the time window, styled like the app-filter chips
    /// rather than a native Picker, so it matches the rest of the custom control language.
    private var rangePicker: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(StatsRange.allCases) { option in
                chip(option.label.uppercased(), selected: range == option) {
                    withAnimation(Theme.Motion.stateChange) { range = option }
                }
            }
        }
    }

    /// Two-option pill switch for Words vs Tokens, persisted in Settings. Lives inside
    /// the Words card itself, since it only ever affects that one card.
    private var unitPicker: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(WordUnit.allCases) { option in
                chip(option.label.uppercased(), selected: unit == option) {
                    store.settings.wordUnit = option
                    store.save()
                }
            }
        }
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
                Text("Nothing here yet. Hold \(store.settings.bindingLabel) and say something.")
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
                .lineLimit(1)
                .fixedSize()
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
    /// Which visual fits the metric: a line for a rate sampled over time (speaking speed,
    /// average session), bars for a quantity that accumulates within each period (words,
    /// time saved) and resets to a new total each bucket.
    enum ChartKind { case line, bars }

    let label: String
    let value: String
    let footnote: String?
    var points: [SparklinePoint]? = nil
    var valueFormat: ((Double) -> String)? = nil
    var chartKind: ChartKind = .line
    /// An optional control scoped to this one card, e.g. the Words/Tokens toggle —
    /// lives beside the eyebrow rather than floating outside the card it affects.
    var accessory: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(label).eyebrow()
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.xxs)
                accessory
                    .layoutPriority(1)
            }

            Text(value)
                .font(Theme.Text.statNumber())
                .tracking(Theme.Text.Track.hero)
                .foregroundStyle(Theme.Colour.ink)
                .monospacedDigit()
                .padding(.top, 2)

            if let points, points.count > 1 {
                Group {
                    switch chartKind {
                    case .line:
                        Sparkline(
                            points: points,
                            valueFormat: valueFormat ?? { String(format: "%.0f", $0) }
                        )
                    case .bars:
                        MiniBars(
                            points: points,
                            valueFormat: valueFormat ?? { String(format: "%.0f", $0) }
                        )
                    }
                }
                .padding(.top, Theme.Space.xxs)
            }

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
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            summary
            if expanded { detail }
        }
    }

    private var summary: some View {
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
                    .lineLimit(expanded ? nil : 3)

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

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.Colour.inkMuted48)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .padding(.top, 4)

            CopyButton(text: session.text)
                .padding(.top, 1)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.Motion.stateChange) { expanded.toggle() } }
    }

    // MARK: - Expanded detail

    /// The full trace of one recording: the text at each stage, which model produced it,
    /// and how long that stage took. The Cleaned stage only appears when cleanup actually
    /// ran — with it off, there is no second model to show, so the row is omitted entirely.
    private var detail: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            stage("Raw",
                  text: session.rawText ?? session.text,
                  by: session.transcribeModel ?? Store.shared.settings.speechModelName,
                  device: session.inputDevice,
                  seconds: session.transcribeSeconds)
            if let cleaned = session.cleanedText, !cleaned.isEmpty {
                stage("Cleaned",
                      text: cleaned,
                      by: session.cleanModel ?? Cleanup.modelName,
                      seconds: session.cleanSeconds)
            }
            stage("Final",
                  text: session.text,
                  by: deliveryLabel,
                  seconds: session.pasteSeconds)

            Rectangle()
                .fill(Theme.Colour.dividerSoft)
                .frame(height: 1)
                .padding(.vertical, 2)

            valueRow("Focused app", session.bundleID.isEmpty ? session.appName : session.bundleID)
            valueRow("Captured", "\(Format.latency(session.duration))s of audio")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, Theme.Space.md)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One stage of the pipeline: an eyebrow, the model that produced it and how long it
    /// took on the same line, then the monospaced text with its own copy button.
    private func stage(_ label: String,
                       text: String?,
                       by producer: String?,
                       device: String? = nil,
                       seconds: TimeInterval?) -> some View {
        let value = (text?.isEmpty == false) ? text : nil
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(label).eyebrow()
                if value != nil, let meta = stageMeta(by: producer, device: device, seconds: seconds) {
                    Text(meta)
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Space.xs)
                if let value { CopyButton(text: value) }
            }
            Text(value ?? "—")
                .font(.system(size: 12, design: value == nil ? .default : .monospaced))
                .foregroundStyle(value == nil ? Theme.Colour.inkMuted48 : Theme.Colour.inkMuted80)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "WhisperKit · distil · MacBook Pro Microphone · 2.36s" — the model, the microphone it
    /// heard, and how long it took, any of which may be missing on an older session that
    /// predates recording them.
    private func stageMeta(by producer: String?, device: String? = nil, seconds: TimeInterval?) -> String? {
        var parts: [String] = []
        if let producer, !producer.isEmpty { parts.append(producer) }
        if let device, !device.isEmpty { parts.append(device) }
        if let seconds { parts.append("\(Format.latency(seconds))s") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How the final text left BlarneyKey, phrased as the actor of that last stage.
    private var deliveryLabel: String? {
        switch session.destination {
        case "paste": return "pasted"
        case "type": return "typed out"
        case "clipboard": return "copied to clipboard"
        default: return session.destination
        }
    }

    private func valueRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            detailLabel(label)
            Text((value?.isEmpty == false) ? value! : "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Colour.inkMuted80)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func detailLabel(_ label: String) -> some View {
        Text(label)
            .font(Theme.Text.caption())
            .foregroundStyle(Theme.Colour.inkMuted48)
            .frame(width: 84, alignment: .leading)
            .padding(.top, 1)
    }
}

/// Copies a transcript back to the clipboard. Confirms in place rather than with a
/// notification, since the click and the feedback belong in the same spot.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(Theme.Motion.interaction) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(Theme.Motion.interaction) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? Theme.Colour.ok : Theme.Colour.inkMuted48)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(text.isEmpty)
        .help(copied ? "Copied" : "Copy this text")
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

    /// Two-decimal seconds for the per-stage latency line, e.g. "2.36".
    static func latency(_ value: TimeInterval) -> String {
        String(format: "%.2f", value)
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
