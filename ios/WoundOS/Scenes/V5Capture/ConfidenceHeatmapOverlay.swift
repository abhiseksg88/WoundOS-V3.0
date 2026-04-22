import SwiftUI
import WoundCapture

// MARK: - Confidence Heatmap Overlay

/// Renders a low-resolution grid of colored rectangles over the AR view.
/// Green = high confidence, yellow = medium, red = low.
struct ConfidenceHeatmapOverlay: View {
    let summary: ConfidenceMapSummary

    var body: some View {
        if let grid = summary.downsampledGrid, !grid.isEmpty {
            // Render per-cell heatmap
            Canvas { context, size in
                let rows = grid.count
                guard rows > 0 else { return }
                let cols = grid[0].count
                guard cols > 0 else { return }
                let cellWidth = size.width / CGFloat(cols)
                let cellHeight = size.height / CGFloat(rows)

                for row in 0..<rows {
                    for col in 0..<grid[row].count {
                        let confidence = grid[row][col]
                        let color: Color
                        switch confidence {
                        case 2: color = .green
                        case 1: color = .yellow
                        default: color = .red
                        }

                        let rect = CGRect(
                            x: CGFloat(col) * cellWidth,
                            y: CGFloat(row) * cellHeight,
                            width: cellWidth,
                            height: cellHeight
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        } else {
            // Fallback: show a single color based on overall score
            Rectangle()
                .fill(overallColor.opacity(0.15))
        }
    }

    private var overallColor: Color {
        let score = summary.overallScore
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .yellow }
        return .red
    }
}
