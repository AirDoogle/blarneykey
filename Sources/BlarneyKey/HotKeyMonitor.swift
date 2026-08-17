import AppKit

/// Watches for any of the push-to-talk keys and reports presses, releases, double-taps
/// and Escape.
///
/// Modifier keys arrive as `.flagsChanged` events that say nothing about direction, so
/// direction comes from the device-dependent bit in the raw flags. Ordinary keys arrive
/// as `.keyDown` / `.keyUp`. Global monitors need Accessibility permission; the local
/// monitor covers the case where our own window has focus, which the global one never
/// sees.
final class HotKeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onDoubleTap: () -> Void = {}
    var onEscape: () -> Void = {}

    /// Two taps inside this window count as a double-tap.
    private let doubleTapWindow: TimeInterval = 0.4

    private var monitors: [Any] = []
    private var lastReleasedAt: Date?
    /// Which key is currently held. Tracking the specific key, rather than a bare flag,
    /// stops one Blarney key's release from ending a dictation another one started.
    private var heldKey: KeyBinding?

    /// Every key that can start dictation. Different keyboards have different spare keys,
    /// so an external board and the built-in one can each have their own.
    var bindings: [KeyBinding] = [.default] {
        didSet { if bindings != oldValue { heldKey = nil } }
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in
            self?.handle($0)
        }) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        if let local { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        heldKey = nil
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    private func binding(forKeyCode code: UInt16, modifier: Bool) -> KeyBinding? {
        bindings.first { $0.keyCode == code && $0.isModifier == modifier }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Escape always cancels, whatever the keys are.
            if event.keyCode == 53, !event.isARepeat { onEscape() }
            // Holding an ordinary key fires keyDown over and over; only the first counts.
            if !event.isARepeat, let key = binding(forKeyCode: event.keyCode, modifier: false) {
                press(key)
            }
        case .keyUp:
            if let key = binding(forKeyCode: event.keyCode, modifier: false) {
                release(key)
            }
        case .flagsChanged:
            guard let key = binding(forKeyCode: event.keyCode, modifier: true) else { return }
            if (event.modifierFlags.rawValue & key.mask) != 0 { press(key) } else { release(key) }
        default:
            return
        }
    }

    private func press(_ key: KeyBinding) {
        // Ignore a second key pressed while the first is still held.
        guard heldKey == nil else { return }
        heldKey = key
        if let last = lastReleasedAt, Date().timeIntervalSince(last) < doubleTapWindow {
            lastReleasedAt = nil
            onDoubleTap()
        } else {
            onPress()
        }
    }

    private func release(_ key: KeyBinding) {
        // Only the key that started this dictation can end it.
        guard heldKey == key else { return }
        heldKey = nil
        lastReleasedAt = Date()
        onRelease()
    }
}
