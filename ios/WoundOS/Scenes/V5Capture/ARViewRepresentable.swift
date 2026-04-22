import SwiftUI
import ARKit

// MARK: - AR View Representable

/// UIViewRepresentable wrapper for ARSCNView.
/// Binds an existing ARSession to display the camera feed with scene reconstruction.
#if !targetEnvironment(simulator)
struct ARViewRepresentable: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.session = session
        arView.automaticallyUpdatesLighting = true
        arView.rendersContinuously = true
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Session binding is one-time in makeUIView
    }
}
#endif
