import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @ObservedObject var store: Store
    @State private var bundleIDField = ""
    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                allowAllToggle
                if !store.settings.allowAllApps {
                    list
                    addByBundleID
                } else {
                    Text("Every app is allowed. Turn the switch off to restrict dictation to a chosen list.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .navigationTitle("Apps")
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: [.application],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard let bundle = Bundle(url: url),
                          let id = bundle.bundleIdentifier else { continue }
                    store.addApp(bundleID: id,
                                 name: FileManager.default.displayName(atPath: url.path)
                                     .replacingOccurrences(of: ".app", with: ""))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apps").font(.largeTitle.weight(.bold))
            Text("Choose where dictation is allowed to paste. Turn on Format for an app to tidy its dictation with the on-device cleanup model.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allowAllToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow every app").font(.callout.weight(.medium))
                Text("Sensible on your own machine. An allowlist is for when you want the discipline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.settings.allowAllApps },
                set: { store.settings.allowAllApps = $0; store.save() }
            ))
            .labelsHidden()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ALLOWED (\(store.allowedApps.count))")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingPicker = true
                } label: {
                    Label("Add app…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 0) {
                ForEach(store.allowedApps) { app in
                    AppRow(store: store, app: app)
                    if app.id != store.allowedApps.last?.id { Divider() }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var addByBundleID: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADD BY BUNDLE ID")
                .font(.caption.weight(.semibold)).tracking(1)
                .foregroundStyle(.secondary)
            Text("For anything that is not a normal app in /Applications.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("com.example.app", text: $bundleIDField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(bundleIDField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 4)
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
        HStack(spacing: 10) {
            if let icon = Store.icon(for: app.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout)
                Text(app.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if Cleanup.isAvailable {
                Text("Format").font(.caption).foregroundStyle(.secondary)
                Toggle("", isOn: Binding(
                    get: { app.formatEnabled },
                    set: { value in
                        if let index = store.allowedApps.firstIndex(where: { $0.id == app.id }) {
                            store.allowedApps[index].formatEnabled = value
                            store.save()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Button {
                store.removeApp(app)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
