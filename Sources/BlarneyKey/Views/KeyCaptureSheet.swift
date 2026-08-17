import AppKit
import SwiftUI

/// "Press the key you want to use." Captures one keypress and offers it as the new
/// binding — nothing is saved until you confirm, so a mis-press costs nothing.
///
/// Keys that would make normal typing impossible are refused outright. Keys that
/// merely have another job are allowed with a warning, since only you know whether
/// you use F5 or the extra key above the numpad.
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Record a key").font(.title3.weight(.semibold))
                Text("Press the key you want to hold for dictation. Nothing changes until you confirm.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            keyWell

            if let risk, let captured {
                message(for: risk, binding: captured)
            } else {
                Text("Currently: \(current.label)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Escape closes this without changing anything.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                Button(risk == .risky ? "Use anyway" : "Use this key") {
                    if let captured { onUse(captured) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(captured == nil || risk == .blocked)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: startCapturing)
        .onDisappear(perform: stopCapturing)
    }

    // MARK: - Pieces

    private var keyWell: some View {
        VStack(spacing: 4) {
            if let captured {
                Text(captured.label)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(captured.isModifier
                     ? "modifier key · code \(captured.keyCode)"
                     : "code \(captured.keyCode)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            } else {
                Text("Waiting…")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("press any key")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColour, lineWidth: captured == nil ? 1 : 2)
        )
    }

    private var borderColour: Color {
        switch risk {
        case .blocked: return .red
        case .risky: return .orange
        case .safe: return .green
        case nil: return .secondary.opacity(0.3)
        }
    }

    @ViewBuilder
    private func message(for risk: KeyNames.Risk, binding: KeyBinding) -> some View {
        switch risk {
        case .blocked:
            note(.red, "exclamationmark.octagon.fill",
                 "\(binding.label) is needed for normal typing, so it cannot be used. Press a different key.")
        case .risky:
            note(.orange, "exclamationmark.triangle.fill",
                 "\(binding.label) already has a job. You can still use it, but the keypress reaches the focused app as well.")
        case .safe:
            note(.green, "checkmark.circle.fill",
                 binding.isModifier
                    ? "\(binding.label) is a good choice — modifier keys do nothing on their own."
                    : "\(binding.label) looks unused. The keypress still reaches the focused app, which is usually harmless for a spare key.")
        }
    }

    private func note(_ colour: Color, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(colour.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Capture

    private func startCapturing() {
        // A local monitor is enough: the sheet has focus. Returning nil swallows the
        // event, so the keypress cannot leak into whatever is behind the sheet.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {   // Escape closes, never gets captured
                    cancel()
                    return nil
                }
                captured = KeyBinding(keyCode: event.keyCode, mask: 0, isModifier: false)
                return nil
            case .flagsChanged:
                // Only record the press, not the release.
                if let mask = Self.modifierMask(for: event.keyCode),
                   event.modifierFlags.rawValue & mask != 0 {
                    captured = KeyBinding(
                        keyCode: event.keyCode, mask: mask, isModifier: true
                    )
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
