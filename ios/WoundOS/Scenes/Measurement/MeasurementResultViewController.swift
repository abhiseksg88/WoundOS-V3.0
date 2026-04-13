import UIKit
import Combine
import simd
import WoundCore

// MARK: - Measurement Result View Controller

/// Displays wound measurement results in Apple Health design style.
/// Layout matches the clinical wound measurement screenshot:
/// - Wound image at top with green boundary overlay and L/W measurement lines
/// - "Scroll down to add wound depth" prompt
/// - Wound label badge
/// - Measurement cards (Area, Circumference, Length, Width)
/// - Depth card
/// - PUSH Score card
/// - Save button
final class MeasurementResultViewController: UIViewController {

    private let viewModel: MeasurementResultViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        return stack
    }()

    private lazy var woundImageOverlay: WoundImageOverlayView = {
        let view = WoundImageOverlayView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var depthPrompt: WODepthPromptView = {
        let view = WODepthPromptView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var saveButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Save & Upload"
        config.image = UIImage(systemName: "arrow.up.circle.fill")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = WOColors.primaryGreen
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Init

    init(viewModel: MeasurementResultViewModel) {
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
        configureContent()
        bindViewModel()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(scrollView)
        view.addSubview(saveButton)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -WOSpacing.md),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - Content

    private func configureContent() {

        // === Wound Image with Overlay ===
        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(woundImageOverlay)
        imageContainer.addSubview(depthPrompt)

        NSLayoutConstraint.activate([
            woundImageOverlay.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            woundImageOverlay.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            woundImageOverlay.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            woundImageOverlay.heightAnchor.constraint(equalTo: woundImageOverlay.widthAnchor, multiplier: 0.85),

            depthPrompt.bottomAnchor.constraint(equalTo: woundImageOverlay.bottomAnchor, constant: -WOSpacing.md),
            depthPrompt.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),

            imageContainer.bottomAnchor.constraint(equalTo: depthPrompt.bottomAnchor, constant: WOSpacing.md),
        ])

        // Configure the wound overlay
        woundImageOverlay.configure(with: WoundImageOverlayView.Configuration(
            boundaryPoints: viewModel.boundaryPointsCG,
            lengthEndpoints: makeLengthEndpoints(),
            widthEndpoints: makeWidthEndpoints(),
            lengthText: viewModel.lengthValue + " " + viewModel.lengthUnit,
            widthText: viewModel.widthValue + " " + viewModel.widthUnit,
            image: viewModel.woundImage
        ))

        contentStack.addArrangedSubview(imageContainer)
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.lg))

        // === Wound Label Badge ===
        let woundBadge = WOWoundBadge(label: "Wound W1")
        contentStack.addArrangedSubview(woundBadge)

        // === Primary Measurements Card ===
        let measurementCard = WOCardView()
        measurementCard.translatesAutoresizingMaskIntoConstraints = false

        let measurementStack = UIStackView()
        measurementStack.axis = .vertical
        measurementStack.translatesAutoresizingMaskIntoConstraints = false
        measurementCard.addSubview(measurementStack)

        NSLayoutConstraint.activate([
            measurementStack.topAnchor.constraint(equalTo: measurementCard.topAnchor),
            measurementStack.leadingAnchor.constraint(equalTo: measurementCard.leadingAnchor),
            measurementStack.trailingAnchor.constraint(equalTo: measurementCard.trailingAnchor),
            measurementStack.bottomAnchor.constraint(equalTo: measurementCard.bottomAnchor),
        ])

        measurementStack.addArrangedSubview(
            WOMeasurementRow(label: "Area", value: viewModel.areaValue, unit: viewModel.areaUnit))
        measurementStack.addArrangedSubview(
            WOMeasurementRow(label: "Circumference", value: viewModel.perimeterValue, unit: viewModel.perimeterUnit))
        measurementStack.addArrangedSubview(
            WOMeasurementRow(label: "Length", value: viewModel.lengthValue, unit: viewModel.lengthUnit))
        measurementStack.addArrangedSubview(
            WOMeasurementRow(label: "Width", value: viewModel.widthValue, unit: viewModel.widthUnit, showSeparator: false))

        let cardWrapper = wrapInPadding(measurementCard, horizontal: WOSpacing.lg)
        contentStack.addArrangedSubview(cardWrapper)
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === Depth Section ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "Depth"))

        let depthCard = WOCardView()
        depthCard.translatesAutoresizingMaskIntoConstraints = false

        let depthStack = UIStackView()
        depthStack.axis = .vertical
        depthStack.translatesAutoresizingMaskIntoConstraints = false
        depthCard.addSubview(depthStack)

        NSLayoutConstraint.activate([
            depthStack.topAnchor.constraint(equalTo: depthCard.topAnchor),
            depthStack.leadingAnchor.constraint(equalTo: depthCard.leadingAnchor),
            depthStack.trailingAnchor.constraint(equalTo: depthCard.trailingAnchor),
            depthStack.bottomAnchor.constraint(equalTo: depthCard.bottomAnchor),
        ])

        depthStack.addArrangedSubview(
            WOMeasurementRow(label: "Max Depth", value: viewModel.maxDepthValue, unit: viewModel.maxDepthUnit))
        depthStack.addArrangedSubview(
            WOMeasurementRow(label: "Mean Depth", value: viewModel.meanDepthValue, unit: viewModel.meanDepthUnit))
        depthStack.addArrangedSubview(
            WOMeasurementRow(label: "Volume", value: viewModel.volumeValue, unit: viewModel.volumeUnit, showSeparator: false))

        contentStack.addArrangedSubview(wrapInPadding(depthCard, horizontal: WOSpacing.lg))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === PUSH Score Section ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "PUSH Score 3.0"))

        let pushCard = WOPushScoreCard()
        pushCard.translatesAutoresizingMaskIntoConstraints = false
        pushCard.configure(
            score: viewModel.pushTotalScore,
            breakdown: viewModel.pushBreakdown
        )

        contentStack.addArrangedSubview(wrapInPadding(pushCard, horizontal: WOSpacing.lg))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === Clinical Assessment Card ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "Clinical Assessment"))

        let assessmentCard = WOCardView()
        assessmentCard.translatesAutoresizingMaskIntoConstraints = false

        let assessmentStack = UIStackView()
        assessmentStack.axis = .vertical
        assessmentStack.translatesAutoresizingMaskIntoConstraints = false
        assessmentCard.addSubview(assessmentStack)

        NSLayoutConstraint.activate([
            assessmentStack.topAnchor.constraint(equalTo: assessmentCard.topAnchor),
            assessmentStack.leadingAnchor.constraint(equalTo: assessmentCard.leadingAnchor),
            assessmentStack.trailingAnchor.constraint(equalTo: assessmentCard.trailingAnchor),
            assessmentStack.bottomAnchor.constraint(equalTo: assessmentCard.bottomAnchor),
        ])

        assessmentStack.addArrangedSubview(
            WOMeasurementRow(label: "Exudate Amount", value: viewModel.exudateDisplay, unit: ""))
        assessmentStack.addArrangedSubview(
            WOMeasurementRow(label: "Tissue Type", value: viewModel.tissueTypeDisplay, unit: "", showSeparator: false))

        contentStack.addArrangedSubview(wrapInPadding(assessmentCard, horizontal: WOSpacing.lg))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === Capture Info ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "Capture Info"))

        let infoCard = WOCardView()
        infoCard.translatesAutoresizingMaskIntoConstraints = false

        let infoStack = UIStackView()
        infoStack.axis = .vertical
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoStack)

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: infoCard.topAnchor),
            infoStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor),
            infoStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor),
            infoStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor),
        ])

        infoStack.addArrangedSubview(
            WOMeasurementRow(label: "Processing Time", value: viewModel.processingTime, unit: ""))
        infoStack.addArrangedSubview(
            WOMeasurementRow(label: "Computed", value: "On Device", unit: "", showSeparator: false))

        contentStack.addArrangedSubview(wrapInPadding(infoCard, horizontal: WOSpacing.lg))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.xxxl))
    }

    // MARK: - Helpers

    private func makeSpacer(_ height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    private func wrapInPadding(_ view: UIView, horizontal: CGFloat) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontal),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontal),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Project the actual rotating-calipers length endpoints (3D world space)
    /// back to normalized 2D image coordinates for the overlay.
    private func makeLengthEndpoints() -> (CGPoint, CGPoint)? {
        guard let endpoints3D = viewModel.scan.primaryMeasurement.lengthEndpoints3D,
              endpoints3D.count == 2 else {
            return nil
        }
        return projectEndpoints(endpoints3D[0], endpoints3D[1])
    }

    /// Project the actual rotating-calipers width endpoints to 2D.
    private func makeWidthEndpoints() -> (CGPoint, CGPoint)? {
        guard let endpoints3D = viewModel.scan.primaryMeasurement.widthEndpoints3D,
              endpoints3D.count == 2 else {
            return nil
        }
        return projectEndpoints(endpoints3D[0], endpoints3D[1])
    }

    /// Project two 3D world-space points to normalized 2D image coordinates
    /// using the frozen camera parameters from the capture data.
    private func projectEndpoints(
        _ a3d: SIMD3<Float>,
        _ b3d: SIMD3<Float>
    ) -> (CGPoint, CGPoint)? {
        let captureData = viewModel.scan.captureData
        let intrinsics = captureData.intrinsicsMatrix
        let transform = captureData.transformMatrix
        let viewMatrix = transform.inverse

        func projectPoint(_ world: SIMD3<Float>) -> CGPoint? {
            let camHomog = viewMatrix * SIMD4<Float>(world.x, world.y, world.z, 1.0)
            let camPoint = SIMD3<Float>(camHomog.x, camHomog.y, camHomog.z)
            guard camPoint.z > 0 else { return nil }
            let projected = intrinsics * camPoint
            let nx = projected.x / (projected.z * Float(captureData.imageWidth))
            let ny = projected.y / (projected.z * Float(captureData.imageHeight))
            return CGPoint(x: CGFloat(nx), y: CGFloat(ny))
        }

        guard let a = projectPoint(a3d), let b = projectPoint(b3d) else { return nil }
        return (a, b)
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saving in
                self?.saveButton.isEnabled = !saving
                self?.saveButton.configuration?.showsActivityIndicator = saving
            }
            .store(in: &cancellables)

        viewModel.$saveError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                let alert = UIAlertController(title: "Save Error", message: error, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        viewModel.saveAndUpload()
    }
}
