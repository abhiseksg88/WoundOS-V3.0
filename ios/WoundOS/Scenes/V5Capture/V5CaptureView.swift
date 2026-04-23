import SwiftUI
import ARKit
import WoundCapture

// MARK: - V5 Capture View

/// Root SwiftUI view for the V5 guided capture experience.
/// Composes: AR camera feed, distance ring, tracking indicator,
/// confidence heatmap, capture button, and guidance card.
struct V5CaptureView: View {
    @ObservedObject var viewModel: V5CaptureViewModel

    var body: some View {
        ZStack {
            // AR camera feed (full screen)
            #if !targetEnvironment(simulator)
            ARViewRepresentable(session: viewModel.arSession)
                .ignoresSafeArea()
                .onLongPressGesture(minimumDuration: 0.5, pressing: { isPressing in
                    if isPressing {
                        viewModel.isHeatmapRevealed = true
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            viewModel.isHeatmapRevealed = false
                        }
                    }
                }, perform: {})
            #else
            Color.black
                .ignoresSafeArea()
                .overlay {
                    Text("ARKit requires a physical device")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.headline)
                }
            #endif

            // Confidence heatmap overlay (dev mode or hold-to-reveal)
            if let confidence = viewModel.confidenceSummary,
               (DeveloperMode.isEnabled || viewModel.isHeatmapRevealed) {
                ConfidenceHeatmapOverlay(summary: confidence)
                    .opacity(viewModel.isHeatmapRevealed ? 0.50 : 0.25)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.3), value: viewModel.isHeatmapRevealed)
            }

            // Tracking overlay (blocks when tracking is limited)
            if case .notAvailable = viewModel.trackingState {
                TrackingIndicatorView(state: viewModel.trackingState)
            } else if case .limited = viewModel.trackingState {
                TrackingIndicatorView(state: viewModel.trackingState)
            }

            // Guided capture UI
            VStack(spacing: 0) {
                // Top: Guidance card
                GuidanceCardView(
                    text: viewModel.guidanceText,
                    iconName: viewModel.guidanceIconName,
                    isReady: viewModel.isReadyToCapture
                )
                .padding(.top, 12)

                Spacer()

                // Center: Distance ring
                DistanceRingView(
                    distanceM: viewModel.currentDistanceM,
                    optimalRange: 0.20...0.35,
                    showNumericLabel: DeveloperMode.isEnabled
                )

                Spacer()

                // Bottom: Capture button + hint
                CaptureButtonView(
                    isReady: viewModel.isReadyToCapture,
                    action: viewModel.capture
                )
                .padding(.bottom, 8)

                if !viewModel.distanceHintText.isEmpty {
                    Text(viewModel.distanceHintText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.distanceHintText)
                }
                Spacer().frame(height: 16)
            }
            .padding(.horizontal)

            // Quality indicator (top-right)
            VStack {
                HStack {
                    Spacer()
                    CaptureQualityIndicatorView(
                        quality: viewModel.qualityLevel,
                        tooltipText: viewModel.qualityTooltipText,
                        showTooltip: $viewModel.showQualityTooltip
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }

            // Dump Bundle button (bottom-right) — dev only
            if DeveloperMode.isEnabled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("Dump Bundle") {
                            viewModel.dumpBundle()
                        }
                        .disabled(viewModel.lastCaptureBundle == nil)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .foregroundStyle(viewModel.lastCaptureBundle != nil ? .white : .gray)
                        .padding(.trailing, 16)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .accessibilityIdentifier("v5_capture_screen")
        .alert("Capture Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .overlay(alignment: .top) {
            if DeveloperMode.isEnabled, let toast = viewModel.dumpToastMessage {
                Text(toast)
                    .font(.caption)
                    .padding(8)
                    .background(.green.opacity(0.9))
                    .cornerRadius(8)
                    .foregroundStyle(.white)
                    .padding(.top, 60)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.dumpToastMessage = nil
                        }
                    }
            }
        }
    }
}
