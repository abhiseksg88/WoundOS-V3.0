import UIKit
import ARKit
import Combine
import WoundCapture

// MARK: - Capture View Controller

/// Full-screen AR camera view with clean distance guidance and capture button.
/// Apple Health-inspired minimal capture UI.
final class CaptureViewController: UIViewController {

    private let viewModel: CaptureViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var arView: ARSCNView = {
        let view = ARSCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.automaticallyUpdatesLighting = true
        return view
    }()

    private lazy var guidanceCard: UIView = {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }()

    private lazy var guidanceIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = .init(pointSize: 18, weight: .medium)
        return iv
    }()

    private lazy var guidanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private lazy var trackingOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.isHidden = true
        return view
    }()

    private lazy var trackingLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = WOFonts.title3
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Outer ring
        let outerRing = UIView()
        outerRing.translatesAutoresizingMaskIntoConstraints = false
        outerRing.layer.cornerRadius = 37
        outerRing.layer.borderWidth = 4
        outerRing.layer.borderColor = UIColor.white.cgColor
        outerRing.isUserInteractionEnabled = false

        // Inner circle
        let innerCircle = UIView()
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 30
        innerCircle.isUserInteractionEnabled = false

        button.addSubview(outerRing)
        button.addSubview(innerCircle)

        NSLayoutConstraint.activate([
            outerRing.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            outerRing.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            outerRing.widthAnchor.constraint(equalToConstant: 74),
            outerRing.heightAnchor.constraint(equalToConstant: 74),
            innerCircle.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 60),
            innerCircle.heightAnchor.constraint(equalToConstant: 60),
        ])

        button.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        return button
    }()

    private lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Hold 15-30 cm from wound"
        label.font = WOFonts.caption1
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .center
        return label
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
        if let arManager = viewModel as? ARSessionManagerAccessor {
            arView.session = arManager.arSession
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseSession()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(arView)
        view.addSubview(trackingOverlay)
        view.addSubview(guidanceCard)
        view.addSubview(captureButton)
        view.addSubview(hintLabel)

        trackingOverlay.addSubview(trackingLabel)

        guidanceCard.contentView.addSubview(guidanceIcon)
        guidanceCard.contentView.addSubview(guidanceLabel)

        NSLayoutConstraint.activate([
            // AR view — full screen
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Tracking overlay
            trackingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            trackingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trackingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            trackingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            trackingLabel.centerXAnchor.constraint(equalTo: trackingOverlay.centerXAnchor),
            trackingLabel.centerYAnchor.constraint(equalTo: trackingOverlay.centerYAnchor),
            trackingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: trackingOverlay.leadingAnchor, constant: 40),

            // Guidance card — top center
            guidanceCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WOSpacing.md),
            guidanceCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guidanceCard.heightAnchor.constraint(equalToConstant: 40),

            guidanceIcon.leadingAnchor.constraint(equalTo: guidanceCard.contentView.leadingAnchor, constant: WOSpacing.md),
            guidanceIcon.centerYAnchor.constraint(equalTo: guidanceCard.contentView.centerYAnchor),
            guidanceIcon.widthAnchor.constraint(equalToConstant: 20),

            guidanceLabel.leadingAnchor.constraint(equalTo: guidanceIcon.trailingAnchor, constant: WOSpacing.sm),
            guidanceLabel.trailingAnchor.constraint(equalTo: guidanceCard.contentView.trailingAnchor, constant: -WOSpacing.lg),
            guidanceLabel.centerYAnchor.constraint(equalTo: guidanceCard.contentView.centerYAnchor),

            // Capture button — bottom center
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.xxl),
            captureButton.widthAnchor.constraint(equalToConstant: 80),
            captureButton.heightAnchor.constraint(equalToConstant: 80),

            // Hint label
            hintLabel.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: WOSpacing.sm),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
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
                self.guidanceLabel.text = self.viewModel.distanceGuidance

                if self.viewModel.isOptimalDistance {
                    self.guidanceIcon.image = UIImage(systemName: "checkmark.circle.fill")
                    self.guidanceIcon.tintColor = WOColors.primaryGreen
                } else {
                    self.guidanceIcon.image = UIImage(systemName: "ruler")
                    self.guidanceIcon.tintColor = WOColors.warningOrange
                }
            }
            .store(in: &cancellables)

        viewModel.$trackingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .normal:
                    self?.trackingOverlay.isHidden = true
                case .limited(let reason):
                    self?.trackingOverlay.isHidden = false
                    switch reason {
                    case .initializing:
                        self?.trackingLabel.text = "Initializing AR\nHold device steady"
                    case .excessiveMotion:
                        self?.trackingLabel.text = "Too Fast\nSlow down"
                    case .insufficientFeatures:
                        self?.trackingLabel.text = "More Light Needed\nImprove lighting"
                    case .relocalizing:
                        self?.trackingLabel.text = "Relocalizing..."
                    }
                case .notAvailable:
                    self?.trackingOverlay.isHidden = false
                    self?.trackingLabel.text = "AR Not Available"
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                let alert = UIAlertController(title: "Capture Error", message: errorMessage, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func captureTapped() {
        // Camera shutter animation
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)

        UIView.animate(withDuration: 0.08, animations: { flash.alpha = 0.6 }) { _ in
            UIView.animate(withDuration: 0.15, animations: { flash.alpha = 0 }) { _ in
                flash.removeFromSuperview()
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.capture()
    }
}

// MARK: - AR Session Accessor

protocol ARSessionManagerAccessor {
    var arSession: ARSession { get }
}
