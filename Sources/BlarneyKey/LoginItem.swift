import ServiceManagement

/// Start BlarneyKey at login, so it survives a restart and is there when you wake the Mac.
///
/// `SMAppService.mainApp` is the modern route: macOS registers the app bundle itself, and
/// the user can see and revoke it in System Settings → General → Login Items. The older
/// approach needed a separate helper bundle inside the app.
///
/// Note there is no "launch on wake" to register: waking from sleep does not restart
/// anything, because the app was never quit. Registering at login is what actually covers
/// the gap, since a restart is the only thing that stops it.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is refusing because the user switched it off by hand. Worth
    /// distinguishing: no amount of retrying from here will change it.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns what actually happened rather than what was asked for, so the interface
    /// can show the truth instead of an optimistic toggle.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("BlarneyKey: could not \(enabled ? "enable" : "disable") launch at login — \(error.localizedDescription)")
        }
        return isEnabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "BlarneyKey starts when you log in."
        case .requiresApproval:
            return "Turned off in System Settings → General → Login Items. Switch it on there."
        case .notFound:
            return "macOS cannot find the app bundle to register. Rebuild and try again."
        case .notRegistered:
            return "BlarneyKey does not start on its own. Waking the Mac does not stop it; only a restart does."
        @unknown default:
            return "Unknown status."
        }
    }
}
