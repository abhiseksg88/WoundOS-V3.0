import UIKit
import Combine
import WoundCore
import WoundBoundary
import WoundAutoSegmentation

// MARK: - Boundary Drawing View Controller

/// Displays the frozen captured image with drawing canvas overlay.
/// Clean, medical-grade UI for wound boundary annotation.
final class BoundaryDrawingViewController: UIViewController {

    private let viewModel: BoundaryDrawingViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        iv.clipsToBounds = true
        return iv
    }()

    private lazy var canvasView: BoundaryCanvasView = {
        let canvas = BoundaryCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.delegate = self
        return canvas
    }()

    private lazy var instructionCard: UIVisualEffectView = {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        return card
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()

    private lazy var modeToggle: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Auto Detect", "Draw Manually"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    /// Status label shown inside `processingOverlay`. Text is swapped between
    /// "Detecting wound boundary…" (auto-segmentation) and "Computing measurements…"
    /// (mesh pipeline) depending on which operation is in flight.
    private lazy var processingLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.subheadline
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Pulsing ring shown at tap point during auto-segmentation.
    private lazy var pulsingRingView: UIView = {
        let ring = UIView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.isHidden = true
        ring.isUserInteractionEnabled = false
        ring.layer.borderColor = WOColors.primaryGreen.cgColor
        ring.layer.borderWidth = 3
        ring.layer.cornerRadius = 30
        ring.frame.size = CGSize(width: 60, height: 60)
        return ring
    }()

    private lazy var bottomBar: UIVisualEffectView = {
        let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var undoButton: UIButton = {
        makeBarButton(icon: "arrow.uturn.backward", title: "Undo", action: #selector(undoTapped))
    }()

    private lazy var clearButton: UIButton = {
        makeBarButton(icon: "trash", title: "Clear", action: #selector(clearTapped))
    }()

    private lazy var measureButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Measure"
        config.image = UIImage(systemName: "checkmark.circle.fill")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = WOColors.primaryGreen
        config.baseForegroundColor = .white
        config.preferredSymbolConfigurationForImage = .init(pointSize: 14, weight: .semibold)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        return button
    }()

    /// Yellow banner for non-blocking validation warnings (Bug 7).
    private lazy var warningBanner: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = WOFonts.footnote
        label.textColor = .black
        label.textAlignment = .center
        label.backgroundColor = WOColors.warningOrange.withAlphaComponent(0.9)
        label.numberOfLines = 0
        label.isHidden = true
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        return label
    }()

    /// Red banner for real errors — segmentation / measurement failures (Bug 6).
    private lazy var errorBanner: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = WOFonts.footnote
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = WOColors.flagRed.withAlphaComponent(0.9)
        label.numberOfLines = 0
        label.isHidden = true
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.isUserInteractionEnabled = true
        return label
    }()

    private var errorDismissTimer: Timer?

    private lazy var woundTypeControl: UISegmentedControl = {
        let items = WoundType.allCases.map { type -> String in
            switch type {
            case .footUlcer: return "Foot"
            case .pressureInjury: return "Pressure"
            case .surgicalWound: return "Surgical"
            case .venousLegUlcer: return "Venous"
            case .unknown: return "Unknown"
            }
        }
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = WoundType.allCases.firstIndex(of: WoundTypeOverride.current) ?? (WoundType.allCases.count - 1)
        control.addTarget(self, action: #selector(woundTypeChanged), for: .valueChanged)
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        control.setTitleTextAttributes([.font: font], for: .normal)
        control.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        return control
    }()

    /// Cached geometry recomputed every layout pass (Bug 4).
    private var currentGeometry = ImageViewGeometry(sensorSize: .zero, displayedSize: .zero, viewSize: .zero)

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    private lazy var processingOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.isHidden = true

        view.addSubview(activityIndicator)
        view.addSubview(processingLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            processingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: WOSpacing.md),
            processingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        return view
    }()

    // MARK: - Init

    init(viewModel: BoundaryDrawingViewModel) {
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
        imageView.image = viewModel.capturedImage

        // If the environment has no segmenter (pre-iOS-17 or DI returned nil),
        // disable + hide the "Auto" segment and fall back to Polygon default.
        if !viewModel.autoSegmenterAvailable {
            modeToggle.setEnabled(false, forSegmentAt: 0)
            modeToggle.selectedSegmentIndex = 1
            viewModel.drawingMode = .freeform
        } else {
            modeToggle.selectedSegmentIndex = 0
        }

        // Dismiss error banner on tap
        errorBanner.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismissErrorBanner))
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Recompute geometry every layout pass so coordinate conversion
        // always uses the current view/image relationship (Bug 4).
        //
        // sensorSize = raw landscape buffer dimensions (for BoundaryProjector).
        // displayedSize = UIImage.size with .right orientation (portrait).
        let sensorSize = CGSize(
            width: viewModel.snapshot.imageWidth,
            height: viewModel.snapshot.imageHeight
        )
        let displayedSize = viewModel.capturedImage?.size ?? sensorSize
        currentGeometry = ImageViewGeometry(
            sensorSize: sensorSize,
            displayedSize: displayedSize,
            viewSize: canvasView.bounds.size
        )
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(imageView)
        view.addSubview(canvasView)
        view.addSubview(pulsingRingView)
        view.addSubview(instructionCard)
        view.addSubview(bottomBar)
        view.addSubview(warningBanner)
        view.addSubview(errorBanner)
        view.addSubview(processingOverlay)

        if DeveloperMode.isEnabled {
            view.addSubview(woundTypeControl)
        }

        instructionCard.contentView.addSubview(instructionLabel)

        // Bottom bar content
        let barStack = UIStackView(arrangedSubviews: [undoButton, clearButton, modeToggle, measureButton])
        barStack.axis = .horizontal
        barStack.distribution = .fill
        barStack.spacing = WOSpacing.md
        barStack.alignment = .center
        barStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(barStack)

        NSLayoutConstraint.activate([
            // Image — fills above bottom bar
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            // Canvas — matches image
            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            // Instruction card — top center on image
            instructionCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WOSpacing.sm),
            instructionCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionCard.heightAnchor.constraint(equalToConstant: 34),

            instructionLabel.leadingAnchor.constraint(equalTo: instructionCard.contentView.leadingAnchor, constant: WOSpacing.lg),
            instructionLabel.trailingAnchor.constraint(equalTo: instructionCard.contentView.trailingAnchor, constant: -WOSpacing.lg),
            instructionLabel.centerYAnchor.constraint(equalTo: instructionCard.contentView.centerYAnchor),

        ])

        if DeveloperMode.isEnabled {
            NSLayoutConstraint.activate([
                woundTypeControl.topAnchor.constraint(equalTo: instructionCard.bottomAnchor, constant: WOSpacing.sm),
                woundTypeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                woundTypeControl.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -WOSpacing.lg * 2),
            ])
        }

        NSLayoutConstraint.activate([
            // Warning banner (yellow, non-blocking validation)
            warningBanner.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -WOSpacing.sm),
            warningBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            warningBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),

            // Error banner (red, real errors)
            errorBanner.bottomAnchor.constraint(equalTo: warningBanner.topAnchor, constant: -WOSpacing.xs),
            errorBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            errorBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),

            // Bottom bar
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            barStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: WOSpacing.md),
            barStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: WOSpacing.lg),
            barStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -WOSpacing.lg),
            barStack.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),

            measureButton.heightAnchor.constraint(equalToConstant: 36),

            // Processing overlay
            processingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            processingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeBarButton(icon: String, title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.preferredSymbolConfigurationForImage = .init(pointSize: 15, weight: .medium)
        config.baseForegroundColor = .label
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$drawingMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.canvasView.drawingMode = mode
                self?.instructionLabel.text = self?.viewModel.instructionText
            }
            .store(in: &cancellables)

        // Validation warnings → yellow banner (non-blocking, Bug 7)
        viewModel.$validationErrors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errors in
                if errors.isEmpty {
                    self?.warningBanner.isHidden = true
                } else {
                    self?.warningBanner.isHidden = false
                    self?.warningBanner.text = "  " + errors.map(\.localizedDescription).joined(separator: ". ") + "  "
                }
            }
            .store(in: &cancellables)

        // Real errors → red banner with auto-dismiss + haptic (Bug 6)
        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                guard let self else { return }
                self.errorDismissTimer?.invalidate()
                if let message = errorMessage, !message.isEmpty {
                    self.errorBanner.isHidden = false
                    self.errorBanner.text = "  \(message)  "
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.errorDismissTimer = Timer.scheduledTimer(
                        withTimeInterval: 6.0, repeats: false
                    ) { [weak self] _ in
                        self?.dismissErrorBanner()
                    }
                } else {
                    self.errorBanner.isHidden = true
                }
            }
            .store(in: &cancellables)

        viewModel.$isComputing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] computing in
                guard let self else { return }
                if computing {
                    self.processingLabel.text = "Computing measurements…"
                    self.processingOverlay.isHidden = false
                    self.activityIndicator.startAnimating()
                    self.canvasView.isUserInteractionEnabled = false
                } else if !self.viewModel.isAutoSegmenting {
                    self.processingOverlay.isHidden = true
                    self.activityIndicator.stopAnimating()
                    self.canvasView.isUserInteractionEnabled = true
                }
            }
            .store(in: &cancellables)

        viewModel.$boundaryFinalized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] finalized in
                self?.measureButton.isEnabled = finalized
                self?.measureButton.alpha = finalized ? 1.0 : 0.5
            }
            .store(in: &cancellables)

        viewModel.$isAutoSegmenting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                if running {
                    self.processingLabel.text = "Detecting wound boundary…"
                    self.processingOverlay.isHidden = false
                    self.activityIndicator.startAnimating()
                    self.canvasView.isUserInteractionEnabled = false
                    self.showPulsingRing()
                } else if !self.viewModel.isComputing {
                    self.processingOverlay.isHidden = true
                    self.activityIndicator.stopAnimating()
                    self.canvasView.isUserInteractionEnabled = true
                    self.hidePulsingRing()
                }
            }
            .store(in: &cancellables)

        // Quality gate rejection → red instruction text with specific message.
        // Draw Manually remains prominent as the fallback.
        viewModel.$lastQualityResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self, let result else { return }
                if case .reject(let reason, _) = result {
                    let msg = MaskQualityGate.userMessage(for: reason)
                    self.instructionLabel.text = msg
                    self.instructionLabel.textColor = WOColors.flagRed
                    // Disable Measure since boundary is rejected
                    self.measureButton.isEnabled = false
                    self.measureButton.alpha = 0.5
                }
            }
            .store(in: &cancellables)

        viewModel.autoSegmentationResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] polygon in
                guard let self else { return }
                // Reset instruction color (may have been red from prior rejection)
                self.instructionLabel.textColor = .white

                // 1. Show the detected boundary on the canvas WITHOUT triggering
                //    the delegate → didFinalizeBoundary → O(n²) validate chain.
                //    autoFinalizeBoundary handles finalization with relaxed validation.
                self.canvasView.setBoundary(points: polygon, notifyDelegate: false)
                // Switch to manual edit mode so nurse can adjust the detected boundary
                self.modeToggle.selectedSegmentIndex = 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                // Show which model was used (helpful for debugging/user awareness)
                if let modelId = self.viewModel.lastSegmenterModelId {
                    let isServer = modelId.contains("sam2") || modelId.contains("server")
                    self.instructionLabel.text = isServer
                        ? "Boundary detected (AI) — adjust if needed"
                        : "Boundary detected (on-device) — adjust if needed"
                }

                // 2. Auto-finalize with relaxed validation (machine-generated contour)
                self.viewModel.autoFinalizeBoundary(polygon, in: self.currentGeometry)

                // 3. Brief pause so the nurse sees the detection, then auto-measure
                guard self.viewModel.boundaryFinalized else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    guard let self, self.viewModel.boundaryFinalized else { return }
                    self.viewModel.computeMeasurementsWithDefaults()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        let mode: DrawingMode
        switch modeToggle.selectedSegmentIndex {
        case 0: mode = .auto
        case 1: mode = .freeform
        default: return
        }
        // Set mode on both VM and canvas SYNCHRONOUSLY to eliminate the
        // race between the Combine binding (async) and the next touch event.
        viewModel.drawingMode = mode
        canvasView.drawingMode = mode
        // Switching modes should clear any in-progress sketch so the nurse
        // doesn't end up with a half-freeform, half-polygon boundary.
        // Use clearBoundaryKeepingMode so the mode set above is not
        // overridden back to .tapPoint (Bug 1 fix).
        canvasView.clearAll()
        viewModel.clearBoundaryKeepingMode()
    }

    @objc private func undoTapped() {
        canvasView.undoLastVertex()
    }

    @objc private func clearTapped() {
        canvasView.clearAll()
        viewModel.clearBoundary()
    }

    @objc private func dismissErrorBanner() {
        errorDismissTimer?.invalidate()
        errorBanner.isHidden = true
        viewModel.error = nil
    }

    @objc private func woundTypeChanged() {
        let index = woundTypeControl.selectedSegmentIndex
        let allCases = Array(WoundType.allCases)
        guard index >= 0, index < allCases.count else { return }
        WoundTypeOverride.current = allCases[index]
        CrashLogger.shared.log("Wound type override: \(allCases[index].rawValue)", category: .segmentation)
    }

    @objc private func confirmTapped() {
        guard viewModel.boundaryFinalized else { return }
        showPUSHInputSheet()
    }

    // MARK: - Pulsing Ring Animation

    private func showPulsingRing() {
        guard let tapPoint = viewModel.tapPoint else { return }
        pulsingRingView.center = tapPoint
        pulsingRingView.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        pulsingRingView.layer.cornerRadius = 30
        pulsingRingView.alpha = 1
        pulsingRingView.isHidden = false
        pulsingRingView.transform = .identity

        UIView.animate(
            withDuration: 1.0,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut]
        ) {
            self.pulsingRingView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            self.pulsingRingView.alpha = 0.3
        }
    }

    private func hidePulsingRing() {
        pulsingRingView.layer.removeAllAnimations()
        pulsingRingView.isHidden = true
        pulsingRingView.transform = .identity
        pulsingRingView.alpha = 1
    }

    // MARK: - PUSH Input Sheet

    private func showPUSHInputSheet() {
        let alert = UIAlertController(
            title: "Clinical Assessment",
            message: "Enter wound assessment for PUSH scoring",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Enter Assessment", style: .default) { [weak self] _ in
            self?.viewModel.computeMeasurements(
                patientId: "patient-001",
                nurseId: "nurse-001",
                facilityId: "facility-001",
                exudateAmount: .moderate,
                tissueType: .granulation
            )
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - BoundaryCanvasDelegate

extension BoundaryDrawingViewController: BoundaryCanvasDelegate {

    func canvasDidPlaceTapPoint(_ point: CGPoint) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.didPlaceTapPoint(point, in: currentGeometry)
    }

    func canvasDidUpdateBoundary(_ points: [CGPoint]) {
        viewModel.didUpdateBoundary(points, in: currentGeometry)
    }

    func canvasDidFinalizeBoundary(_ points: [CGPoint]) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.didFinalizeBoundary(points, in: currentGeometry)
    }

    func canvasDidClearBoundary() {
        viewModel.clearBoundary()
    }
}
