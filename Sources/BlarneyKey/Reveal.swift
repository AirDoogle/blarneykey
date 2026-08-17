import SwiftUI

/// The standard build-in, as specified in the Motion section of the design system:
/// fade plus a 26pt rise, staggered 70–130ms down the reading order, fired once.
///
/// Reduced motion is a *final state*, not a degraded one — the content resolves to its
/// finished appearance immediately rather than being hidden or animating anyway.
struct Reveal: ViewModifier {
    /// Position in the reading order within this lockup. Group by lockup, not by page:
    /// a heading, its sub-line and its CTA are one group starting at zero.
    let index: Int
    /// Above the fold uses the faster step so the hero is not still assembling.
    let aboveFold: Bool
    /// Blur is for display-size and narrative copy only. Blurred small text reads as a
    /// rendering fault, and it is the most expensive property here to composite.
    let blurred: Bool

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double {
        Double(index) * (aboveFold ? Theme.Motion.staggerFast : Theme.Motion.stagger)
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: shown ? 0 : (blurred ? Theme.Motion.blur : 0))
            .opacity(shown ? 1 : 0)
            // Applies to everything above it, giving opacity the longer leg.
            .animation(Theme.Motion.fade.delay(delay), value: shown)
            .offset(y: shown ? 0 : Theme.Motion.travel)
            .animation(Theme.Motion.rise.delay(delay), value: shown)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                // A tick later, so the transition has a start state to animate from.
                DispatchQueue.main.async { shown = true }
            }
    }
}

extension View {
    /// Standard build-in. Don't stagger more than about six children in one group — past
    /// that the last child is late enough that the reader notices they are waiting.
    func reveal(_ index: Int = 0, aboveFold: Bool = false, blurred: Bool = false) -> some View {
        modifier(Reveal(index: index, aboveFold: aboveFold, blurred: blurred))
    }
}

/// Press state is `scale(0.95)` — the system-wide micro-interaction. Applied through a
/// button style so every control in the app gets it without being asked.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.Motion.interaction, value: configuration.isPressed)
    }
}

/// The signature action: Action Blue, full pill. The pill radius *is* the action signal,
/// so it is reserved for this and never used decoratively.
struct PillButtonStyle: ButtonStyle {
    var onDark = false
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        let accent = onDark ? Theme.Colour.primaryOnDark : Theme.Colour.primary
        configuration.label
            .font(Theme.Text.body())
            .tracking(Theme.Text.Track.body)
            .foregroundStyle(prominent ? Theme.Colour.onDark : accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(minHeight: 28)
            .background {
                if prominent {
                    Capsule().fill(accent)
                } else {
                    Capsule().strokeBorder(accent, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.Motion.interaction, value: configuration.isPressed)
    }
}

/// The compact utility rectangle — the second and last button grammar in the system.
struct UtilityButtonStyle: ButtonStyle {
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Text.caption())
            .tracking(Theme.Text.Track.body)
            .foregroundStyle(onDark ? Theme.Colour.onDark : Theme.Colour.inkMuted80)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(onDark ? Theme.Colour.tile2 : Theme.Colour.pearl)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(onDark ? .clear : Theme.Colour.dividerSoft, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.Motion.interaction, value: configuration.isPressed)
    }
}
