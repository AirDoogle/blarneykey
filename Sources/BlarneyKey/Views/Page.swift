import SwiftUI

/// Shared page furniture, so every surface in the app has the same chassis: a display
/// title, a lead line, then sections of hairline-ringed rows on a parchment canvas.
struct Page<Content: View>: View {
    let title: String
    let lead: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Theme.Text.displayLg())
                        .tracking(Theme.Text.Track.display)
                        .foregroundStyle(Theme.Colour.ink)
                    Text(lead)
                        .font(Theme.Text.lead())
                        .tracking(Theme.Text.Track.body)
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .reveal(0, aboveFold: true, blurred: true)

                content
            }
            .padding(Theme.Space.section)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Reserve scrollable room past the last section so it clears the window's bottom
        // edge — without it the final card (History, on a long Settings page) sat flush
        // against the frame and read as cut off even when fully scrolled.
        .contentMargins(.bottom, Theme.Space.xxl, for: .scrollContent)
        .background(Theme.Colour.parchment)
        .navigationTitle(title)
    }
}

/// A titled group of rows. The eyebrow labels it; the card holds it.
struct Section_<Content: View>: View {
    let label: String
    var index: Int = 1
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label).eyebrow()
            VStack(alignment: .leading, spacing: 0) { content }
                .cardSurface()
        }
        .reveal(index)
    }
}

/// One setting: name, explanation, control. 44pt minimum height for the touch target.
struct Row<Control: View>: View {
    let title: String
    var detail: String?
    /// Longer explanation shown as a native hover tooltip off a small (i) glyph,
    /// for settings that need more context than fits in the one-line detail.
    var info: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(Theme.Text.bodyStrong())
                        .tracking(Theme.Text.Track.body)
                        .foregroundStyle(Theme.Colour.ink)
                    if let info {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colour.inkMuted48)
                            .help(info)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(Theme.Text.caption())
                        .foregroundStyle(Theme.Colour.inkMuted48)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            control
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .frame(minHeight: 44)
    }
}

/// A note inside a card — explanation, warning or confirmation. Warnings carry a glyph as
/// well as colour, because colour is never the only signal.
struct Note: View {
    enum Kind { case plain, warn, ok, stop }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 1)
            }
            Text(text)
                .font(Theme.Text.caption())
                .foregroundStyle(kind == .plain ? Theme.Colour.inkMuted48 : tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
    }

    private var symbol: String? {
        switch kind {
        case .plain: return nil
        case .warn: return "exclamationmark.triangle.fill"
        case .ok: return "checkmark.circle.fill"
        case .stop: return "exclamationmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .plain: return Theme.Colour.inkMuted48
        case .warn: return Theme.Colour.warn
        case .ok: return Theme.Colour.ok
        case .stop: return Theme.Colour.stop
        }
    }
}

/// The hairline between rows inside a card, inset so it reads as a divider rather than a
/// line across the whole surface.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colour.dividerSoft)
            .frame(height: 1)
            .padding(.leading, Theme.Space.md)
    }
}
