import AVFoundation
import Foundation

/// A phrase the speech model tends to mishear, and what to write instead.
struct WordFix: Codable, Hashable, Identifiable {
    var id = UUID()
    var heard: String
    var write: String
}

/// Helps the speech model get your own names and places right, in two ways: a list of
/// words it is told to expect before it starts, and corrections applied to what it wrote.
enum Vocabulary {
    /// Whisper's prompt holds about 224 tokens and unusual names cost several each, so
    /// words past this length are left out rather than letting the model truncate them.
    static let maxPromptCharacters = 600

    /// Whisper works in 30-second windows. Measured, the word list cost no words within
    /// one window but lost a few on clips over 45 seconds, where it carries across them.
    static let maxPromptSeconds: TimeInterval = 30

    /// The text to hand Whisper, or nil when there is no list or the clip is too long.
    /// An unknown duration counts as too long, since the list is only ever an extra.
    static func prompt(words: [String], audioSeconds: TimeInterval?) -> String? {
        guard let audioSeconds, audioSeconds <= maxPromptSeconds else { return nil }
        let fitting = wordsThatFit(words)
        return fitting.isEmpty ? nil : fitting.joined(separator: ", ") + "."
    }

    /// The leading words that fit in the prompt, skipping blanks.
    static func wordsThatFit(_ words: [String]) -> [String] {
        var fitting: [String] = []
        var length = 0
        for word in words.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !word.isEmpty {
            length += word.count + 2
            guard length <= maxPromptCharacters else { break }
            fitting.append(word)
        }
        return fitting
    }

    static func duration(of audio: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: audio),
              file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Replaces each misheard phrase, whole words only and ignoring case. Longest first,
    /// so "Mary Murfy" is matched before a shorter fix for "Murfy" alone.
    static func apply(_ fixes: [WordFix], to text: String) -> String {
        var result = text
        for fix in fixes.sorted(by: { $0.heard.count > $1.heard.count }) {
            result = replace(fix, in: result)
        }
        return result
    }

    /// A correction found by comparing a transcript with your edited version of it.
    struct Learned: Hashable, Identifiable {
        var heard: String
        var write: String
        /// False when `heard` is an ordinary word, like "their" for "there". Replacing it
        /// on every dictation would do damage, so it needs a deliberate opt-in.
        var safe: Bool
        var id: String { heard + "\u{0}" + write }
    }

    /// The word-level changes between two versions of a transcript. Only replacements
    /// count: text you added or deleted says nothing about what was misheard.
    static func learn(from original: String, to edited: String,
                      isOrdinaryWord: (String) -> Bool) -> [Learned] {
        let before = words(in: original), after = words(in: edited)
        let difference = after.difference(from: before)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var found: [Learned] = []
        var i = 0, j = 0
        while i < before.count || j < after.count {
            guard removed.contains(i) || inserted.contains(j) else { i += 1; j += 1; continue }
            let heardStart = i, writeStart = j
            while removed.contains(i) { i += 1 }
            while inserted.contains(j) { j += 1 }
            let heard = before[heardStart..<i], write = after[writeStart..<j]
            // Long spans are a rewrite, which would never recur word for word.
            guard !heard.isEmpty, !write.isEmpty, heard.count <= 4, write.count <= 4 else { continue }
            let phrase = heard.joined(separator: " ")
            let item = Learned(heard: phrase, write: write.joined(separator: " "),
                               safe: heard.count > 1 || !isOrdinaryWord(phrase))
            if !found.contains(item) { found.append(item) }
        }
        return found
    }

    /// Words with the punctuation at their edges removed, so "Cork," matches "Cork".
    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    private static func replace(_ fix: WordFix, in text: String) -> String {
        let parts = fix.heard.split(whereSeparator: \.isWhitespace).map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        guard !parts.isEmpty, !fix.write.isEmpty else { return text }
        let pattern = "(?<![\\p{L}\\p{N}])" + parts.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return text }

        let result = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            // A fix like "Acme" -> "Acme Holdings" must leave text that already
            // has the full name alone.
            let rest = result.substring(from: match.range.location)
            if rest.range(of: fix.write, options: [.anchored, .caseInsensitive]) != nil { continue }
            result.replaceCharacters(in: match.range, with: fix.write)
        }
        return result as String
    }
}
