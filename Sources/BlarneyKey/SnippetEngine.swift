import Foundation

/// Say a trigger phrase, get the full text pasted instead.
///
/// Matching ignores case, punctuation and repeated spaces, because a speech model
/// will happily give you "Weekly business review." when you said the words plainly.
enum SnippetEngine {
    static func normalise(_ text: String) -> String {
        let stripped = text.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        return String(String.UnicodeScalarView(stripped))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Returns the expansion if the whole utterance is the trigger phrase.
    /// Deliberately strict: a trigger buried in a sentence should not swallow it.
    static func expand(_ text: String, using snippets: [Snippet]) -> String? {
        let spoken = normalise(text)
        guard !spoken.isEmpty else { return nil }
        return snippets.first { normalise($0.trigger) == spoken }?.expansion
    }
}
