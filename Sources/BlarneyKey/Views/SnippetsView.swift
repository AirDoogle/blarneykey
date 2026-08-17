import SwiftUI

struct SnippetsView: View {
    @ObservedObject var store: Store
    @State private var editing: Snippet?

    var body: some View {
        Page(
            title: "Snippets",
            lead: "Say a trigger phrase and BlarneyKey pastes the full text instead. For example, say \"weekly business review\"."
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("SNIPPETS (\(store.snippets.count))").eyebrow()
                    Spacer()
                    Button("New snippet") {
                        editing = Snippet(trigger: "", expansion: "")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }

                VStack(spacing: 0) {
                    if store.snippets.isEmpty {
                        Note(kind: .plain, text: "No snippets yet.")
                    }
                    ForEach(Array(store.snippets.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 { RowDivider() }
                        row(snippet)
                    }
                }
                .cardSurface()
            }
            .reveal(1)

            Section_(label: "HOW MATCHING WORKS", index: 2) {
                Note(kind: .plain,
                     text: "The whole utterance has to be the trigger phrase, so a trigger buried in a sentence will not swallow it. Case, punctuation and extra spaces are ignored.")
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { saved in
                store.upsert(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        Button {
            editing = snippet
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.inkMuted48)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.trigger)
                        .font(Theme.Text.bodyStrong())
                        .tracking(Theme.Text.Track.body)
                        .foregroundStyle(Theme.Colour.ink)
                    Text(snippet.expansion.split(separator: "\n").first.map(String.init) ?? "")
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Space.sm)

                Button {
                    store.remove(snippet)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colour.inkMuted48)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(snippet.trigger.isEmpty ? "New snippet" : "Edit snippet")
                .font(Theme.Text.displayMd())
                .tracking(Theme.Text.Track.display)
                .foregroundStyle(Theme.Colour.ink)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRIGGER PHRASE").eyebrow()
                TextField("weekly business review", text: $snippet.trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Text.body())
                Text("Matching ignores case and punctuation.")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("EXPANSION").eyebrow()
                TextEditor(text: $snippet.expansion)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 190)
                    .padding(4)
                    .cardSurface(Theme.Colour.canvas, radius: Theme.Radius.sm)
            }

            HStack(spacing: Theme.Space.xs) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Save") { onSave(snippet) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(snippet.trigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || snippet.expansion.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 500)
        .background(Theme.Colour.parchment)
    }
}
