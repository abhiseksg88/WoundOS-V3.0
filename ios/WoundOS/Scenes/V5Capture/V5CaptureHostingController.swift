import UIKit
import SwiftUI

// MARK: - V5 Capture Hosting Controller

/// UIHostingController bridge for the V5 SwiftUI capture view.
/// Manages AR session lifecycle in viewWillAppear/viewWillDisappear.
final class V5CaptureHostingController: UIHostingController<V5CaptureView> {

    private let viewModel: V5CaptureViewModel

    init(viewModel: V5CaptureViewModel) {
        self.viewModel = viewModel
        let view = V5CaptureView(viewModel: viewModel)
        super.init(rootView: view)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseSession()
    }

    override var prefersStatusBarHidden: Bool { true }
}
