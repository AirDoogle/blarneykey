import AppKit
import SwiftUI

/// Edit a past transcript and BlarneyKey works out which words it got wrong, then offers
/// to fix them on every future dictation.
struct CorrectionSheet: View {
    @ObservedObject var store: Store
    let text: String
    let onClose: () -> Void

    @State private var edited = ""
    @State private var chosen = Set<String>()
    @State private var seen = Set<String>()

    private var found: [Vocabulary.Learned] {
        Vocabulary.learn(from: text, to: edited, isOrdinaryWord: Self.isOrdinaryWord)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Teach it a correction")
                    .font(Theme.Text.displayMd())
                    .foregroundStyle(Theme.Colour.ink)
                Text("Change the words it got wrong. Nothing is saved until you add them.")
                    .font(Theme.Text.body())
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            TextEditor(text: $edited)
                .font(Theme.Text.body())
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Colour.hairline))

            ForEach(found) { item in
                Toggle(isOn: Binding(
                    get: { chosen.contains(item.id) },
                    set: { if $0 { chosen.insert(item.id) } else { chosen.remove(item.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.heard)  \u{2192}  \(item.write)")
                            .font(Theme.Text.body())
                            .foregroundStyle(Theme.Colour.ink)
                        if !item.safe {
                            Text("An ordinary word. This would replace it every time you say it.")
                                .font(Theme.Text.caption())
                                .foregroundStyle(Theme.Colour.warn)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(PillButtonStyle())
                Button("Add") { add() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(found.filter { chosen.contains($0.id) }.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 460)
        .onAppear { edited = text }
        .onChange(of: edited) {
            // Tick new safe corrections once, and never re-tick one you turned off.
            for item in found where !seen.contains(item.id) {
                seen.insert(item.id)
                if item.safe { chosen.insert(item.id) }
            }
        }
    }

    private func add() {
        for item in found where chosen.contains(item.id) {
            store.settings.wordFixes.removeAll {
                $0.heard.caseInsensitiveCompare(item.heard) == .orderedSame
            }
            store.settings.wordFixes.append(WordFix(heard: item.heard, write: item.write))
            if !store.settings.vocabulary.contains(item.write) {
                store.settings.vocabulary.append(item.write)
            }
        }
        store.save()
        onClose()
    }

    private static func isOrdinaryWord(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }
}
