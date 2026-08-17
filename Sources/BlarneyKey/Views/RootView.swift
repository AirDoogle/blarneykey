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
    @ObservedObject private var permissions = Permissions.shared
    @State private var tab: Tab = .home

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 212, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if !permissions.hasAccessibility { permissionBanner }
                switch tab {
                case .home: HomeView(store: store, dictation: dictation)
                case .apps: AppsView(store: store)
                case .snippets: SnippetsView(store: store)
                case .settings: SettingsView(store: store)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        // The single accent, applied once at the root so every control inherits it.
        .tint(Theme.Colour.primary)
    }

    /// Nothing works without this grant, so it gets a dark tile across the top of every
    /// surface rather than a line buried in Settings.
    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colour.warn)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("BlarneyKey cannot type anywhere yet")
                    .font(Theme.Text.tagline())
                    .tracking(Theme.Text.Track.body)
                    .foregroundStyle(Theme.Colour.onDark)
                Text("Dictation will still record and transcribe, but without Accessibility permission it cannot put the text into another app. If BlarneyKey already appears ticked in the list, remove it with the minus button and add it again — rebuilding the app leaves a stale entry that looks granted but is not.")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.bodyMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.sm)

            VStack(spacing: Theme.Space.xs) {
                Button("Open settings") { permissions.request() }
                    .buttonStyle(PillButtonStyle(onDark: true))
                Button("Reveal app") { permissions.revealApp() }
                    .buttonStyle(UtilityButtonStyle(onDark: true))
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colour.tile1)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.Colour.primary)
                Text("BlarneyKey")
                    .font(Theme.Text.tagline())
                    .tracking(Theme.Text.Track.body)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, Theme.Space.sm)

            List(selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(Theme.Text.body())
                        .tag(item)
                }
            }
            .listStyle(.sidebar)

            statusBox
        }
    }

    /// Status, not chrome: a pearl plate with a hairline, no shadow.
    private var statusBox: some View {
        VStack(spacing: 5) {
            row("Hotkey", store.settings.binding.shortLabel)
            row("Insertion", store.settings.insertionMode == .paste ? "Paste" : "Type")
            row("Cleanup", cleanupState)
            row("Speech model", modelReady ? "Ready" : "Missing")
            row("Sessions today", "\(store.sessionsToday)")
        }
        .padding(Theme.Space.sm)
        .cardSurface(Theme.Colour.pearl, radius: Theme.Radius.md)
        .padding(Theme.Space.sm)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(label)
                .font(Theme.Text.caption())
                .foregroundStyle(Theme.Colour.inkMuted48)
            Spacer(minLength: Theme.Space.xxs)
            Text(value)
                .font(Theme.Text.captionStrong())
                .foregroundStyle(Theme.Colour.inkMuted80)
                .lineLimit(1)
        }
    }

    private var cleanupState: String {
        guard Cleanup.isAvailable else { return "Unavailable" }
        return store.settings.cleanupEverywhere ? "On" : "Per app"
    }

    private var modelReady: Bool {
        FileManager.default.fileExists(atPath: store.settings.modelPath)
    }
}
