import AppKit
import SwiftUI

/// The floating "pill" shown while dictating: live level, elapsed time, stop button.
///
/// A non-activating panel, so showing it never steals focus from the app you are
/// dictating into — which would defeat the purpose.
final class PillWindow {
    private var panel: NSPanel?
    private var timer: Timer?
    private let model = PillModel()

    func show(controller: DictationController) {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 196, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Chrome over content gets its lift from the dark surface, not from a shadow —
        // the system's one drop-shadow is reserved for product imagery.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: PillView(model: model, onStop: { controller.stop() })
        )

        // Bottom centre of whichever screen has the mouse.
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 98, y: frame.minY + 90))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        model.locked = controller.isLocked
        let started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            self?.model.level = controller.level
            self?.model.elapsed = Date().timeIntervalSince(started)
            self?.model.locked = controller.isLocked
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class PillModel: ObservableObject {
    @Published var level: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var locked = false
}

private struct PillView: View {
    @ObservedObject var model: PillModel
    let onStop: () -> Void

    /// Bars either side of centre, so the meter reads outwards from the middle.
    private let barCount = 13

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: model.locked ? "lock.fill" : "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colour.bodyMuted)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Theme.Colour.onDark)
                        .frame(width: 2.5, height: height(at: index))
                }
            }
            .frame(height: 20)

            Text(String(format: "%d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                .font(Theme.Text.caption())
                .monospacedDigit()
                .foregroundStyle(Theme.Colour.bodyMuted)

            // The one interactive element, so it carries the accent — Sky Link Blue,
            // because Action Blue disappears against a dark tile.
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Colour.onDark)
                    .padding(6)
                    .background(Circle().fill(Theme.Colour.primaryOnDark))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(Capsule().fill(Theme.Colour.tile1))
        .overlay(Capsule().strokeBorder(Theme.Colour.onDarkFaint.opacity(0.25), lineWidth: 1))
    }

    private func height(at index: Int) -> Double {
        // Taper towards the ends so the meter looks like a waveform, not a bar chart.
        let middle = Double(barCount - 1) / 2
        let distance = abs(Double(index) - middle) / middle
        let taper = 1 - distance * 0.65
        return max(3, 3 + model.level * 17 * taper)
    }
}
