import SwiftUI

struct PromptsView: View {
    @ObservedObject var store: Store
    @State private var editing: Prompt?

    var body: some View {
        Page(
            title: "Prompts",
            lead: "Say the name of a saved prompt and BlarneyKey pastes the whole thing instead of the words you said. Say \"Get Things Done\" and the full template lands."
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("PROMPTS (\(store.prompts.count))").eyebrow()
                    Spacer()
                    Button("New prompt") {
                        editing = Prompt(trigger: "", expansion: "")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }

                VStack(spacing: 0) {
                    if store.prompts.isEmpty {
                        Note(kind: .plain, text: "No prompts yet.")
                    }
                    ForEach(Array(store.prompts.enumerated()), id: \.element.id) { index, prompt in
                        if index > 0 { RowDivider() }
                        row(prompt)
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
        .sheet(item: $editing) { prompt in
            PromptEditor(prompt: prompt) { saved in
                store.upsert(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private func row(_ prompt: Prompt) -> some View {
        Button {
            editing = prompt
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.inkMuted48)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.trigger)
                        .font(Theme.Text.bodyStrong())
                        .tracking(Theme.Text.Track.body)
                        .foregroundStyle(Theme.Colour.ink)
                    Text(prompt.expansion.split(separator: "\n").first.map(String.init) ?? "")
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Space.sm)

                Button {
                    store.remove(prompt)
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

private struct PromptEditor: View {
    @State var prompt: Prompt
    let onSave: (Prompt) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(prompt.trigger.isEmpty ? "New prompt" : "Edit prompt")
                .font(Theme.Text.displayMd())
                .tracking(Theme.Text.Track.display)
                .foregroundStyle(Theme.Colour.ink)

            VStack(alignment: .leading, spacing: 5) {
                Text("TRIGGER PHRASE").eyebrow()
                TextField("weekly business review", text: $prompt.trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Text.body())
                Text("Matching ignores case and punctuation.")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("EXPANSION").eyebrow()
                TextEditor(text: $prompt.expansion)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 190)
                    .padding(4)
                    .cardSurface(Theme.Colour.canvas, radius: Theme.Radius.sm, bordered: true)
            }

            HStack(spacing: Theme.Space.xs) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Save") { onSave(prompt) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.trigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.expansion.isEmpty)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 500)
        .background(Theme.Colour.parchment)
    }
}
