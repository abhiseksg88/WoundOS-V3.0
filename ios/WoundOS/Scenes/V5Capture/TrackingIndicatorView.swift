import SwiftUI
import WoundCore

// MARK: - Tracking Indicator View

/// Full-screen semi-transparent overlay shown when AR tracking is limited.
struct TrackingIndicatorView: View {
    let state: TrackingState

    private var message: String {
        switch state {
        case .notAvailable:
            return "AR Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Initializing AR — Hold device steady"
            case .excessiveMotion:
                return "Too Fast — Slow down"
            case .insufficientFeatures:
                return "More Light Needed — Improve lighting"
            case .relocalizing:
                return "Relocalizing…"
            }
        case .normal:
            return ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "arkit")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.8))

                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .accessibilityIdentifier("tracking_overlay")
    }
}
