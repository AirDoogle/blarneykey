import SwiftUI

/// The keys that rewrite selected text by voice.
struct CommandSettings: View {
    @ObservedObject var store: Store
    let index: Int

    @State private var capturing = false

    var body: some View {
        Section_(label: "COMMAND MODE", index: index) {
            Row(
                title: "Shift + your Blarney key",
                detail: Cleanup.unavailableReason
                    ?? "Select text, hold \u{21E7} with your Blarney key and say what to change, such as \u{201C}make this more assertive\u{201D}. Runs on this Mac. \u{2318}Z undoes it. In Claude Code, highlight any part of your unsent draft and the whole draft is rewritten in place; highlight its output and a rewritten copy lands at the cursor."
            ) {
                EmptyView()
            }
            RowDivider()
            Row(
                title: "Or a separate command key",
                detail: "Optional. Hold it on its own instead of using \u{21E7}."
            ) {
                Button("Add a key") { capturing = true }
                    .buttonStyle(PillButtonStyle())
            }

            ForEach(store.settings.commandBindings, id: \.self) { key in
                RowDivider()
                HStack(spacing: Theme.Space.sm) {
                    Text(key.label)
                        .font(Theme.Text.body())
                        .foregroundStyle(Theme.Colour.ink)
                    Spacer(minLength: Theme.Space.sm)
                    Button {
                        store.settings.commandBindings.removeAll { $0 == key }
                        store.save()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colour.inkMuted48)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Remove this key")
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $capturing) {
            KeyCaptureSheet(current: store.settings.commandBindings.first ?? store.settings.primaryBinding,
                            existing: store.settings.bindings + store.settings.commandBindings) { binding in
                let taken = store.settings.bindings + store.settings.commandBindings
                if !taken.contains(binding) {
                    store.settings.commandBindings.append(binding)
                    store.save()
                }
                capturing = false
            } onCancel: {
                capturing = false
            }
        }
    }
}
