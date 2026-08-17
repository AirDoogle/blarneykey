import AppKit

/// Puts text into whatever has keyboard focus, in any app.
///
/// Two strategies, because no single one works everywhere:
///
/// - **paste** — clipboard plus a synthesised ⌘V. Fast, and correct for long text.
/// - **type** — synthesised Unicode keystrokes. Slower, but it works in apps that
///   refuse a synthetic paste, and it never touches your clipboard.
enum TextInserter {
    static func insert(_ text: String, mode: InsertionMode = .paste) {
        guard !text.isEmpty else { return }
        switch mode {
        case .paste: pasteViaClipboard(text)
        case .type: typeDirectly(text)
        }
    }

    // MARK: - Paste

    private static func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general

        // Snapshot every representation, not just the string, so an image or rich text
        // on the clipboard survives.
        let saved: [NSPasteboard.PasteboardType: Data] = pb.pasteboardItems?.first
            .map { item in
                item.types.reduce(into: [:]) { dict, type in
                    if let data = item.data(forType: type) { dict[type] = data }
                }
            } ?? [:]

        pb.clearContents()
        pb.setString(text, forType: .string)

        pressCommandV()

        // Chromium and Electron apps service the paste asynchronously, so give them
        // real time before handing the clipboard back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard !saved.isEmpty else { return }
            pb.clearContents()
            for (type, data) in saved { pb.setData(data, forType: type) }
        }
    }

    /// Sends the whole chord as real key events: ⌘ down, V down, V up, ⌘ up.
    ///
    /// Setting `.maskCommand` on the V event alone is enough for native AppKit apps,
    /// but Chromium-based ones (Electron: Notion, Slack, VS Code, Discord) track
    /// modifier state from the modifier key events themselves. Without a genuine ⌘
    /// keyDown they see a bare "v" and discard it.
    private static func pressCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let commandKey: CGKeyCode = 55
        let vKey: CGKeyCode = 9
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true)
        commandDown?.flags = .maskCommand

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand

        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        commandUp?.flags = []

        // A few milliseconds between events; posting the chord all at once gets it
        // coalesced away by some apps.
        let gap: UInt32 = 8_000
        commandDown?.post(tap: tap)
        usleep(gap)
        vDown?.post(tap: tap)
        usleep(gap)
        vUp?.post(tap: tap)
        usleep(gap)
        commandUp?.post(tap: tap)
    }

    // MARK: - Type

    /// Types the text as Unicode input. `keyboardSetUnicodeString` is reliable in small
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

            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(3_000)
        }
    }
}
