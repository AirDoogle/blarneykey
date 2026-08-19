import SwiftUI

/// A single point on a `Sparkline`, carrying enough to label a hover tooltip.
struct SparklinePoint {
    let label: String
    let value: Double
}

/// A trend line for a `StatCard`. No axes or gridlines — just the shape of the last
/// few buckets — but hovering reveals the exact value and date for that point, since
/// a glance is often not enough once you want to know "wait, which day was that?"
struct Sparkline: View {
    let points: [SparklinePoint]
    var color: Color = Theme.Colour.primary
    var valueFormat: (Double) -> String = { String(format: "%.0f", $0) }

    @State private var hoverIndex: Int?
    @State private var tooltipWidth: CGFloat = 84

    init(points: [SparklinePoint], color: Color = Theme.Colour.primary, valueFormat: @escaping (Double) -> String = { String(format: "%.0f", $0) }) {
        self.points = points
        self.color = color
        self.valueFormat = valueFormat
    }

    private var values: [Double] { points.map(\.value) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard values.count > 1 else { return }
                    let maxValue = values.max() ?? 0
                    let minValue = min(values.min() ?? 0, 0)
                    let range = maxValue - minValue

                    func point(_ index: Int) -> CGPoint {
                        let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let fraction = range > 0 ? (values[index] - minValue) / range : 0.5
                        let y = size.height * (1 - CGFloat(fraction))
                        return CGPoint(x: x, y: y)
                    }

                    var line = Path()
                    line.move(to: point(0))
                    for i in 1..<values.count { line.addLine(to: point(i)) }

                    var fill = line
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()

                    context.fill(
                        fill,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.16), color.opacity(0)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                    context.stroke(line, with: .color(color.opacity(0.8)), lineWidth: 1.5)

                    if let hoverIndex, values.indices.contains(hoverIndex) {
                        let p = point(hoverIndex)
                        context.stroke(
                            Path { $0.move(to: CGPoint(x: p.x, y: 0)); $0.addLine(to: CGPoint(x: p.x, y: size.height)) },
                            with: .color(color.opacity(0.25)),
                            lineWidth: 1
                        )
                        let dot = Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
                        context.fill(dot, with: .color(color))
                    }
                }

                if let hoverIndex, points.indices.contains(hoverIndex) {
                    tooltip(for: points[hoverIndex], at: hoverIndex, in: size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard values.count > 1 else { return }
                    let step = size.width / CGFloat(values.count - 1)
                    let index = Int((location.x / max(step, 1)).rounded())
                    hoverIndex = min(max(index, 0), values.count - 1)
                case .ended:
                    hoverIndex = nil
                }
            }
        }
        .frame(height: 32)
    }

    /// Keeps the bubble inside the card by clamping its offset to the measured
    /// width of its own content, so longer labels (e.g. "116 wpm · 1.8×") are never
    /// cut off instead of just centering on a guessed fixed width.
    private func tooltip(for point: SparklinePoint, at index: Int, in size: CGSize) -> some View {
        let fraction = values.count > 1 ? CGFloat(index) / CGFloat(values.count - 1) : 0.5
        let x = size.width * fraction
        let clampedX = min(max(x - tooltipWidth / 2, 0), max(size.width - tooltipWidth, 0))

        return VStack(alignment: .leading, spacing: 1) {
            Text(point.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Colour.inkMuted48)
            Text(valueFormat(point.value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Colour.ink)
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Colour.canvas)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Colour.hairline))
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TooltipWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TooltipWidthKey.self) { tooltipWidth = $0 }
        .fixedSize()
        .offset(x: clampedX, y: -38)
        .allowsHitTesting(false)
    }
}

private struct TooltipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 84
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A mini bar chart for a `StatCard`, the counterpart to `Sparkline`. Bars are for a metric
/// that is a *quantity accumulated within each period* — words dictated in a day, time saved
/// in a day — where every bucket is its own self-contained total. A line implies a continuous
/// signal sampled between points, which is right for a rate (speaking speed, average session
/// length) but misleading for a count that resets each period. Same chassis as the sparkline:
/// 32pt tall, one accent, no axes, hover for the exact figure.
struct MiniBars: View {
    let points: [SparklinePoint]
    var color: Color = Theme.Colour.primary
    var valueFormat: (Double) -> String = { String(format: "%.0f", $0) }

    @State private var hoverIndex: Int?
    @State private var tooltipWidth: CGFloat = 84

    init(points: [SparklinePoint], color: Color = Theme.Colour.primary, valueFormat: @escaping (Double) -> String = { String(format: "%.0f", $0) }) {
        self.points = points
        self.color = color
        self.valueFormat = valueFormat
    }

    private var values: [Double] { points.map(\.value) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let count = values.count
            let gap: CGFloat = count > 20 ? 1 : 2
            let slot = count > 0 ? size.width / CGFloat(count) : 0
            let barWidth = max(1, slot - gap)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let maxValue = values.max() ?? 0
                    guard count > 0, maxValue > 0 else { return }
                    for i in values.indices {
                        // Zero buckets draw nothing; a non-zero bucket keeps a 1pt sliver so
                        // it never disappears next to a tall neighbour.
                        guard values[i] > 0 else { continue }
                        let h = max(1, size.height * CGFloat(values[i] / maxValue))
                        let x = slot * CGFloat(i) + gap / 2
                        let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                        let dimmed = hoverIndex != nil && hoverIndex != i
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: min(1.5, barWidth / 2)),
                            with: .color(color.opacity(dimmed ? 0.28 : 0.8))
                        )
                    }
                }

                if let hoverIndex, points.indices.contains(hoverIndex) {
                    tooltip(for: points[hoverIndex], at: hoverIndex, slot: slot, in: size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard count > 0, slot > 0 else { return }
                    hoverIndex = min(max(Int(location.x / slot), 0), count - 1)
                case .ended:
                    hoverIndex = nil
                }
            }
        }
        .frame(height: 32)
    }

    private func tooltip(for point: SparklinePoint, at index: Int, slot: CGFloat, in size: CGSize) -> some View {
        let center = slot * (CGFloat(index) + 0.5)
        let clampedX = min(max(center - tooltipWidth / 2, 0), max(size.width - tooltipWidth, 0))

        return VStack(alignment: .leading, spacing: 1) {
            Text(point.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Colour.inkMuted48)
            Text(valueFormat(point.value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Colour.ink)
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.Colour.canvas)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Colour.hairline))
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TooltipWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TooltipWidthKey.self) { tooltipWidth = $0 }
        .offset(x: clampedX, y: -38)
        .allowsHitTesting(false)
    }
}
