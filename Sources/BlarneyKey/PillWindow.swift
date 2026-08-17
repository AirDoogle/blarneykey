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
            contentRect: NSRect(x: 0, y: 0, width: 190, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: PillView(model: model, onStop: { controller.stop() })
        )

        // Bottom centre of whichever screen has the mouse.
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - 95,
                y: frame.minY + 90
            ))
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
        HStack(spacing: 10) {
            Image(systemName: model.locked ? "lock.fill" : "mic.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 2.5, height: height(at: index))
                }
            }
            .frame(height: 20)

            Text(String(format: "%d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.white.opacity(0.22), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.95))
        )
        .overlay(Capsule().stroke(.white.opacity(0.15)))
    }

    private func height(at index: Int) -> Double {
        // Taper towards the ends so the meter looks like a waveform, not a bar chart.
        let middle = Double(barCount - 1) / 2
        let distance = abs(Double(index) - middle) / middle
        let taper = 1 - distance * 0.65
        return max(3, 3 + model.level * 17 * taper)
    }
}
