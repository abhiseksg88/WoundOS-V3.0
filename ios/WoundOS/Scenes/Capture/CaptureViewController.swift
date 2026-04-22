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

    #if !targetEnvironment(simulator)
    private lazy var arView: ARSCNView = {
        let view = ARSCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.automaticallyUpdatesLighting = true
        return view
    }()
    #endif

    private lazy var cameraView: UIView = {
        #if targetEnvironment(simulator)
        let placeholder = UIView()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.backgroundColor = UIColor(white: 0.12, alpha: 1)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "ARKit requires a physical device\nwith LiDAR (iPhone 12 Pro+)"
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        placeholder.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: placeholder.leadingAnchor, constant: 32),
        ])
        return placeholder
        #else
        return arView
        #endif
    }()

    private lazy var guidanceCard: UIVisualEffectView = {
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

    // MARK: - Wound Framing Guide

    /// Translucent reticle overlay to guide wound framing.
    private lazy var framingGuideView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false

        // Dashed circle reticle
        let reticle = UIView()
        reticle.translatesAutoresizingMaskIntoConstraints = false
        reticle.backgroundColor = .clear
        reticle.layer.cornerRadius = 80
        reticle.layer.borderWidth = 1.5
        reticle.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor

        // Crosshair lines
        let hLine = UIView()
        hLine.translatesAutoresizingMaskIntoConstraints = false
        hLine.backgroundColor = UIColor.white.withAlphaComponent(0.2)

        let vLine = UIView()
        vLine.translatesAutoresizingMaskIntoConstraints = false
        vLine.backgroundColor = UIColor.white.withAlphaComponent(0.2)

        // Label
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Center wound in frame"
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        label.textAlignment = .center

        container.addSubview(reticle)
        container.addSubview(hLine)
        container.addSubview(vLine)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            reticle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -30),
            reticle.widthAnchor.constraint(equalToConstant: 160),
            reticle.heightAnchor.constraint(equalToConstant: 160),

            hLine.centerYAnchor.constraint(equalTo: reticle.centerYAnchor),
            hLine.leadingAnchor.constraint(equalTo: reticle.leadingAnchor, constant: 10),
            hLine.trailingAnchor.constraint(equalTo: reticle.trailingAnchor, constant: -10),
            hLine.heightAnchor.constraint(equalToConstant: 0.5),

            vLine.centerXAnchor.constraint(equalTo: reticle.centerXAnchor),
            vLine.topAnchor.constraint(equalTo: reticle.topAnchor, constant: 10),
            vLine.bottomAnchor.constraint(equalTo: reticle.bottomAnchor, constant: -10),
            vLine.widthAnchor.constraint(equalToConstant: 0.5),

            label.topAnchor.constraint(equalTo: reticle.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        return container
    }()

    // MARK: - Distance Indicator Bar

    /// Visual bar showing the 15–30 cm optimal range with live reading.
    private lazy var distanceBar: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        return container
    }()

    private lazy var distanceTrack: UIView = {
        let track = UIView()
        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        track.layer.cornerRadius = 3
        return track
    }()

    private lazy var distanceFill: UIView = {
        let fill = UIView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = WOColors.primaryGreen
        fill.layer.cornerRadius = 3
        return fill
    }()

    private lazy var distanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private var distanceFillWidthConstraint: NSLayoutConstraint?

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
        view.accessibilityIdentifier = "v4_capture_screen"
        setupUI()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startSession()
        #if !targetEnvironment(simulator)
        if let session = viewModel.arSession {
            arView.session = session
        }
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseSession()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(cameraView)
        view.addSubview(framingGuideView)
        view.addSubview(trackingOverlay)
        view.addSubview(guidanceCard)
        view.addSubview(distanceBar)
        view.addSubview(captureButton)
        view.addSubview(hintLabel)

        trackingOverlay.addSubview(trackingLabel)

        guidanceCard.contentView.addSubview(guidanceIcon)
        guidanceCard.contentView.addSubview(guidanceLabel)

        // Distance bar subviews
        distanceBar.addSubview(distanceTrack)
        distanceBar.addSubview(distanceFill)
        distanceBar.addSubview(distanceLabel)

        let fillWidth = distanceFill.widthAnchor.constraint(equalToConstant: 0)
        distanceFillWidthConstraint = fillWidth

        NSLayoutConstraint.activate([
            // AR view — full screen
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Framing guide — centered in camera view
            framingGuideView.topAnchor.constraint(equalTo: view.topAnchor),
            framingGuideView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            framingGuideView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            framingGuideView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

            // Distance bar — above capture button
            distanceBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            distanceBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            distanceBar.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            distanceBar.heightAnchor.constraint(equalToConstant: 28),

            distanceTrack.leadingAnchor.constraint(equalTo: distanceBar.leadingAnchor),
            distanceTrack.trailingAnchor.constraint(equalTo: distanceBar.trailingAnchor),
            distanceTrack.centerYAnchor.constraint(equalTo: distanceBar.centerYAnchor),
            distanceTrack.heightAnchor.constraint(equalToConstant: 6),

            distanceFill.leadingAnchor.constraint(equalTo: distanceTrack.leadingAnchor),
            distanceFill.centerYAnchor.constraint(equalTo: distanceTrack.centerYAnchor),
            distanceFill.heightAnchor.constraint(equalToConstant: 6),
            fillWidth,

            distanceLabel.centerXAnchor.constraint(equalTo: distanceBar.centerXAnchor),
            distanceLabel.bottomAnchor.constraint(equalTo: distanceTrack.topAnchor, constant: -2),

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
        // Strict gating drives the capture button + guidance card together.
        viewModel.$readiness
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readiness in
                guard let self else { return }
                let isReady = readiness.isReady
                self.captureButton.isEnabled = isReady
                self.captureButton.alpha = isReady ? 1.0 : 0.35

                self.guidanceLabel.text = self.viewModel.guidanceText
                self.guidanceIcon.image = UIImage(systemName: self.viewModel.guidanceIconName)
                self.guidanceIcon.tintColor = isReady
                    ? WOColors.primaryGreen
                    : WOColors.warningOrange

                // Update distance bar
                self.updateDistanceBar()

                // Hide framing guide when tracking overlay is showing
                self.framingGuideView.alpha = (self.trackingOverlay.isHidden) ? 1 : 0
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

    // MARK: - Distance Bar

    private func updateDistanceBar() {
        guard let distance = viewModel.currentDistanceM else {
            distanceLabel.text = "-- cm"
            distanceFill.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            distanceFillWidthConstraint?.constant = 0
            return
        }

        let cm = distance * 100
        distanceLabel.text = String(format: "%.0f cm", cm)

        // Optimal range: 15–30 cm. Map 5–50 cm to full bar width.
        let trackWidth = distanceTrack.bounds.width
        guard trackWidth > 0 else { return }

        let minCm: Float = 5
        let maxCm: Float = 50
        let fraction = CGFloat((cm - minCm) / (maxCm - minCm))
        let clampedFraction = max(0, min(1, fraction))
        distanceFillWidthConstraint?.constant = trackWidth * clampedFraction

        // Color: green if in range, orange otherwise
        let inRange = (15...30).contains(Int(cm))
        let color = inRange ? WOColors.primaryGreen : WOColors.warningOrange
        distanceFill.backgroundColor = color
        distanceLabel.textColor = inRange ? .white : WOColors.warningOrange
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

