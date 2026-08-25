import SwiftUI
import CoreAudio

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var capturingKey = false
    @State private var testCountdown = 0

    // Test-microphone state.
    @StateObject private var mic = MicTester()
    @State private var inputDevices: [AudioDevices.InputDevice] = []
    @State private var selectedInput: AudioDeviceID = 0
    @State private var inputVolume: Double = 0
    @State private var volumeSettable = false
    @State private var deviceObserver: InputDeviceObserver?

    var body: some View {
        Page(
            title: "Settings",
            lead: "Audio never leaves your Mac. Transcription runs on the Neural Engine."
        ) {
            appearanceSection
            hotkeySection
            insertionSection
            cleanupSection
            AppsSettings(store: store, index: 5)
            speechSection
            microphoneSection
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
        .onAppear {
            refreshDevices()
            // Follow the mic live: if the selected device is unplugged, macOS moves the
            // default (usually back to the built-in mic) and the picker updates to match.
            deviceObserver = InputDeviceObserver { devicesChanged() }
        }
        .onDisappear {
            mic.stop()
            deviceObserver?.stop()
            deviceObserver = nil
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
                     text: "With this off, cleanup still runs for individual apps you switch Format on under Apps below.")
            }
        }
    }

    // MARK: - Speech

    private var speechSection: some View {
        Section_(label: "SPEECH", index: 8) {
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

    // MARK: - Microphone

    private var microphoneSection: some View {
        Section_(label: "MICROPHONE", index: 9) {
            Row(
                title: "Input device",
                detail: "BlarneyKey records from your Mac's input device. Pick one here to set it and try it out."
            ) {
                if inputDevices.isEmpty {
                    Text("None found")
                        .font(Theme.Text.captionStrong())
                        .foregroundStyle(Theme.Colour.warn)
                } else {
                    Picker("", selection: Binding(
                        get: { selectedInput },
                        set: { id in
                            selectedInput = id
                            AudioDevices.setDefaultInput(id)
                            loadVolume()
                        }
                    )) {
                        ForEach(inputDevices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            if volumeSettable {
                RowDivider()
                Row(title: "Input volume", detail: "The system input gain for this microphone.") {
                    HStack(spacing: Theme.Space.xs) {
                        Slider(value: Binding(
                            get: { inputVolume },
                            set: { inputVolume = $0; AudioDevices.setInputVolume(Float($0), of: selectedInput) }
                        ), in: 0...1)
                        .frame(width: 160)
                        Text("\(Int(inputVolume * 100))%")
                            .font(Theme.Text.caption())
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colour.inkMuted48)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            RowDivider()
            Row(
                title: "Test microphone",
                detail: mic.isRunning
                    ? "Listening — speak, and what BlarneyKey hears appears below."
                    : "Records and transcribes on your Mac, so you can hear which mic reads you cleanest."
            ) {
                Button(mic.isRunning ? "Stop" : "Test microphone") {
                    mic.toggle(settings: store.settings)
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!modelReady)
            }

            if mic.isRunning {
                LevelMeter(level: mic.level)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xs)
            }

            RowDivider()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("LIVE TRANSCRIPTION").eyebrow()
                Text(transcriptText)
                    .font(mic.transcript.isEmpty
                          ? Theme.Text.body()
                          : .system(size: 13, design: .monospaced))
                    .foregroundStyle(mic.transcript.isEmpty
                                     ? Theme.Colour.inkMuted48
                                     : Theme.Colour.inkMuted80)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .padding(Theme.Space.sm)
                    .cardSurface(Theme.Colour.parchment, radius: Theme.Radius.md, bordered: true)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)

            if !modelReady {
                RowDivider()
                Note(kind: .warn,
                     text: "No speech model is loaded, so the test can't transcribe. Set one up under Model below.")
            }
            if let error = mic.error {
                RowDivider()
                Note(kind: .warn, text: error)
            }

            RowDivider()
            Note(kind: .plain,
                 text: "Changing the input device here sets your Mac's input device — the same one BlarneyKey dictates from. Recording and transcription stay on your Mac.")
        }
    }

    private var transcriptText: String {
        if !mic.transcript.isEmpty { return mic.transcript }
        return mic.isRunning ? "Listening…" : "Press Test microphone and say a few words."
    }

    private func refreshDevices() {
        inputDevices = AudioDevices.inputDevices()
        selectedInput = AudioDevices.defaultInputID ?? inputDevices.first?.id ?? 0
        loadVolume()
    }

    /// The device list or default input changed under us. Re-read both, and if a running
    /// test was listening to the device that just vanished, restart it on the new default
    /// so the live transcription keeps working rather than hanging on a dead mic.
    private func devicesChanged() {
        let previous = selectedInput
        refreshDevices()
        if mic.isRunning && selectedInput != previous {
            mic.restart(settings: store.settings)
        }
    }

    private func loadVolume() {
        volumeSettable = selectedInput != 0 && AudioDevices.inputVolumeSettable(of: selectedInput)
        inputVolume = Double(AudioDevices.inputVolume(of: selectedInput) ?? 0)
    }

    // MARK: - Model
    /// A WhisperKit model folder discovered on disk: the folder name, its full path, and
    /// the tensor prefix it was assembled with (read from the marker `setup.sh` leaves).
    private struct SpeechModel: Hashable, Identifiable {
        let name: String
        let path: String
        let prefix: String
        var id: String { path }
    }

    /// The folder the models live in — the parent of whichever one is selected.
    private var modelsDirectory: String {
        (store.settings.modelPath as NSString).deletingLastPathComponent
    }

    /// Every subfolder of the models directory that actually holds a compiled model, so the
    /// picker only ever offers something that will load.
    private func discoveredModels() -> [SpeechModel] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: modelsDirectory) else { return [] }
        return entries.sorted().compactMap { name in
            let path = (modelsDirectory as NSString).appendingPathComponent(name)
            let encoder = (path as NSString).appendingPathComponent("AudioEncoder.mlmodelc")
            guard fm.fileExists(atPath: encoder) else { return nil }
            let marker = (path as NSString).appendingPathComponent("model-prefix.txt")
            let prefix = (try? String(contentsOfFile: marker, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SpeechModel(
                name: name, path: path,
                prefix: (prefix?.isEmpty == false) ? prefix! : store.settings.modelPrefix
            )
        }
    }

    private var modelSection: some View {
        let models = discoveredModels()
        return Section_(label: "MODEL", index: 10) {
            Row(
                title: "Speech model",
                detail: "Transcription runs on WhisperKit. Pick which model it loads — larger is more accurate, smaller is faster."
            ) {
                if models.isEmpty {
                    Text("None found")
                        .font(Theme.Text.captionStrong())
                        .foregroundStyle(Theme.Colour.warn)
                } else {
                    Picker("", selection: Binding(
                        get: { store.settings.modelPath },
                        set: { newPath in
                            store.settings.modelPath = newPath
                            // Match the prefix to the chosen model, so a model assembled
                            // with a different prefix still loads.
                            if let model = models.first(where: { $0.path == newPath }) {
                                store.settings.modelPrefix = model.prefix
                            }
                            store.save()
                        }
                    )) {
                        ForEach(models) { Text($0.name).tag($0.path) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            RowDivider()
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
            RowDivider()
            Note(kind: .plain,
                 text: "Models live in \(modelsDirectory). To add one, run  ./setup.sh <model> <prefix> <folder>  in the BlarneyKey project folder — e.g.  ./setup.sh large-v3 openai large-v3  — and it appears in this list. Model names are on Hugging Face at argmaxinc/whisperkit-coreml.")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section_(label: "PRIVACY", index: 11) {
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

/// A live input-level bar for the mic test — the surface fills with the one accent colour,
/// no numbers, since it only has to show that sound is getting in.
private struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colour.dividerSoft)
                Capsule()
                    .fill(Theme.Colour.primary)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, level)))))
                    .animation(Theme.Motion.interaction, value: level)
            }
        }
        .frame(height: 6)
    }
}
