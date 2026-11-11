import AppKit
import Carbon.HIToolbox

/// The system-wide ⌃⌥V shortcut for pasting the last dictation. A registered hot key
/// rather than an event monitor, so the keystroke is consumed and the app underneath
/// never sees it.
final class GlobalShortcut {
    var onFire: () -> Void = {}

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var isRegistered: Bool { hotKey != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled, hotKey == nil { register() }
        if !enabled, let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func register() {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return noErr }
                let this = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { this.onFire() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x424B_504C), id: 1) // "BKPL"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), id,
                                         GetEventDispatcherTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil
            NSLog("BlarneyKey: could not register ⌃⌥V (status \(status)); another app may own it")
        }
    }
}
