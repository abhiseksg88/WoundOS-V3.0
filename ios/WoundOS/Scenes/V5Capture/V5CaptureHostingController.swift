import UIKit
import SwiftUI
import ARKit

// MARK: - V5 Capture Hosting Controller

/// UIHostingController bridge for the V5 SwiftUI capture view.
/// Manages AR session lifecycle in viewWillAppear/viewWillDisappear.
/// Checks LiDAR availability before showing the AR view.
final class V5CaptureHostingController: UIHostingController<V5CaptureView> {

    private let viewModel: V5CaptureViewModel
    private var hasCheckedLiDAR = false

    init(viewModel: V5CaptureViewModel) {
        self.viewModel = viewModel
        let view = V5CaptureView(viewModel: viewModel)
        super.init(rootView: view)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasCheckedLiDAR else { return }
        hasCheckedLiDAR = true

        #if !targetEnvironment(simulator)
        if !ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            showLiDARUnavailableAlert()
            return
        }
        #else
        // On simulator, show warning but allow UI inspection
        showLiDARUnavailableAlert()
        return
        #endif

        viewModel.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseSession()
    }

    override var prefersStatusBarHidden: Bool { true }

    private func showLiDARUnavailableAlert() {
        let alert = UIAlertController(
            title: "LiDAR Not Available",
            message: "V5 capture requires iPhone Pro or iPad Pro with LiDAR sensor. This device does not support scene depth.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Go Back", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}
