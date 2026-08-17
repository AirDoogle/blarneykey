import SwiftUI

/// The Cork AI Consulting design system, as it applies to a native macOS app.
///
/// Source of truth: `cork_ai_consulting/jobs_to_be_done/06_website/01_design/design.md`.
/// That file is medium-independent and instructs us to take the principle and apply the
/// nearest equivalent where a rule is web-specific — see the "macOS app" section added
/// there for the three mappings this file makes (type scale, section rhythm, surfaces).
///
/// The two rules that shape everything here: **one accent colour**, and **elevation comes
/// from the surface changing, not from chrome**.
enum Theme {

    // MARK: - Colour

    enum Colour {
        /// Action Blue. The single interactive colour on light surfaces. Nothing else.
        static let primary = Color(hex: 0x0066CC)
        /// Sky Link Blue. The same role, on a dark tile, where Action Blue disappears.
        static let primaryOnDark = Color(hex: 0x2997FF)
        static let primaryFocus = Color(hex: 0x0071E3)

        // Surfaces. Brand-fixed, not theme-following: a dark tile is dark in both themes,
        // so its on-dark text tokens hold contrast either way.
        static let canvas = Color(hex: 0xFFFFFF)
        static let parchment = Color(hex: 0xF5F5F7)
        static let pearl = Color(hex: 0xFAFAFC)
        static let tile1 = Color(hex: 0x272729)
        static let tile2 = Color(hex: 0x2A2A2C)
        static let tile3 = Color(hex: 0x252527)
        static let black = Color(hex: 0x000000)

        // Text on light surfaces.
        static let ink = Color(hex: 0x1D1D1F)
        static let inkMuted80 = Color(hex: 0x333333)
        static let inkMuted48 = Color(hex: 0x7A7A7A)

        // Text on dark tiles. Never reach for inkMuted48 here — it fails contrast.
        static let onDark = Color(hex: 0xFFFFFF)
        static let bodyMuted = Color(hex: 0xCCCCCC)
        static let onDarkFaint = Color(hex: 0x98989D)

        // Hairlines. These are rings, not hard lines.
        static let hairline = Color(hex: 0xE0E0E0)
        static let dividerSoft = Color(hex: 0xF0F0F0)

        /// Semantic status. Not accents: they label state, never interactivity, and only
        /// ever appear as a small glyph or a hairline — never as a fill behind copy.
        static let ok = Color(hex: 0x1D8348)
        static let warn = Color(hex: 0xB25000)
        static let stop = Color(hex: 0xB3261E)
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

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
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

    /// The 1px hairline ring used on utility cards. A ring, not a border.
    func cardSurface(_ fill: Color = Theme.Colour.canvas,
                     radius: CGFloat = Theme.Radius.lg) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.Colour.hairline, lineWidth: 1)
            )
    }
}
