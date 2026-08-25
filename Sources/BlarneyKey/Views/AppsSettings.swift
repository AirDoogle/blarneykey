import SwiftUI
import UniformTypeIdentifiers

/// The allowlist, as a group of sections inside Settings rather than its own tab: where
/// dictation may paste, and which apps get the cleanup pass. `index` starts the reveal
/// stagger where the surrounding Settings page left off.
struct AppsSettings: View {
    @ObservedObject var store: Store
    var index: Int
    @State private var bundleIDField = ""
    @State private var showingPicker = false

    var body: some View {
        Group {
            Section_(label: "APPS", index: index) {
                Row(
                    title: "Allow every app",
                    detail: "Sensible on your own machine. An allowlist is for when you want the discipline."
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.settings.allowAllApps },
                        set: { store.settings.allowAllApps = $0; store.save() }
                    ))
                    .labelsHidden()
                }
                RowDivider()
                Note(kind: .plain,
                     text: "Turn on Format for an app to tidy its dictation with the on-device cleanup model.")
            }

            if store.settings.allowAllApps {
                Section_(label: "ALLOWLIST", index: index + 1) {
                    Note(kind: .plain,
                         text: "Every app is allowed. Turn the switch off to restrict dictation to a chosen list.")
                }
            } else {
                allowlist
                addByBundleID
            }
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.application],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                store.addApp(
                    bundleID: id,
                    name: FileManager.default.displayName(atPath: url.path)
                        .replacingOccurrences(of: ".app", with: "")
                )
            }
        }
    }

    private var allowlist: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("ALLOWED (\(store.allowedApps.count))").eyebrow()
                Spacer()
                Button("Add app") { showingPicker = true }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }

            VStack(spacing: 0) {
                if store.allowedApps.isEmpty {
                    Note(kind: .warn,
                         text: "The list is empty, so dictation has nowhere to go. Add an app or turn Allow every app back on.")
                }
                ForEach(Array(store.allowedApps.enumerated()), id: \.element.id) { position, app in
                    if position > 0 { RowDivider() }
                    AppRow(store: store, app: app)
                }
            }
            .cardSurface()
        }
        .reveal(index + 1)
    }

    private var addByBundleID: some View {
        Section_(label: "ADD BY BUNDLE ID", index: index + 2) {
            Row(title: "Bundle identifier",
                detail: "For anything that is not a normal app in /Applications.") {
                HStack(spacing: Theme.Space.xs) {
                    TextField("com.example.app", text: $bundleIDField)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Text.body())
                        .frame(width: 210)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(PillButtonStyle())
                        .disabled(bundleIDField.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        store.addApp(bundleID: bundleIDField)
        bundleIDField = ""
    }
}

private struct AppRow: View {
    @ObservedObject var store: Store
    let app: AllowedApp

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            if let icon = Store.icon(for: app.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Theme.Text.bodyStrong())
                    .tracking(Theme.Text.Track.body)
                    .foregroundStyle(Theme.Colour.ink)
                Text(app.bundleID)
                    .font(Theme.Text.caption())
                    .monospaced()
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            Spacer(minLength: Theme.Space.sm)

            if Cleanup.isAvailable {
                Text("Format")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
                Toggle("", isOn: Binding(
                    get: { app.formatEnabled },
                    set: { value in
                        guard let index = store.allowedApps.firstIndex(where: { $0.id == app.id })
                        else { return }
                        store.allowedApps[index].formatEnabled = value
                        store.save()
                    }
                ))
                .labelsHidden()
                .controlSize(.small)
            }

            Button {
                store.removeApp(app)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(minHeight: 44)
    }
}
