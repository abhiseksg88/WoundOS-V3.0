import SwiftUI

// MARK: - Capture Button View

/// White shutter button with outer ring. Enabled when readiness passes.
/// Includes haptic feedback on tap.
struct CaptureButtonView: View {
    let isReady: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 74, height: 74)

                // Inner fill
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(!isReady)
        .opacity(isReady ? 1.0 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: isReady)
        .accessibilityIdentifier("capture_button")
        .accessibilityLabel("Capture wound")
    }
}
