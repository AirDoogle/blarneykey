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
    var onCommandPress: () -> Void = {}
    var onCommandRelease: () -> Void = {}
    /// Shift went down while an ordinary Blarney key was held: make it a command.
    var onShiftWhileHeld: () -> Void = {}

    /// Two taps inside this window count as a double-tap.
    private let doubleTapWindow: TimeInterval = 0.4

    private var monitors: [Any] = []
    private var lastReleasedAt: Date?
    /// Which key is currently held. Tracking the specific key, rather than a bare flag,
    /// stops one Blarney key's release from ending a dictation another one started.
    private var heldKey: KeyBinding?
    /// The held key is running a command, via a command key or Shift + a Blarney key.
    private var heldAsCommand = false

    /// Every key that can start dictation. Different keyboards have different spare keys,
    /// so an external board and the built-in one can each have their own.
    var bindings: [KeyBinding] = [.default] {
        didSet { if bindings != oldValue { heldKey = nil } }
    }

    /// Keys that hold to speak a command about the selected text.
    var commandBindings: [KeyBinding] = [] {
        didSet { if commandBindings != oldValue { heldKey = nil } }
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
        (commandBindings + bindings).first { $0.keyCode == code && $0.isModifier == modifier }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Escape always cancels, whatever the keys are. EscapeTap normally catches it
            // first; this covers the case where the tap could not be created.
            if event.keyCode == 53, !event.isARepeat { onEscape() }
            // Holding an ordinary key fires keyDown over and over; only the first counts.
            if !event.isARepeat, let key = binding(forKeyCode: event.keyCode, modifier: false) {
                press(key, shift: event.modifierFlags.contains(.shift))
            }
        case .keyUp:
            if let key = binding(forKeyCode: event.keyCode, modifier: false) {
                release(key)
            }
        case .flagsChanged:
            // Left or right Shift, added after the Blarney key went down.
            if [56, 60].contains(event.keyCode), event.modifierFlags.contains(.shift),
               heldKey != nil, !heldAsCommand {
                heldAsCommand = true
                onShiftWhileHeld()
            }
            guard let key = binding(forKeyCode: event.keyCode, modifier: true) else { return }
            if (event.modifierFlags.rawValue & key.mask) != 0 {
                press(key, shift: event.modifierFlags.contains(.shift))
            } else {
                release(key)
            }
        default:
            return
        }
    }

    private func press(_ key: KeyBinding, shift: Bool = false) {
        // Ignore a second key pressed while the first is still held.
        guard heldKey == nil else { return }
        heldKey = key
        heldAsCommand = commandBindings.contains(key) || shift
        if heldAsCommand {
            onCommandPress()
            return
        }
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
        if heldAsCommand {
            heldAsCommand = false
            onCommandRelease()
            return
        }
        lastReleasedAt = Date()
        onRelease()
    }
}

/// Swallows the keys that steer a running dictation, so they do not also reach the app
/// underneath: Escape (in Claude Code a stray one interrupts whatever it is doing), and V
/// while a Blarney key is held, which pastes the last dictation instead.
final class EscapeTap {
    var onEscape: () -> Void = {}
    var onPasteLast: () -> Void = {}
    /// Asked on the main thread each time V goes down.
    var takesV: () -> Bool = { false }

    private var tap: CFMachPort?

    var isInstalled: Bool { tap != nil }

    func setActive(_ active: Bool) {
        if active, tap == nil { create() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: active) }
    }

    private func create() {
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let this = Unmanaged<EscapeTap>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = this.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            switch key {
            case 53:
                if !repeated { DispatchQueue.main.async { this.onEscape() } }
                return nil
            case 9 where this.takesV():
                if !repeated { DispatchQueue.main.async { this.onPasteLast() } }
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = created
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
    }
}
