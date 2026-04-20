import UIKit
import Combine
import WoundCore
import WoundBoundary

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
        let control = UISegmentedControl(items: ["Auto", "Polygon", "Freeform"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    /// Status label shown inside `processingOverlay`. Text is swapped between
    /// "Detecting outline…" (auto-segmentation) and "Computing measurements…"
    /// (mesh pipeline) depending on which operation is in flight.
    private lazy var processingLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.subheadline
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        return label
    }()

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
            viewModel.drawingMode = .polygon
        } else {
            modeToggle.selectedSegmentIndex = 0
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(imageView)
        view.addSubview(canvasView)
        view.addSubview(instructionCard)
        view.addSubview(bottomBar)
        view.addSubview(errorBanner)
        view.addSubview(processingOverlay)

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

            // Error banner
            errorBanner.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -WOSpacing.sm),
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

        viewModel.$validationErrors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errors in
                if errors.isEmpty {
                    self?.errorBanner.isHidden = true
                } else {
                    self?.errorBanner.isHidden = false
                    self?.errorBanner.text = "  " + errors.map(\.localizedDescription).joined(separator: ". ") + "  "
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
                    self.processingLabel.text = "Detecting outline…"
                    self.processingOverlay.isHidden = false
                    self.activityIndicator.startAnimating()
                    self.canvasView.isUserInteractionEnabled = false
                } else if !self.viewModel.isComputing {
                    self.processingOverlay.isHidden = true
                    self.activityIndicator.stopAnimating()
                    self.canvasView.isUserInteractionEnabled = true
                }
            }
            .store(in: &cancellables)

        viewModel.autoSegmentationResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] polygon in
                guard let self else { return }
                self.canvasView.setBoundary(points: polygon)
                // Canvas is now in .polygon mode; reflect in segmented control
                // so the nurse understands they can edit vertices.
                self.modeToggle.selectedSegmentIndex = 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        switch modeToggle.selectedSegmentIndex {
        case 0: viewModel.drawingMode = .auto
        case 1: viewModel.drawingMode = .polygon
        case 2: viewModel.drawingMode = .freeform
        default: break
        }
        // Switching modes should clear any in-progress sketch so the nurse
        // doesn't end up with a half-freeform, half-polygon boundary.
        canvasView.clearAll()
        viewModel.clearBoundary()
    }

    @objc private func undoTapped() {
        canvasView.undoLastVertex()
    }

    @objc private func clearTapped() {
        canvasView.clearAll()
        viewModel.clearBoundary()
    }

    @objc private func confirmTapped() {
        guard viewModel.boundaryFinalized else { return }
        showPUSHInputSheet()
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
        viewModel.didPlaceTapPoint(point, in: canvasView.bounds.size)
    }

    func canvasDidUpdateBoundary(_ points: [CGPoint]) {
        viewModel.didUpdateBoundary(points, in: canvasView.bounds.size)
    }

    func canvasDidFinalizeBoundary(_ points: [CGPoint]) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.didFinalizeBoundary(points, in: canvasView.bounds.size)
    }

    func canvasDidClearBoundary() {
        viewModel.clearBoundary()
    }
}
