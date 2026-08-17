import SwiftUI

struct SnippetsView: View {
    @ObservedObject var store: Store
    @State private var editing: Snippet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snippets").font(.largeTitle.weight(.bold))
                    Text("Say a trigger phrase and BlarneyKey pastes the full text instead. For example, say \"weekly business review\".")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    editing = Snippet(trigger: "", expansion: "")
                } label: {
                    Label("New snippet", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                if store.snippets.isEmpty {
                    Text("No snippets yet.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.snippets) { snippet in
                            row(snippet)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Snippets")
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.trigger).font(.callout.weight(.semibold))
                Text(snippet.expansion.split(separator: "\n").first.map(String.init) ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.remove(snippet)
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { editing = snippet }
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snippet.trigger.isEmpty ? "New snippet" : "Edit snippet")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("TRIGGER PHRASE")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                TextField("weekly business review", text: $snippet.trigger)
                    .textFieldStyle(.roundedBorder)
                Text("Matching ignores case and punctuation.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("EXPANSION")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                TextEditor(text: $snippet.expansion)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") { onSave(snippet) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(snippet.trigger.trimmingCharacters(in: .whitespaces).isEmpty
                              || snippet.expansion.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
