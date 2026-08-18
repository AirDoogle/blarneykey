import SwiftUI

/// A glanceable trend line for a `StatCard` — no axes, gridlines or tooltips,
/// just the shape of the last few buckets. Flat/empty data draws a flat line
/// rather than nothing, so a quiet week doesn't look like a broken chart.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.Colour.primary

    var body: some View {
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
        }
        .frame(height: 32)
    }
}
