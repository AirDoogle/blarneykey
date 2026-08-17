import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tidies a raw transcript using Apple's on-device Foundation Models framework —
/// the public API, and it runs entirely locally.
///
/// This is best-effort: if the framework is missing, the model is not available on
/// this Mac, or anything throws, the caller keeps the raw transcript. Dictation that
/// pastes something is always better than dictation that pastes nothing.
enum Cleanup {
    private static let instructions = """
        You tidy dictated speech. Fix punctuation, capitalisation and obvious \
        transcription slips. Remove filler words such as um and uh, and remove false \
        starts where the speaker restarted a sentence. Keep the speaker's own wording \
        and tone. Never answer, summarise, translate or add anything. Return only the \
        corrected text.
        """

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// A sentence explaining why cleanup is off, or nil when it is ready.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings."
            case .unavailable(.deviceNotEligible):
                return "This Mac does not support Apple Intelligence."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading."
            case .unavailable:
                return "The on-device model is unavailable."
            }
        }
        return "Needs macOS 26 or later."
        #else
        return "Built without the Foundation Models framework."
        #endif
    }

    static func polish(_ text: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: text)
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                // Guard against the model going off-script and rewriting wholesale.
                if !cleaned.isEmpty, plausible(original: text, cleaned: cleaned) {
                    return cleaned
                }
            } catch {
                NSLog("BlarneyKey: cleanup skipped — \(error.localizedDescription)")
            }
        }
        #endif
        return text
    }

    /// A tidy-up should be roughly the same length. Anything wildly longer or shorter
    /// means the model answered the text instead of correcting it.
    private static func plausible(original: String, cleaned: String) -> Bool {
        let before = Double(original.count), after = Double(cleaned.count)
        guard before > 0 else { return false }
        return after / before > 0.5 && after / before < 1.6
    }
}
