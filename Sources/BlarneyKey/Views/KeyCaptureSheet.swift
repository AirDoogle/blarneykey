import AppKit
import SwiftUI

/// "Press the key you want to use." Captures one keypress and offers it as the new
/// binding — nothing is saved until you confirm, so a mis-press costs nothing.
///
/// Keys that would make normal typing impossible are refused outright. Keys that merely
/// have another job are allowed with a warning, since only you know whether you use F5.
struct KeyCaptureSheet: View {
    let current: KeyBinding
    let onUse: (KeyBinding) -> Void
    let onCancel: () -> Void

    @State private var captured: KeyBinding?
    @State private var monitor: Any?

    private var risk: KeyNames.Risk? {
        captured.map { KeyNames.risk(for: $0.keyCode) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Record a key")
                    .font(Theme.Text.displayMd())
                    .tracking(Theme.Text.Track.display)
                    .foregroundStyle(Theme.Colour.ink)
                Text("Press the key you want to hold for dictation. Nothing changes until you confirm.")
                    .font(Theme.Text.body())
                    .foregroundStyle(Theme.Colour.inkMuted48)
                    .fixedSize(horizontal: false, vertical: true)
            }

            keyWell

            if let risk, let captured {
                message(for: risk, binding: captured).cardSurface()
            } else {
                Note(kind: .plain, text: "Currently using \(current.label).").cardSurface()
            }

            HStack(spacing: Theme.Space.xs) {
                Text("Escape closes this without changing anything.")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.inkMuted48)
                Spacer(minLength: Theme.Space.sm)
                Button("Cancel", action: cancel)
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button(risk == .risky ? "Use anyway" : "Use this key") {
                    if let captured { onUse(captured) }
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil || risk == .blocked)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 480)
        .background(Theme.Colour.parchment)
        .onAppear(perform: startCapturing)
        .onDisappear(perform: stopCapturing)
    }

    // MARK: - Pieces

    /// A dark tile: the one place in the app where the surface flips, because this is the
    /// moment the app is waiting on you rather than the other way round.
    private var keyWell: some View {
        VStack(spacing: 3) {
            if let captured {
                Text(captured.label)
                    .font(Theme.Text.heroDisplay())
                    .tracking(Theme.Text.Track.hero)
                    .foregroundStyle(Theme.Colour.onDark)
                Text(captured.isModifier
                     ? "modifier key · code \(captured.keyCode)"
                     : "key code \(captured.keyCode)")
                    .font(Theme.Text.caption())
                    .monospaced()
                    .foregroundStyle(Theme.Colour.onDarkFaint)
            } else {
                Text("Waiting")
                    .font(Theme.Text.displayLg())
                    .tracking(Theme.Text.Track.display)
                    .foregroundStyle(Theme.Colour.bodyMuted)
                Text("press any key")
                    .font(Theme.Text.caption())
                    .foregroundStyle(Theme.Colour.onDarkFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
        .background(Theme.Colour.tile1, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .strokeBorder(wellRing, lineWidth: captured == nil ? 1 : 2)
        )
    }

    private var wellRing: Color {
        switch risk {
        case .blocked: return Theme.Colour.stop
        case .risky: return Theme.Colour.warn
        case .safe: return Theme.Colour.ok
        case nil: return Theme.Colour.onDarkFaint.opacity(0.3)
        }
    }

    @ViewBuilder
    private func message(for risk: KeyNames.Risk, binding: KeyBinding) -> some View {
        switch risk {
        case .blocked:
            Note(kind: .stop,
                 text: "\(binding.label) is needed for normal typing, so it cannot be used. Press a different key.")
        case .risky:
            Note(kind: .warn,
                 text: "\(binding.label) already has a job. You can still use it, but the keypress reaches the focused app as well.")
        case .safe:
            Note(kind: .ok,
                 text: binding.isModifier
                    ? "\(binding.label) is a good choice — modifier keys do nothing on their own."
                    : "\(binding.label) looks unused. The keypress still reaches the focused app, which is usually harmless for a spare key.")
        }
    }

    // MARK: - Capture

    private func startCapturing() {
        // A local monitor is enough: the sheet has focus. Returning nil swallows the event,
        // so the keypress cannot leak into whatever is behind the sheet.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {   // Escape closes, and is never captured
                    cancel()
                    return nil
                }
                captured = KeyBinding(keyCode: event.keyCode, mask: 0, isModifier: false)
                return nil
            case .flagsChanged:
                // Only record the press, not the release.
                if let mask = Self.modifierMask(for: event.keyCode),
                   event.modifierFlags.rawValue & mask != 0 {
                    captured = KeyBinding(keyCode: event.keyCode, mask: mask, isModifier: true)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func stopCapturing() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func cancel() {
        stopCapturing()
        onCancel()
    }

    /// The device-dependent bit for a modifier key code, or nil if it is not a modifier.
    private static func modifierMask(for keyCode: UInt16) -> UInt? {
        HotKey.allCases.first { $0.isModifier && $0.keyCode == keyCode }?.mask
    }
}
