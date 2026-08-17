import SwiftUI

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, apps, snippets, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .apps: return "Apps"
            case .snippets: return "Snippets"
            case .settings: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "house"
            case .apps: return "square.grid.2x2"
            case .snippets: return "text.badge.plus"
            case .settings: return "gearshape"
            }
        }
    }

    @ObservedObject var store: Store
    @ObservedObject var dictation: DictationController
    @State private var tab: Tab = .home

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text("BlarneyKey").font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)

                List(selection: $tab) {
                    ForEach(Tab.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .listStyle(.sidebar)

                statusBox
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch tab {
            case .home: HomeView(store: store, dictation: dictation)
            case .apps: AppsView(store: store)
            case .snippets: SnippetsView(store: store)
            case .settings: SettingsView(store: store)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    private var statusBox: some View {
        VStack(spacing: 4) {
            row("Hotkey", store.settings.binding.shortLabel)
            row("Cleanup", Cleanup.isAvailable
                ? (store.settings.cleanupEverywhere ? "On" : "Per app")
                : "Unavailable")
            row("Speech model", modelReady ? "Ready" : "Missing")
            row("Sessions today", "\(store.sessionsToday)")
        }
        .font(.caption)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }

    private var modelReady: Bool {
        FileManager.default.fileExists(atPath: store.settings.modelPath)
    }
}
