import SwiftUI

/// Settings for the names and places the speech model should get right.
struct WordsSettings: View {
    @ObservedObject var store: Store
    let index: Int

    @State private var newWord = ""
    @State private var heard = ""
    @State private var write = ""

    var body: some View {
        Section_(label: "WORDS", index: index) {
            Row(
                title: "Words to expect",
                detail: "Names and places to listen for, on dictations up to 30 seconds. Adds about a third of a second."
            ) {
                HStack(spacing: Theme.Space.xs) {
                    TextField("Add a word or name", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Text.body())
                        .frame(width: 200)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .buttonStyle(PillButtonStyle())
                        .disabled(trimmed(newWord).isEmpty)
                }
            }

            ForEach(store.settings.vocabulary, id: \.self) { word in
                RowDivider()
                itemRow(word) {
                    store.settings.vocabulary.removeAll { $0 == word }
                    store.save()
                }
            }

            if listIsTooLong {
                RowDivider()
                Note(kind: .warn,
                     text: "The list is longer than the model can hold, so the words at the end are being left out.")
            }

            RowDivider()
            Row(
                title: "Corrections",
                detail: "Swaps a phrase it keeps mishearing for the right one, on every dictation. Whole words only, ignoring case."
            ) {
                HStack(spacing: Theme.Space.xs) {
                    TextField("When it hears", text: $heard)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Text.body())
                        .frame(width: 130)
                    TextField("Write", text: $write)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Text.body())
                        .frame(width: 130)
                        .onSubmit(addFix)
                    Button("Add", action: addFix)
                        .buttonStyle(PillButtonStyle())
                        .disabled(trimmed(heard).isEmpty || trimmed(write).isEmpty)
                }
            }

            ForEach(store.settings.wordFixes) { fix in
                RowDivider()
                itemRow("\(fix.heard)  \u{2192}  \(fix.write)") {
                    store.settings.wordFixes.removeAll { $0.id == fix.id }
                    store.save()
                }
            }
        }
    }

    private var listIsTooLong: Bool {
        let words = store.settings.vocabulary.filter { !trimmed($0).isEmpty }
        return Vocabulary.wordsThatFit(words).count < words.count
    }

    private func itemRow(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(text)
                .font(Theme.Text.body())
                .foregroundStyle(Theme.Colour.ink)
                .textSelection(.enabled)
            Spacer(minLength: Theme.Space.sm)
            Button(action: remove) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }
            .buttonStyle(PressableButtonStyle())
            .help("Remove")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xs)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        let word = trimmed(newWord)
        guard !word.isEmpty else { return }
        if !store.settings.vocabulary.contains(word) {
            store.settings.vocabulary.append(word)
            store.save()
        }
        newWord = ""
    }

    private func addFix() {
        let from = trimmed(heard), to = trimmed(write)
        guard !from.isEmpty, !to.isEmpty else { return }
        store.settings.wordFixes.removeAll { $0.heard.caseInsensitiveCompare(from) == .orderedSame }
        store.settings.wordFixes.append(WordFix(heard: from, write: to))
        store.save()
        heard = ""
        write = ""
    }
}
