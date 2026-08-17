import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store.shared
    private let dictation = DictationController()
    private let hotKey = HotKeyMonitor()
    private let pill = PillWindow()

    private let permissions = Permissions.shared
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("waveform")
        buildMenu()

        dictation.requestMicrophoneAccess()
        wireHotKey()
        observeState()

        // A revoked grant looks identical to a first run, and both leave the app unable
        // to type, so both open the window where the banner explains it.
        permissions.$hasAccessibility
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in
                self?.buildMenu()
                if !granted { self?.setIcon("exclamationmark.triangle.fill", tint: .systemOrange) }
            }
            .store(in: &cancellables)

        if !permissions.hasAccessibility {
            permissions.request()
            openWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.stop()
        store.writeNow()
    }

    // MARK: - Hotkey wiring

    private func wireHotKey() {
        hotKey.binding = store.settings.binding
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            // In locked mode a tap is the stop signal.
            if self.dictation.isLocked { self.dictation.stop() }
            else { self.dictation.begin(locked: false) }
        }
        hotKey.onRelease = { [weak self] in self?.dictation.endIfHolding() }
        hotKey.onDoubleTap = { [weak self] in
            guard let self else { return }
            if self.dictation.isRecording { self.dictation.stop() }
            else if self.store.settings.doubleTapToLock { self.dictation.begin(locked: true) }
            else { self.dictation.begin(locked: false) }
        }
        hotKey.onEscape = { [weak self] in
            guard let self, self.dictation.isLocked else { return }
            self.dictation.stop()
        }
        hotKey.start()

        // Keep the monitor in step when the hotkey is changed in Settings.
        store.$settings
            .map(\.binding)
            .removeDuplicates()
            .sink { [weak self] key in
                self?.hotKey.binding = key
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    // MARK: - State to menu bar and pill

    private func observeState() {
        dictation.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.setIcon("waveform")
                    self.pill.hide()
                case .recording:
                    self.setIcon("mic.fill", tint: .systemRed)
                    if self.store.settings.showPill { self.pill.show(controller: self.dictation) }
                case .transcribing:
                    self.setIcon("ellipsis.circle", tint: .systemBlue)
                    self.pill.hide()
                case .failed:
                    self.setIcon("exclamationmark.triangle.fill", tint: .systemOrange)
                    self.pill.hide()
                }
                self.buildMenu()
            }
            .store(in: &cancellables)
    }

    private func setIcon(_ symbol: String, tint: NSColor? = nil) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "BlarneyKey")
        image?.isTemplate = tint == nil
        button.image = image
        button.contentTintColor = tint
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        switch dictation.state {
        case .failed(let message):
            menu.addItem(disabled(message))
        case .recording(let locked):
            menu.addItem(disabled(locked ? "Recording — locked on" : "Recording…"))
        case .transcribing:
            menu.addItem(disabled("Transcribing…"))
        case .idle:
            menu.addItem(disabled("Hold \(store.settings.binding.shortLabel) to dictate"))
        }

        if !permissions.hasAccessibility {
            menu.addItem(disabled("Cannot type — no Accessibility permission"))
            menu.addItem(item("Fix Accessibility permission…", #selector(promptForAccessibility)))
        }

        menu.addItem(.separator())
        let toggle = item(dictation.isRecording ? "Stop dictation" : "Start dictation",
                          #selector(toggleDictation))
        toggle.keyEquivalent = "d"
        menu.addItem(toggle)

        // Always reachable with the mouse, so a badly chosen key is one click from fixed.
        if store.settings.binding.preset == nil {
            menu.addItem(item("Reset hotkey to \(KeyBinding.default.shortLabel)",
                              #selector(resetHotKey)))
        }

        menu.addItem(.separator())
        let open = item("Open BlarneyKey", #selector(openWindow))
        open.keyEquivalent = "o"
        menu.addItem(open)

        menu.addItem(.separator())
        let quit = item("Quit BlarneyKey", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        dictation.toggleLocked()
    }

    @objc private func resetHotKey() {
        store.settings.binding = .default
        store.writeNow()
        buildMenu()
    }

    @objc private func openWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingView(rootView: RootView(store: store, dictation: dictation))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "BlarneyKey"
        window.titlebarAppearsTransparent = true
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    @objc private func promptForAccessibility() {
        permissions.request()
        openWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
