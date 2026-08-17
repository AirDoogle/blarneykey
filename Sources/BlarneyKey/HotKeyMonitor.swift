import AppKit

/// Watches for the push-to-talk key and reports presses, releases, double-taps and Escape.
///
/// Modifier keys arrive as `.flagsChanged` events that say nothing about direction, so
/// direction comes from the device-dependent bit in the raw flags. Global monitors need
/// Accessibility permission; the local monitor covers the case where our own window has
/// focus, which the global one never sees.
final class HotKeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onDoubleTap: () -> Void = {}
    var onEscape: () -> Void = {}

    /// Two taps inside this window count as a double-tap.
    private let doubleTapWindow: TimeInterval = 0.4

    private var monitors: [Any] = []
    private var lastReleasedAt: Date?
    private var isDown = false

    var binding: KeyBinding = .default {
        didSet { if binding != oldValue { isDown = false } }
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
        isDown = false
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Escape always cancels, whatever the hotkey is.
            if event.keyCode == 53, !event.isARepeat { onEscape() }
            // Holding an ordinary key fires keyDown over and over; only the first counts.
            if !binding.isModifier, event.keyCode == binding.keyCode, !event.isARepeat {
                press()
            }
        case .keyUp:
            if !binding.isModifier, event.keyCode == binding.keyCode {
                release()
            }
        case .flagsChanged:
            guard binding.isModifier, event.keyCode == binding.keyCode else { return }
            if (event.modifierFlags.rawValue & binding.mask) != 0 { press() } else { release() }
        default:
            return
        }
    }

    private func press() {
        guard !isDown else { return }
        isDown = true
        if let last = lastReleasedAt, Date().timeIntervalSince(last) < doubleTapWindow {
            lastReleasedAt = nil
            onDoubleTap()
        } else {
            onPress()
        }
    }

    private func release() {
        guard isDown else { return }
        isDown = false
        lastReleasedAt = Date()
        onRelease()
    }
}
