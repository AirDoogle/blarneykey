import Foundation

// MARK: - Dictation history

struct Session: Codable, Identifiable {
    var id = UUID()
    var date: Date
    /// The final text that was delivered (or copied). Kept as `text` because every
    /// stat, filter and row summary reads it.
    var text: String
    var appName: String
    var bundleID: String
    /// Seconds of audio recorded.
    var duration: TimeInterval
    /// Nil when the text was inserted successfully.
    var failure: String?

    // MARK: - Recording detail (all optional, added after the first releases, so an
    // older state.json still decodes — these simply read as nil for past sessions).

    /// The transcript straight out of the speech model, before any snippet or cleanup.
    var rawText: String?
    /// The transcript after the cleanup model, when it ran. Nil when cleanup was skipped.
    var cleanedText: String?
    /// Which speech model produced `rawText`, e.g. "WhisperKit · distil". Nil for older sessions.
    var transcribeModel: String?
    /// Which model produced `cleanedText`, e.g. "Apple Intelligence". Nil when cleanup was skipped.
    var cleanModel: String?
    /// How the text reached the app: "paste", "type", or "clipboard" (the fallback).
    var destination: String?
    /// Seconds spent turning audio into text.
    var transcribeSeconds: TimeInterval?
    /// Seconds spent in the cleanup model. Zero when it ran and did nothing; nil when skipped.
    var cleanSeconds: TimeInterval?
    /// Seconds spent inserting the text into the focused app.
    var pasteSeconds: TimeInterval?

    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    var characterCount: Int { text.count }

    /// Rough English heuristic (~4 characters per token). No tokenizer dependency,
    /// so this is an estimate, not an exact count from any specific model.
    var tokenCount: Int { max(wordCount > 0 ? 1 : 0, characterCount / 4) }

    var succeeded: Bool { failure == nil }
}

/// Whether word-based stats are shown as words or an estimated token count.
enum WordUnit: String, Codable, CaseIterable, Identifiable {
    case words, tokens
    var id: String { rawValue }
    var label: String { self == .words ? "Words" : "Tokens" }
}

// MARK: - Allowlist

struct AllowedApp: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    /// Run the transcript through the on-device cleanup model for this app.
    var formatEnabled: Bool = false

    var id: String { bundleID }
}

// MARK: - Snippets

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

// MARK: - Hotkey

enum HotKey: String, Codable, CaseIterable, Identifiable {
    // Right-hand modifiers: the best push-to-talk keys, since almost nothing
    // uses them on their own.
    case rightCommand, rightOption, rightControl, rightShift
    // Left-hand modifiers: available, but they carry most keyboard shortcuts.
    case leftCommand, leftOption, leftControl, leftShift
    case fn
    // Function keys, for anyone with a full-size or external keyboard.
    case f13, f14, f15, f16, f17, f18, f19

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        case .leftCommand: return 55
        case .leftOption: return 58
        case .leftControl: return 59
        case .leftShift: return 56
        case .fn: return 63
        case .f13: return 105
        case .f14: return 107
        case .f15: return 113
        case .f16: return 106
        case .f17: return 64
        case .f18: return 79
        case .f19: return 80
        }
    }

    /// Modifiers arrive as `.flagsChanged`, which says nothing about direction.
    /// Ordinary keys arrive as `.keyDown` / `.keyUp` and need no mask.
    var isModifier: Bool {
        switch self {
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19: return false
        default: return true
        }
    }

    /// The device-dependent modifier bit, which is what separates a press from a
    /// release and the right-hand key from its left-hand twin.
    var mask: UInt {
        switch self {
        case .leftControl: return 0x0000_0001
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .fn: return 0x0080_0000
        default: return 0
        }
    }

    var label: String {
        switch self {
        case .rightCommand: return "Right ⌘ Command"
        case .rightOption: return "Right ⌥ Option"
        case .rightControl: return "Right ⌃ Control"
        case .rightShift: return "Right ⇧ Shift"
        case .leftCommand: return "Left ⌘ Command"
        case .leftOption: return "Left ⌥ Option"
        case .leftControl: return "Left ⌃ Control"
        case .leftShift: return "Left ⇧ Shift"
        case .fn: return "fn (Globe)"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        }
    }

    var shortLabel: String {
        switch self {
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        case .rightControl: return "Right ⌃"
        case .rightShift: return "Right ⇧"
        case .leftCommand: return "Left ⌘"
        case .leftOption: return "Left ⌥"
        case .leftControl: return "Left ⌃"
        case .leftShift: return "Left ⇧"
        case .fn: return "fn"
        default: return label
        }
    }

    /// Worth warning about in the UI, because these keys have day jobs.
    var caveat: String? {
        switch self {
        case .rightCommand, .leftCommand:
            return "May briefly mis-trigger when you ⌘-Tab or use other ⌘ shortcuts."
        case .rightOption, .leftOption:
            return "⌥ is the dead key for accented characters."
        case .leftControl, .leftShift:
            return "Left-hand modifiers carry most keyboard shortcuts. A right-hand key is steadier."
        case .fn:
            return "macOS may claim fn for its own dictation and the emoji picker."
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19:
            return "Needs a keyboard with this key. The keypress also reaches the focused app."
        case .rightControl, .rightShift:
            return nil
        }
    }

    // Groups for the Settings picker.
    static let rightHand: [HotKey] = [.rightCommand, .rightOption, .rightControl, .rightShift]
    static let leftHand: [HotKey] = [.leftCommand, .leftOption, .leftControl, .leftShift]
    static let special: [HotKey] = [.fn]
    static let functionKeys: [HotKey] = [.f13, .f14, .f15, .f16, .f17, .f18, .f19]

    var binding: KeyBinding {
        KeyBinding(keyCode: keyCode, mask: mask, isModifier: isModifier, preset: rawValue)
    }
}

// MARK: - Key binding

/// Whichever key drives dictation — one of the presets, or any key you captured.
struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// Device-dependent modifier bit. Zero for ordinary keys.
    var mask: UInt = 0
    var isModifier = false
    /// Set when this came from the preset list, so the UI can show the nicer name.
    var preset: String?

    static let `default` = HotKey.rightOption.binding

    private var presetKey: HotKey? { preset.flatMap(HotKey.init(rawValue:)) }

    var label: String { presetKey?.label ?? KeyNames.label(for: keyCode) }
    var shortLabel: String { presetKey?.shortLabel ?? KeyNames.label(for: keyCode) }

    var caveat: String? {
        if let presetKey { return presetKey.caveat }
        switch KeyNames.risk(for: keyCode) {
        case .blocked:
            return "This key is needed for normal typing."
        case .risky:
            return "This key has another job. The keypress also reaches the focused app."
        case .safe:
            return isModifier ? nil : "The keypress also reaches the focused app."
        }
    }
}

// MARK: - Key names and risk

enum KeyNames {
    enum Risk { case safe, risky, blocked }

    /// Keys that make typing impossible if you bind dictation to them.
    private static let blocked: Set<UInt16> = {
        var set: Set<UInt16> = [
            36, 76,   // Return, keypad Enter
            48, 49,   // Tab, Space
            51, 117,  // Delete, forward delete
            53,       // Escape — reserved for cancelling dictation
            57        // Caps Lock — a toggle, so press and release do not pair up
        ]
        // Letters, digits and punctuation.
        set.formUnion(0...11)
        set.formUnion(12...29)
        set.formUnion([30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50])
        return set
    }()

    /// Usable, but they already do something you may miss.
    private static let risky: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // F1–F12
        123, 124, 125, 126,                                       // arrows
        115, 116, 119, 121, 114,                                  // Home/PgUp/End/PgDn/Help
        65, 67, 69, 71, 75, 78, 81,                               // keypad operators
        82, 83, 84, 85, 86, 87, 88, 89, 91, 92                    // keypad digits
    ]

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Escape", 54: "Right ⌘", 55: "Left ⌘", 56: "Left ⇧", 57: "Caps Lock",
        58: "Left ⌥", 59: "Left ⌃", 60: "Right ⇧", 61: "Right ⌥", 62: "Right ⌃", 63: "fn",
        64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear",
        75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 79: "F18", 80: "F19",
        81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8",
        92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func label(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    /// An unmapped key code is almost certainly one of the extra keys on a big
    /// external keyboard, which is exactly what you want for push-to-talk.
    static func risk(for keyCode: UInt16) -> Risk {
        if blocked.contains(keyCode) { return .blocked }
        if risky.contains(keyCode) { return .risky }
        return .safe
    }
}

// MARK: - Settings

/// How the transcript gets into the focused app.
enum InsertionMode: String, Codable, CaseIterable, Identifiable {
    /// Clipboard plus a synthesised ⌘V. Fast, and right for long text.
    case paste
    /// Synthesised Unicode keystrokes. Slower, leaves the clipboard alone, and works
    /// in apps that refuse a synthetic paste.
    case type

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paste: return "Paste (⌘V)"
        case .type: return "Type it out"
        }
    }

    var detail: String {
        switch self {
        case .paste:
            return "Fastest, and best for long dictation. Your clipboard is put back afterwards."
        case .type:
            return "Slower, but works in apps that ignore a synthetic paste, and never touches your clipboard."
        }
    }
}

/// Follow the system, or pin the app to one appearance.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct Settings: Codable {
    /// Every key that starts dictation. Any of them works; the first is the one shown
    /// in the interface when a single name is needed.
    var bindings: [KeyBinding] = [.default]
    var appearance: AppearanceMode = .system
    /// Start BlarneyKey when you log in, so it is there after a restart.
    var launchAtLogin = false
    var insertionMode: InsertionMode = .paste
    var language: String? = "en"
    var playSounds = true
    var showPill = true

    /// Double-tap the hotkey to keep dictating without holding it.
    var doubleTapToLock = true

    /// Taps shorter than this are treated as a stray keypress, not dictation.
    var minimumDuration: TimeInterval = 0.25

    /// Skip the allowlist entirely. Sensible on a personal machine.
    var allowAllApps = true

    /// Run every transcript through the cleanup model, not just per-app.
    var cleanupEverywhere = false

    /// Baseline for the "time saved" figure. 40 wpm is an average typing speed.
    var typingWPM: Double = 40

    /// Whether the dashboard shows word counts or an estimated token count.
    var wordUnit: WordUnit = .words

    var modelPath = "\(NSHomeDirectory())/Developer/blarneykey/models/combined"
    var modelPrefix = "distil"
    var cliPath = "/opt/homebrew/bin/whisperkit-cli"

    init() {}

    var primaryBinding: KeyBinding { bindings.first ?? .default }

    /// A human label for the speech model, e.g. "WhisperKit · distil-large-v3". WhisperKit
    /// is the engine; the model folder names the weights it loads, falling back to the
    /// prefix when the folder is the generic "combined".
    var speechModelName: String {
        let folder = (modelPath as NSString).lastPathComponent
        let generic: Set<String> = ["", "combined", "model", "models"]
        let name = generic.contains(folder.lowercased()) ? modelPrefix : folder
        return "WhisperKit · \(name.isEmpty ? "distil" : name)"
    }

    /// "Right ⌥", or "Right ⌥ or F13" when more than one key is set up.
    var bindingLabel: String {
        let names = bindings.map(\.shortLabel)
        switch names.count {
        case 0: return KeyBinding.default.shortLabel
        case 1: return names[0]
        case 2: return "\(names[0]) or \(names[1])"
        default: return "\(names[0]) or \(names.count - 1) others"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case bindings, binding, hotKey, insertionMode, appearance, launchAtLogin
        case language, playSounds, showPill
        case doubleTapToLock
        case minimumDuration, allowAllApps, cleanupEverywhere, typingWPM, wordUnit
        case modelPath, modelPrefix, cliPath
    }

    /// Every field is optional on the way in, so adding a setting in a later version
    /// never throws away an existing state.json — and with it, the whole history.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Three generations of this field, oldest last. A settings file from any of them
        // has to survive, because losing it would take the whole history with it.
        if let list = try? c.decode([KeyBinding].self, forKey: .bindings), !list.isEmpty {
            bindings = list
        } else if let single = try? c.decode(KeyBinding.self, forKey: .binding) {
            bindings = [single]
        } else if let legacy = try? c.decode(HotKey.self, forKey: .hotKey) {
            bindings = [legacy.binding]
        }

        insertionMode = try c.decodeIfPresent(InsertionMode.self, forKey: .insertionMode)
            ?? insertionMode
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? language
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? playSounds
        showPill = try c.decodeIfPresent(Bool.self, forKey: .showPill) ?? showPill
        doubleTapToLock = try c.decodeIfPresent(Bool.self, forKey: .doubleTapToLock)
            ?? doubleTapToLock
        minimumDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .minimumDuration)
            ?? minimumDuration
        allowAllApps = try c.decodeIfPresent(Bool.self, forKey: .allowAllApps) ?? allowAllApps
        cleanupEverywhere = try c.decodeIfPresent(Bool.self, forKey: .cleanupEverywhere)
            ?? cleanupEverywhere
        typingWPM = try c.decodeIfPresent(Double.self, forKey: .typingWPM) ?? typingWPM
        wordUnit = try c.decodeIfPresent(WordUnit.self, forKey: .wordUnit) ?? wordUnit
        modelPath = try c.decodeIfPresent(String.self, forKey: .modelPath) ?? modelPath
        modelPrefix = try c.decodeIfPresent(String.self, forKey: .modelPrefix) ?? modelPrefix
        cliPath = try c.decodeIfPresent(String.self, forKey: .cliPath) ?? cliPath
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bindings, forKey: .bindings)
        try c.encode(insertionMode, forKey: .insertionMode)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(playSounds, forKey: .playSounds)
        try c.encode(showPill, forKey: .showPill)
        try c.encode(doubleTapToLock, forKey: .doubleTapToLock)
        try c.encode(minimumDuration, forKey: .minimumDuration)
        try c.encode(allowAllApps, forKey: .allowAllApps)
        try c.encode(cleanupEverywhere, forKey: .cleanupEverywhere)
        try c.encode(typingWPM, forKey: .typingWPM)
        try c.encode(wordUnit, forKey: .wordUnit)
        try c.encode(modelPath, forKey: .modelPath)
        try c.encode(modelPrefix, forKey: .modelPrefix)
        try c.encode(cliPath, forKey: .cliPath)
    }
}
