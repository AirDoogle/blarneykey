import AppKit

/// Puts text into whatever has keyboard focus, in any app.
///
/// Two strategies, because no single one works everywhere:
///
/// - **paste** — clipboard plus a synthesised ⌘V. Fast, and correct for long text.
/// - **type** — synthesised Unicode keystrokes. Slower, but it works in apps that
///   refuse a synthetic paste, and it never touches your clipboard.
enum TextInserter {

    /// Synthetic events are *posted* at the HID level, as though they came from the
    /// keyboard. `.cgAnnotatedSessionEventTap` exists for event taps that **listen**;
    /// posting there is silently dropped by most apps, which looks exactly like dictation
    /// working and then nothing appearing.
    private static let tap: CGEventTapLocation = .cghidEventTap

    /// Microseconds between the events of a chord. Posting them in the same instant gets
    /// the chord coalesced away by some apps.
    private static let gap: UInt32 = 12_000

    /// `deletingFirst` backspaces are sent before the text, from the end of the line, to
    /// clear a terminal draft that the text replaces.
    static func insert(_ text: String, mode: InsertionMode = .paste, deletingFirst: Int = 0) {
        guard !text.isEmpty else { return }
        switch mode {
        case .paste: pasteViaClipboard(text, deletingFirst: deletingFirst)
        case .type:
            DispatchQueue.global(qos: .userInitiated).async {
                clear(deletingFirst)
                typeDirectly(text)
            }
        }
    }

    /// ⌃E to the end of the line, then backspaces. Readline and Claude Code both read ⌃E as
    /// "end of line", and a backspace at an empty prompt does nothing.
    private static func clear(_ count: Int) {
        guard count > 0, let source = CGEventSource(stateID: .combinedSessionState) else { return }
        waitForModifiersReleased(timeout: 2)
        press(14, flags: .maskControl, source: source) // E
        for _ in 0..<count { press(51, flags: [], source: source) } // Delete
        usleep(gap)
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags, source: CGEventSource) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: tap)
        up?.post(tap: tap)
        usleep(1_500)
    }

    // MARK: - Paste

    private static func pasteViaClipboard(_ text: String, deletingFirst: Int = 0) {
        let pb = NSPasteboard.general
        let saved = snapshot()

        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardWatcher.shared.noteOwnWrite()

        // Post off the main thread: the inter-event gaps would otherwise stall the UI, and
        // a busy main thread is a poor place to be feeding the event system from.
        DispatchQueue.global(qos: .userInitiated).async {
            clear(deletingFirst)
            pressCommand(key: 9) // V

            // Chromium and Electron apps service the paste asynchronously, so give them
            // real time before handing the clipboard back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                restore(saved)
            }
        }
    }

    /// Every representation of the clipboard, not just the string, so an image or rich
    /// text survives.
    static func snapshot() -> [NSPasteboard.PasteboardType: Data] {
        NSPasteboard.general.pasteboardItems?.first
            .map { item in
                item.types.reduce(into: [:]) { dict, type in
                    if let data = item.data(forType: type) { dict[type] = data }
                }
            } ?? [:]
    }

    static func restore(_ saved: [NSPasteboard.PasteboardType: Data]) {
        guard !saved.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        for (type, data) in saved { pb.setData(data, forType: type) }
        ClipboardWatcher.shared.noteOwnWrite()
    }

    /// Sends the whole chord as real key events: ⌘ down, key down, key up, ⌘ up.
    ///
    /// Setting `.maskCommand` on the V event alone is enough for native AppKit apps, but
    /// Chromium-based ones (Electron: Notion, Slack, VS Code, Discord) track modifier
    /// state from the modifier key events themselves. Without a genuine ⌘ keyDown they see
    /// a bare "v" and discard it.
    static func pressCommand(key: CGKeyCode) {
        // A key still held changes the chord: with Shift, Terminal reads ⌘V as Paste
        // Selection. Shift + Blarney key is the command trigger, so give you a moment to
        // let go.
        waitForModifiersReleased(timeout: 2)
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let commandKey: CGKeyCode = 55

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true)
        commandDown?.flags = .maskCommand

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        vDown?.flags = .maskCommand

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        vUp?.flags = .maskCommand

        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        commandUp?.flags = []

        commandDown?.post(tap: tap)
        usleep(gap)
        vDown?.post(tap: tap)
        usleep(gap)
        vUp?.post(tap: tap)
        usleep(gap)
        commandUp?.post(tap: tap)
    }

    /// Waits until no modifier key is down. Returns false if one still is at the timeout.
    @discardableResult
    static func waitForModifiersReleased(timeout: TimeInterval) -> Bool {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let deadline = Date().addingTimeInterval(timeout)
        while !CGEventSource.flagsState(.combinedSessionState).isDisjoint(with: held) {
            if Date() > deadline { return false }
            usleep(25_000)
        }
        return true
    }

    // MARK: - Type

    /// Types the text as Unicode input. Blocks, so callers run it off the main thread. `keyboardSetUnicodeString` is reliable in small
    /// pieces, so this walks the string in chunks rather than sending it in one event.
    private static func typeDirectly(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let units = Array(text.utf16)
        let chunkSize = 16

        for start in stride(from: 0, to: units.count, by: chunkSize) {
            let chunk = Array(units[start..<min(start + chunkSize, units.count)])
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)

            down.post(tap: tap)
            up.post(tap: tap)
            usleep(4_000)
        }
    }

    // MARK: - Diagnostics

    /// Inserts a known string after a delay, so insertion can be tested without speaking.
    /// The delay exists to give you time to click into a text field first.
    static func test(mode: InsertionMode, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            insert("BlarneyKey insertion test ✓", mode: mode)
        }
    }
}
