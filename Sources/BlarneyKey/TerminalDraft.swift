import AppKit

/// What was highlighted in the focused app, read the moment the keys go down. Terminals
/// can drop a highlight while a dictation is being transcribed, so waiting until the end
/// loses it.
struct CapturedSelection {
    var text: String
    /// The whole visible text and the highlight's place in it, when the app reports them.
    /// Terminal does, which is how a Claude Code draft is told apart from its output.
    var buffer: String?
    var range: NSRange?

    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"
    ]

    static func read(from app: NSRunningApplication?) -> CapturedSelection? {
        guard let app else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        let selection = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success
            ? (selected as? String) ?? "" : ""

        var buffer: String?
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
            buffer = value as? String
        }

        if !selection.isEmpty {
            var capture = CapturedSelection(text: selection, buffer: buffer)
            var rangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                    capture.range = NSRange(location: range.location, length: range.length)
                }
            }
            return capture
        }

        // Claude Code's full-screen mode draws its own highlight, which the terminal never
        // sees, and copies it to the clipboard when you let go of the mouse. So in a
        // terminal, something copied moments ago stands in for the highlight.
        guard let id = app.bundleIdentifier, terminals.contains(id),
              let copied = ClipboardWatcher.shared.recentCopy(within: 30) else { return nil }
        return CapturedSelection(text: copied, buffer: buffer)
    }
}

/// Notices when something other than BlarneyKey puts text on the clipboard, and when.
final class ClipboardWatcher {
    static let shared = ClipboardWatcher()

    private var lastCount = NSPasteboard.general.changeCount
    private var ownCounts = Set<Int>()
    private var lastExternal: Date?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Call right after BlarneyKey writes the clipboard, so that write is not mistaken
    /// for one of yours.
    func noteOwnWrite() {
        ownCounts.insert(NSPasteboard.general.changeCount)
        if ownCounts.count > 50 { ownCounts.removeFirst() }
    }

    private func poll() {
        let count = NSPasteboard.general.changeCount
        guard count != lastCount else { return }
        lastCount = count
        if !ownCounts.contains(count) { lastExternal = Date() }
    }

    func recentCopy(within seconds: TimeInterval) -> String? {
        poll()
        guard let lastExternal, Date().timeIntervalSince(lastExternal) <= seconds,
              let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return nil }
        return text
    }
}

/// The unsent draft in Claude Code's input box, as drawn in a terminal:
///
///     ────────────────
///     ❯ first line of the draft
///       and its continuation
///     ────────────────
enum TerminalDraft {
    struct Draft: Equatable {
        var text: String
        /// Backspaces that are certain to clear it. Extra ones at an empty prompt do nothing,
        /// so this errs high: a soft-wrapped line can hide a space the screen doesn't show.
        var clearCount: Int
    }

    /// The draft, when the highlight touches the input box; nil when it is elsewhere.
    static func draft(in buffer: String, selection: NSRange) -> Draft? {
        guard let (box, draft) = inputBox(in: buffer) else { return nil }
        let touches = NSIntersectionRange(box, selection).length > 0
            || (selection.length == 0 && NSLocationInRange(selection.location, box))
        return touches ? draft : nil
    }

    /// The draft, when the copied text is part of it. Compared without spacing, since the
    /// screen wraps lines where the draft has none.
    static func draft(in buffer: String, containing copied: String) -> Draft? {
        guard let (_, draft) = inputBox(in: buffer) else { return nil }
        let needle = squeezed(copied.drop(while: { $0 == "❯" || $0 == ">" }).description)
        guard !needle.isEmpty, squeezed(draft.text).contains(needle) else { return nil }
        return draft
    }

    private static func squeezed(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func inputBox(in buffer: String) -> (NSRange, Draft)? {
        let text = buffer as NSString
        var lines: [(range: NSRange, content: String)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append((range, text.substring(with: range)))
        }

        guard let prompt = lines.indices.last(where: { index in
            index > 0 && isPrompt(lines[index].content) && isRule(lines[index - 1].content)
        }) else { return nil }
        let end = lines[(prompt + 1)...].firstIndex { isRule($0.content) } ?? lines.endIndex
        guard end > prompt else { return nil }

        let box = NSUnionRange(lines[prompt].range, lines[end - 1].range)

        var drafted: [String] = []
        for (offset, line) in lines[prompt..<end].enumerated() {
            var content = line.content
            if offset == 0 { content = String(content.drop(while: { isPromptGlyph($0) })) }
            drafted.append(content.trimmingCharacters(in: .whitespaces))
        }
        while drafted.last?.isEmpty == true { drafted.removeLast() }
        let draft = drafted.joined(separator: "\n")
        guard !draft.isEmpty else { return nil }
        return (box, Draft(text: draft, clearCount: draft.count + drafted.count + 10))
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "─" }
    }

    private static func isPrompt(_ line: String) -> Bool {
        line.first == "❯" || line.first == ">"
    }

    private static func isPromptGlyph(_ character: Character) -> Bool {
        character == "❯" || character == ">" || character.isWhitespace
    }
}
