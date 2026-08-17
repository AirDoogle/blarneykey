import AppKit
import SwiftUI

/// The app's own marks and its one line of copy, in one place so they cannot drift apart
/// between the sidebar, the hero and the docs.
enum Brand {

    /// The tagline. It explains that the key *is* the Blarney key, which is the joke the
    /// whole name rests on, and it says it once rather than in every string.
    static let tagline = "Hold the Blarney key for the gift of the gab."

    /// Marks live in the bundle's Resources, copied there by build.sh.
    private static func image(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let nsImage = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: nsImage)
    }

    /// The BlarneyKey keep. Transparent background, so the arrow slits and the gaps
    /// between the arcs take the colour of whatever is behind them, in either appearance.
    @ViewBuilder
    static func mark(size: CGFloat) -> some View {
        if let image = image("blarneykey-mark") {
            image.resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            // The app still has to run if the resource is missing from the bundle.
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(Theme.Colour.primary)
        }
    }

    /// The Cork AI Consulting crest.
    @ViewBuilder
    static func corkMark(size: CGFloat) -> some View {
        if let image = image("cork-ai-consulting-mark") {
            image.resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "building.columns")
                .font(.system(size: size * 0.8))
                .foregroundStyle(Theme.Colour.primary)
        }
    }

    /// UTM tagged per `06_website/03_analytics/utm_tracking.md`, and registered in that
    /// doc's table. Frozen once anyone has the app installed.
    static let corkURL = URL(string:
        "https://corkaiconsulting.ie/?utm_source=blarneykey&utm_medium=referral"
        + "&utm_campaign=blarneykey-app&utm_content=about-footer"
    )!
}
