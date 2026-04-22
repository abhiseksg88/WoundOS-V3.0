import SwiftUI

// MARK: - Guidance Card View

/// Material blur card with SF Symbol + guidance text.
/// Matches the Apple Health-inspired design from V4.
struct GuidanceCardView: View {
    let text: String
    let iconName: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isReady ? .green : .orange)

            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("guidance_card")
    }
}
