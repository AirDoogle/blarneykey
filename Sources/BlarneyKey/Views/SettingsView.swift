import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var capturingKey = false
    @State private var testCountdown = 0

    var body: some View {
        Page(
            title: "Settings",
            lead: "Audio never leaves your Mac. Transcription runs on the Neural Engine."
        ) {
            appearanceSection
            hotkeySection
            insertionSection
            cleanupSection
            speechSection
            modelSection
            privacySection
        }
        .sheet(isPresented: $capturingKey) {
            KeyCaptureSheet(current: store.settings.primaryBinding,
                            existing: store.settings.bindings) { binding in
                if !store.settings.bindings.contains(binding) {
                    store.settings.bindings.append(binding)
                    store.save()
                }
                capturingKey = false
            } onCancel: {
                capturingKey = false
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section_(label: "GENERAL", index: 1) {
            Row(title: "Start at login", detail: LoginItem.statusDescription) {
                Toggle("", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { wanted in
                        // Show what macOS actually did, not what was asked for.
                        store.settings.launchAtLogin = LoginItem.set(wanted)
                        store.save()
                    }
                ))
                .labelsHidden()
            }
            RowDivider()
            Row(title: "Theme", detail: "Dark tiles stay dark in both, by design.") {
                Picker("", selection: binding(\.appearance)) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 148)
            }
        }
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        Section_(label: "BLARNEYKEY", index: 2) {
            Row(
                title: "Your Blarney keys",
                detail: store.settings.doubleTapToLock
                    ? "Hold any of them to talk, or double-tap to lock dictation on. Tap again, press Escape, or click stop on the pill."
                    : "Hold any of them to talk."
            ) {
                Button("Add a key") { capturingKey = true }
                    .buttonStyle(PillButtonStyle())
            }

            ForEach(Array(store.settings.bindings.enumerated()), id: \.element) { index, key in
                RowDivider()
                keyRow(key, index: index)
            }

            if store.settings.bindings.isEmpty {
                RowDivider()
                Note(kind: .warn,
                     text: "No keys set up, so nothing starts dictation. Add one, or use Start dictation in the menu bar.")
            }

            RowDivider()
            Note(kind: .plain,
                 text: "More than one is useful when your keyboards differ: a spare key on an external board, and something like Right \u{2325} on the built-in one.")

            RowDivider()
            toggle("Double-tap to lock on",
                   detail: "Keeps recording after you let go, for longer dictation.",
                   path: \.doubleTapToLock)
            RowDivider()
            toggle("Show the floating pill",
                   detail: "A small indicator with the live level and a stop button.",
                   path: \.showPill)
            RowDivider()
            toggle("Play start and stop sounds", detail: nil, path: \.playSounds)
        }
    }

    /// One configured key: what it is, why it might misbehave, and how to remove it.
    private func keyRow(_ key: KeyBinding, index: Int) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(key.shortLabel)
                .font(Theme.Text.captionStrong())
                .foregroundStyle(Theme.Colour.ink)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.Colour.parchment))

            VStack(alignment: .leading, spacing: 1) {
                Text(key.label)
                    .font(Theme.Text.body())
                    .foregroundStyle(Theme.Colour.ink)
                if let caveat = key.caveat {
                    Text(caveat)
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Space.sm)

            if index == 0 {
                Text("shown in the app")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            Button {
                store.settings.bindings.removeAll { $0 == key }
                store.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(store.settings.bindings.count <= 1)
            .help(store.settings.bindings.count <= 1
                  ? "Keep at least one key"
                  : "Remove this key")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(minHeight: 44)
    }

    // MARK: - Insertion

    private var insertionSection: some View {
        Section_(label: "INSERTION", index: 3) {
            Row(title: "How text is inserted", detail: store.settings.insertionMode.detail) {
                Picker("", selection: binding(\.insertionMode)) {
                    ForEach(InsertionMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 148)
            }
            RowDivider()
            Row(
                title: "Test it",
                detail: testCountdown > 0
                    ? "Click into any text field now — inserting in \(testCountdown)…"
                    : "Inserts a known phrase after three seconds, so you can check insertion without speaking."
            ) {
                Button(testCountdown > 0 ? "\(testCountdown)…" : "Test insertion") {
                    runInsertionTest()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(testCountdown > 0)
            }
            RowDivider()
            Note(kind: .plain,
                 text: "If dictation records but nothing appears in an app, switch to Type it out. A few apps refuse a synthetic paste.")
        }
    }

    /// Counts down out loud so there is time to focus a text field in another app.
    private func runInsertionTest() {
        testCountdown = 3
        let mode = store.settings.insertionMode
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            testCountdown -= 1
            if testCountdown <= 0 {
                timer.invalidate()
                TextInserter.insert("BlarneyKey insertion test ✓", mode: mode)
            }
        }
    }

    // MARK: - Cleanup

    private var cleanupSection: some View {
        Section_(label: "CLEANUP", index: 4) {
            Row(
                title: "On-device cleanup",
                detail: Cleanup.unavailableReason
                    ?? "Polish transcripts with Apple Intelligence's on-device model. Runs locally; nothing leaves the device.",
                info: "Fixes punctuation and capitalisation, removes filler words like \"um\" and \"uh\", and drops false starts where you restarted a sentence — using Apple Intelligence's on-device model, so nothing leaves your Mac. It keeps your own wording and tone; it never answers, summarises or translates. If the cleaned-up text comes back a wildly different length, BlarneyKey keeps your original transcript instead."
            ) {
                if Cleanup.isAvailable {
                    Toggle("", isOn: binding(\.cleanupEverywhere)).labelsHidden()
                } else {
                    Text("Unavailable")
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Colour.pearl))
                        .overlay(Capsule().strokeBorder(Theme.Colour.hairline))
                }
            }
            if Cleanup.isAvailable {
                RowDivider()
                Note(kind: .plain,
                     text: "With this off, cleanup still runs for individual apps you switch Format on for in the Apps tab.")
            }
        }
    }

    // MARK: - Speech

    private var speechSection: some View {
        Section_(label: "SPEECH", index: 5) {
            Row(title: "Language", detail: "Leave empty to let the model detect it.") {
                TextField("en", text: Binding(
                    get: { store.settings.language ?? "" },
                    set: { store.settings.language = $0.isEmpty ? nil : $0; store.save() }
                ))
                .textFieldStyle(.roundedBorder)
                .font(Theme.Text.body())
                .frame(width: 64)
            }
            RowDivider()
            Row(title: "Minimum hold",
                detail: "Shorter taps are ignored, so a stray keypress does nothing.") {
                Stepper(value: binding(\.minimumDuration), in: 0.1...2.0, step: 0.05) {
                    Text(String(format: "%.2fs", store.settings.minimumDuration))
                        .font(Theme.Text.body())
                        .monospacedDigit()
                }
                .frame(width: 112)
            }
            RowDivider()
            Row(title: "Typing speed baseline", detail: "Used for the time-saved figure.") {
                Stepper(value: binding(\.typingWPM), in: 20...120, step: 5) {
                    Text("\(Int(store.settings.typingWPM)) wpm")
                        .font(Theme.Text.body())
                        .monospacedDigit()
                }
                .frame(width: 112)
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section_(label: "MODEL", index: 6) {
            Row(title: "Model folder", detail: store.settings.modelPath) {
                HStack(spacing: Theme.Space.xs) {
                    if modelReady {
                        Text("Ready")
                            .font(Theme.Text.captionStrong())
                            .foregroundStyle(Theme.Colour.ok)
                    } else {
                        Text("Missing")
                            .font(Theme.Text.captionStrong())
                            .foregroundStyle(Theme.Colour.warn)
                    }
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(
                            store.settings.modelPath, inFileViewerRootedAtPath: ""
                        )
                    }
                    .buttonStyle(UtilityButtonStyle())
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section_(label: "PRIVACY", index: 7) {
            Row(title: "History",
                detail: "\(store.sessions.count) sessions stored on this Mac, and nowhere else.") {
                Button("Clear") { store.clearHistory() }
                    .buttonStyle(UtilityButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private var modelReady: Bool {
        FileManager.default.fileExists(atPath: store.settings.modelPath)
    }

    /// Every setting writes through to disk on change, so there is no Save button.
    private func binding<Value>(_ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: path] },
            set: { store.settings[keyPath: path] = $0; store.save() }
        )
    }

    private func toggle(_ title: String, detail: String?,
                        path: WritableKeyPath<Settings, Bool>) -> some View {
        Row(title: title, detail: detail) {
            Toggle("", isOn: binding(path)).labelsHidden()
        }
    }
}
