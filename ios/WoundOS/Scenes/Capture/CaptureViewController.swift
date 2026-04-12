import UIKit
import ARKit
import Combine
import WoundCapture

// MARK: - Capture View Controller

/// Full-screen AR camera view with distance guidance overlay and capture button.
final class CaptureViewController: UIViewController {

    // MARK: - Properties

    private let viewModel: CaptureViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var arView: ARSCNView = {
        let view = ARSCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.automaticallyUpdatesLighting = true
        return view
    }()

    private lazy var distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        return label
    }()

    private lazy var trackingLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .systemYellow
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: "circle.inset.filled",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 72)),
            for: .normal
        )
        button.tintColor = .white
        button.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        return button
    }()

    private lazy var distanceIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 6
        return view
    }()

    // MARK: - Init

    init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startSession()

        // Connect AR session to the view
        if let arManager = viewModel as? ARSessionManagerAccessor {
            arView.session = arManager.arSession
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseSession()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(arView)
        view.addSubview(distanceLabel)
        view.addSubview(trackingLabel)
        view.addSubview(captureButton)
        view.addSubview(distanceIndicator)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            distanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            distanceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            distanceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            distanceLabel.heightAnchor.constraint(equalToConstant: 40),

            distanceIndicator.centerYAnchor.constraint(equalTo: distanceLabel.centerYAnchor),
            distanceIndicator.trailingAnchor.constraint(equalTo: distanceLabel.leadingAnchor, constant: -8),
            distanceIndicator.widthAnchor.constraint(equalToConstant: 12),
            distanceIndicator.heightAnchor.constraint(equalToConstant: 12),

            trackingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            trackingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            trackingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$isReadyToCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.captureButton.isEnabled = ready
                self?.captureButton.alpha = ready ? 1.0 : 0.4
            }
            .store(in: &cancellables)

        viewModel.$estimatedDistance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.distanceLabel.text = "  \(self.viewModel.distanceGuidance)  "
                self.distanceIndicator.backgroundColor = self.viewModel.isOptimalDistance
                    ? .systemGreen
                    : .systemOrange
            }
            .store(in: &cancellables)

        viewModel.$trackingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .normal:
                    self?.trackingLabel.isHidden = true
                case .limited(let reason):
                    self?.trackingLabel.isHidden = false
                    switch reason {
                    case .initializing:
                        self?.trackingLabel.text = "Initializing AR...\nHold device steady"
                    case .excessiveMotion:
                        self?.trackingLabel.text = "Slow down\nMoving too fast"
                    case .insufficientFeatures:
                        self?.trackingLabel.text = "Need better lighting\nor more visual features"
                    case .relocalizing:
                        self?.trackingLabel.text = "Relocalizing..."
                    }
                case .notAvailable:
                    self?.trackingLabel.isHidden = false
                    self?.trackingLabel.text = "AR not available"
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                let alert = UIAlertController(
                    title: "Capture Error",
                    message: errorMessage,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func captureTapped() {
        // Flash effect
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)

        UIView.animate(withDuration: 0.1, animations: {
            flash.alpha = 0.7
        }) { _ in
            UIView.animate(withDuration: 0.2, animations: {
                flash.alpha = 0
            }) { _ in
                flash.removeFromSuperview()
            }
        }

        viewModel.capture()
    }
}

// MARK: - AR Session Accessor

/// Protocol to access the underlying AR session from the view model.
protocol ARSessionManagerAccessor {
    var arSession: ARSession { get }
}
