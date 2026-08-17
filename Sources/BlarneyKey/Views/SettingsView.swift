import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var capturingKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.largeTitle.weight(.bold))
                    Text("Audio never leaves your Mac. Transcription runs on the Neural Engine.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                section("HOTKEY") {
                    settingRow(
                        "Dictation hotkey",
                        detail: store.settings.doubleTapToLock
                            ? "Hold to talk, or double-tap to lock dictation on. Tap again, press ESC, or click the pill to stop."
                            : "Hold to talk."
                    ) {
                        Picker("", selection: Binding(
                            get: { store.settings.binding },
                            set: { store.settings.binding = $0; store.save() }
                        )) {
                            if store.settings.binding.preset == nil {
                                Section("Recorded") {
                                    Text(store.settings.binding.label)
                                        .tag(store.settings.binding)
                                }
                            }
                            Section("Right-hand modifiers") {
                                ForEach(HotKey.rightHand) { Text($0.label).tag($0.binding) }
                            }
                            Section("Left-hand modifiers") {
                                ForEach(HotKey.leftHand) { Text($0.label).tag($0.binding) }
                            }
                            Section {
                                ForEach(HotKey.special) { Text($0.label).tag($0.binding) }
                            }
                            Section("Function keys") {
                                ForEach(HotKey.functionKeys) { Text($0.label).tag($0.binding) }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    if let caveat = store.settings.binding.caveat {
                        Text(caveat)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }

                    Divider()
                    settingRow(
                        "Use any key",
                        detail: "Press a spare key on your keyboard and use that instead. Keys needed for typing are refused."
                    ) {
                        HStack(spacing: 8) {
                            if store.settings.binding.preset == nil {
                                Button("Reset") {
                                    store.settings.binding = .default
                                    store.save()
                                }
                            }
                            Button("Record a key…") { capturingKey = true }
                        }
                    }

                    Divider()
                    toggleRow("Double-tap to lock on",
                              detail: "Keeps recording after you let go, for longer dictation.",
                              value: Binding(
                                get: { store.settings.doubleTapToLock },
                                set: { store.settings.doubleTapToLock = $0; store.save() }
                              ))
                    Divider()
                    toggleRow("Show the floating pill",
                              detail: "A small indicator with the live level and a stop button.",
                              value: Binding(
                                get: { store.settings.showPill },
                                set: { store.settings.showPill = $0; store.save() }
                              ))
                    Divider()
                    toggleRow("Play start and stop sounds", detail: nil, value: Binding(
                        get: { store.settings.playSounds },
                        set: { store.settings.playSounds = $0; store.save() }
                    ))
                }

                section("INSERTION") {
                    settingRow(
                        "How text is inserted",
                        detail: store.settings.insertionMode.detail
                    ) {
                        Picker("", selection: Binding(
                            get: { store.settings.insertionMode },
                            set: { store.settings.insertionMode = $0; store.save() }
                        )) {
                            ForEach(InsertionMode.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    Divider()
                    Text("If dictation records but nothing appears in an app, switch to Type it out. A few apps refuse a synthetic paste.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(12)
                }

                section("CLEANUP") {
                    settingRow(
                        "On-device cleanup",
                        detail: Cleanup.unavailableReason
                            ?? "Polish transcripts with Apple Foundation Models. Runs locally; nothing leaves the device."
                    ) {
                        if Cleanup.isAvailable {
                            Toggle("", isOn: Binding(
                                get: { store.settings.cleanupEverywhere },
                                set: { store.settings.cleanupEverywhere = $0; store.save() }
                            ))
                            .labelsHidden()
                        } else {
                            Text("Unavailable")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    if Cleanup.isAvailable {
                        Divider()
                        Text("With this off, cleanup still runs for individual apps you switch Format on for in the Apps tab.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(12)
                    }
                }

                section("SPEECH") {
                    settingRow("Language", detail: "Leave empty to let the model detect it.") {
                        TextField("en", text: Binding(
                            get: { store.settings.language ?? "" },
                            set: { store.settings.language = $0.isEmpty ? nil : $0; store.save() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }
                    Divider()
                    settingRow("Minimum hold", detail: "Shorter taps are ignored, so a stray keypress does nothing.") {
                        Stepper(
                            value: Binding(
                                get: { store.settings.minimumDuration },
                                set: { store.settings.minimumDuration = $0; store.save() }
                            ),
                            in: 0.1...2.0, step: 0.05
                        ) {
                            Text(String(format: "%.2f s", store.settings.minimumDuration))
                                .font(.callout.monospacedDigit())
                        }
                        .frame(width: 120)
                    }
                    Divider()
                    settingRow("Typing speed baseline", detail: "Used for the time-saved figure.") {
                        Stepper(
                            value: Binding(
                                get: { store.settings.typingWPM },
                                set: { store.settings.typingWPM = $0; store.save() }
                            ),
                            in: 20...120, step: 5
                        ) {
                            Text("\(Int(store.settings.typingWPM)) wpm")
                                .font(.callout.monospacedDigit())
                        }
                        .frame(width: 120)
                    }
                }

                section("MODEL") {
                    settingRow("Model folder", detail: store.settings.modelPath) {
                        HStack(spacing: 8) {
                            Text(modelReady ? "Ready" : "Missing")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(modelReady ? Color.green.opacity(0.18)
                                                       : Color.orange.opacity(0.2),
                                            in: Capsule())
                            Button("Reveal") {
                                NSWorkspace.shared.selectFile(
                                    store.settings.modelPath,
                                    inFileViewerRootedAtPath: ""
                                )
                            }
                        }
                    }
                }

                section("PRIVACY") {
                    settingRow(
                        "Network calls",
                        detail: "BlarneyKey makes none. Transcription is a local process; nothing is uploaded."
                    ) {
                        Text("none").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    settingRow("History", detail: "\(store.sessions.count) sessions stored on this Mac.") {
                        Button("Clear") { store.clearHistory() }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $capturingKey) {
            KeyCaptureSheet(current: store.settings.binding) { binding in
                store.settings.binding = binding
                store.save()
                capturingKey = false
            } onCancel: {
                capturingKey = false
            }
        }
    }

    private var modelReady: Bool {
        FileManager.default.fileExists(atPath: store.settings.modelPath)
    }

    // MARK: - Layout helpers

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold)).tracking(1)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func settingRow<Control: View>(
        _ title: String, detail: String?, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
        }
        .padding(12)
    }

    private func toggleRow(_ title: String, detail: String?, value: Binding<Bool>) -> some View {
        settingRow(title, detail: detail) {
            Toggle("", isOn: value).labelsHidden()
        }
    }
}
