import SwiftUI

// MARK: - Distance Ring View

/// Circular animated ring showing the current distance to the wound surface.
/// Green when in optimal range, orange when out of range.
struct DistanceRingView: View {
    let distanceM: Float?
    let optimalRange: ClosedRange<Float>
    var showNumericLabel: Bool = true

    private var fraction: CGFloat {
        guard let d = distanceM else { return 0 }
        // Map 5cm–50cm to 0–1
        return CGFloat((d - 0.05) / (0.50 - 0.05)).clamped(to: 0...1)
    }

    private var isInRange: Bool {
        guard let d = distanceM else { return false }
        return optimalRange.contains(d)
    }

    private var distanceText: String {
        guard let d = distanceM else { return "--" }
        return String(format: "%.0f", d * 100)
    }

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)
                .frame(width: 180, height: 180)

            // Fill ring
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isInRange ? Color.green : Color.orange,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: fraction)

            // Center distance label (dev mode only)
            if showNumericLabel {
                VStack(spacing: 2) {
                    Text(distanceText)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("cm")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
            }
        }
        .accessibilityIdentifier("distance_ring")
    }
}

// MARK: - CGFloat Clamping

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
