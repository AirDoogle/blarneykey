import SwiftUI

/// The Cork AI Consulting design system, as it applies to a native macOS app.
///
/// Source of truth: `cork_ai_consulting/jobs_to_be_done/06_website/01_design/design.md`.
/// That file is medium-independent and instructs us to take the principle and apply the
/// nearest equivalent where a rule is web-specific.
///
/// The two rules that shape everything here: **one accent colour**, and **elevation comes
/// from the surface changing, not from chrome**.
enum Theme {

    // MARK: - Colour

    enum Colour {
        // Light-surface tokens follow the system appearance. Dark-tile tokens do not:
        // a dark tile is dark in both themes, which is what lets its on-dark text hold
        // contrast either way.
        //
        // The design system documents no dark-mode palette (it says so in Known Gaps),
        // so these dark values follow its own principles: the accent shifts to Sky Link
        // Blue exactly as it does on a dark tile, ink inverts to the on-dark ladder, and
        // surfaces step in the same small increments the near-black tiles use.

        /// Action Blue on light, Sky Link Blue on dark. The single interactive colour.
        static let primary = dynamic(light: 0x0066CC, dark: 0x2997FF)
        /// The same role where the surface is a dark tile regardless of theme.
        static let primaryOnDark = fixed(0x2997FF)
        static let primaryFocus = dynamic(light: 0x0071E3, dark: 0x2997FF)

        // Surfaces that follow the theme.
        static let canvas = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let parchment = dynamic(light: 0xF5F5F7, dark: 0x242426)
        static let pearl = dynamic(light: 0xFAFAFC, dark: 0x2C2C2E)

        // Near-black tiles. Fixed: dark in both themes, by design.
        static let tile1 = fixed(0x272729)
        static let tile2 = fixed(0x2A2A2C)
        static let tile3 = fixed(0x252527)
        static let black = fixed(0x000000)

        // Text on theme-following surfaces.
        static let ink = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
        static let inkMuted80 = dynamic(light: 0x333333, dark: 0xD1D1D6)
        static let inkMuted48 = dynamic(light: 0x7A7A7A, dark: 0x98989D)

        // Text on dark tiles. Never reach for inkMuted48 here: in light theme its value
        // lands at 2.7:1 on a dark surface.
        static let onDark = fixed(0xFFFFFF)
        static let bodyMuted = fixed(0xCCCCCC)
        static let onDarkFaint = fixed(0x98989D)

        // Hairlines. These are rings, not hard lines.
        static let hairline = dynamic(light: 0xE0E0E0, dark: 0x3A3A3C)
        static let dividerSoft = dynamic(light: 0xF0F0F0, dark: 0x303032)

        /// Semantic status. Not accents: they label state, never interactivity, and only
        /// ever appear as a small glyph or a hairline, never as a fill behind copy.
        /// Each lifts on dark, where the light-theme value would fall under 4.5:1.
        static let ok = dynamic(light: 0x1D8348, dark: 0x30D158)
        static let warn = dynamic(light: 0xB25000, dark: 0xFF9F0A)
        static let stop = dynamic(light: 0xB3261E, dark: 0xFF6961)

        // MARK: Plumbing

        /// A colour that resolves per appearance, so every view adapts without asking.
        private static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }

        private static func fixed(_ hex: UInt32) -> Color {
            Color(nsColor: NSColor(hex: hex))
        }
    }

    // MARK: - Typography

    /// The web ladder is in px for a 1440px page; this app's widest surface is a 980pt
    /// window, so display sizes compress while the *ratios*, weights and negative
    /// tracking carry over unchanged. The 300/400/600/700 ladder holds — weight 500 is
    /// deliberately absent here too.
    enum Text {
        static func heroDisplay() -> Font { .system(size: 34, weight: .semibold) }
        static func displayLg() -> Font { .system(size: 26, weight: .semibold) }
        static func displayMd() -> Font { .system(size: 21, weight: .semibold) }
        static func statNumber() -> Font { .system(size: 32, weight: .semibold) }
        static func lead() -> Font { .system(size: 17, weight: .regular) }
        static func leadAiry() -> Font { .system(size: 17, weight: .light) }
        static func tagline() -> Font { .system(size: 15, weight: .semibold) }
        static func bodyStrong() -> Font { .system(size: 13, weight: .semibold) }
        static func body() -> Font { .system(size: 13, weight: .regular) }
        static func caption() -> Font { .system(size: 11, weight: .regular) }
        static func captionStrong() -> Font { .system(size: 11, weight: .semibold) }
        static func eyebrow() -> Font { .system(size: 10, weight: .semibold) }
        static func finePrint() -> Font { .system(size: 10, weight: .regular) }

        /// Negative tracking at display sizes is the signature of the system. Never
        /// applied at 12pt or below — and the eyebrow is the one positive-tracking device.
        enum Track {
            static let hero: CGFloat = -0.6
            static let display: CGFloat = -0.4
            static let body: CGFloat = -0.2
            static let none: CGFloat = 0
            static let eyebrow: CGFloat = 1.2
        }
    }

    // MARK: - Shape

    enum Radius {
        static let none: CGFloat = 0
        static let xs: CGFloat = 5
        static let sm: CGFloat = 8      // compact utility controls
        static let md: CGFloat = 11     // pearl capsules
        static let lg: CGFloat = 18     // utility cards
    }

    // MARK: - Space

    /// The 8pt base with the system's sub-base steps. `section` compresses from the web's
    /// 80px to 40pt: inside a 700pt-tall window, 80 would put one tile per viewport.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 17
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let section: CGFloat = 40
    }

    // MARK: - Motion

    /// The standard build-in: everything arrives, nothing performs. Fade plus a rise of
    /// roughly one line of body text, staggered down the reading order.
    ///
    /// The fade deliberately outlasts the travel — the element lands in position while
    /// still slightly transparent, then settles into full colour. Equal durations are
    /// what make a reveal feel mechanical.
    enum Motion {
        static let travel: CGFloat = 26
        static let blur: CGFloat = 9

        /// Above the fold, so the hero is not still assembling as you start reading.
        static let staggerFast: Double = 0.07
        /// Below the fold.
        static let stagger: Double = 0.13

        static let fade = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.9)
        static let rise = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.7)

        /// Interaction timings. Under 150ms reads as a glitch.
        static let interaction = Animation.easeInOut(duration: 0.2)
        static let stateChange = Animation.easeInOut(duration: 0.4)
    }
}

// MARK: - Helpers

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// A tracked, uppercase label that *labels* something rather than naming it — the one
    /// sanctioned use of positive tracking in the system.
    func eyebrow(onDark: Bool = false) -> some View {
        font(Theme.Text.eyebrow())
            .tracking(Theme.Text.Track.eyebrow)
            .foregroundStyle(onDark ? Theme.Colour.onDarkFaint : Theme.Colour.inkMuted48)
    }

    /// The 1pt hairline ring used on utility cards. A ring, not a border.
    func cardSurface(_ fill: Color = Theme.Colour.canvas,
                     radius: CGFloat = Theme.Radius.lg) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.Colour.hairline, lineWidth: 1)
            )
    }
}
