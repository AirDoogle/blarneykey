import AppKit
import Combine

/// Watches the Accessibility grant, which BlarneyKey cannot work without.
///
/// Worth its own type because the grant is *revocable behind your back*: macOS ties it to
/// the app's code signature, so re-signing the bundle — which every rebuild does — leaves
/// a stale entry that still looks ticked in System Settings but no longer authorises
/// anything. Polling is the only way to notice.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var hasAccessibility: Bool

    private var timer: Timer?

    private init() {
        hasAccessibility = AXIsProcessTrusted()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = AXIsProcessTrusted()
            if current != self.hasAccessibility {
                self.hasAccessibility = current
            }
        }
    }

    /// Ask for the grant and open the pane, since the dialog alone is easy to dismiss.
    func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSettings()
    }

    func openSettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reveals the app so it can be dragged into the Accessibility list, which is the
    /// reliable way to replace a stale entry.
    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
