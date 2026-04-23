import SwiftUI

// MARK: - Capture Quality Indicator View

/// 40×40pt corner indicator showing capture readiness state.
/// Gray = initializing, Amber = adjust needed, Green = ready.
/// Tapping shows a tooltip card with the specific reason.
struct CaptureQualityIndicatorView: View {
    let quality: CaptureQualityLevel
    let tooltipText: String
    @Binding var showTooltip: Bool

    private var iconName: String {
        switch quality {
        case .gray:  return "circle.dotted"
        case .amber: return "exclamationmark.circle.fill"
        case .green: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch quality {
        case .gray:  return .white.opacity(0.6)
        case .amber: return .orange
        case .green: return .green
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                showTooltip.toggle()
            } label: {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Capture quality")
            .accessibilityValue(accessibilityValue)
            .animation(.easeInOut(duration: 0.3), value: quality)

            // Tooltip card
            if showTooltip {
                Text(tooltipText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showTooltip = false }
                        }
                    }
            }
        }
    }

    private var accessibilityValue: String {
        switch quality {
        case .gray:  return "Initializing"
        case .amber: return "Adjustment needed"
        case .green: return "Ready"
        }
    }
}
