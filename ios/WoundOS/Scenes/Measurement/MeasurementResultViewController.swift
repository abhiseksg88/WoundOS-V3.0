import UIKit
import Combine
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

    private lazy var assessmentButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Continue to Assessment"
        config.image = UIImage(systemName: "doc.text.fill")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = WOColors.primaryGreen
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(assessmentTapped), for: .touchUpInside)
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
        scrollView.addSubview(contentStack)

        if viewModel.showContinueToAssessment {
            let buttonStack = UIStackView(arrangedSubviews: [assessmentButton, saveButton])
            buttonStack.axis = .vertical
            buttonStack.spacing = WOSpacing.sm
            buttonStack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(buttonStack)

            var saveConfig = saveButton.configuration
            saveConfig?.baseBackgroundColor = .secondarySystemFill
            saveConfig?.baseForegroundColor = WOColors.secondaryText
            saveButton.configuration = saveConfig

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -WOSpacing.md),

                contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
                contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

                buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
                buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),
                buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),
                assessmentButton.heightAnchor.constraint(equalToConstant: 50),
                saveButton.heightAnchor.constraint(equalToConstant: 50),
            ])
        } else {
            view.addSubview(saveButton)

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

        // === Clinical Measurement (Manual) Section ===
        if viewModel.showContinueToAssessment {
            contentStack.addArrangedSubview(makeManualMeasurementSection())
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))
        }

        // === Auto-Measured Section Header ===
        if viewModel.showContinueToAssessment {
            let autoHeader = makeSubduedSectionHeader(
                title: "Auto-Measured (Research)",
                subtitle: "Collected for accuracy validation \u{2014} not for clinical use"
            )
            contentStack.addArrangedSubview(autoHeader)
        }

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

    // MARK: - Manual Measurement Section

    private func makeManualMeasurementSection() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let headerLabel = UILabel()
        headerLabel.text = "Clinical Measurement"
        headerLabel.font = WOFonts.title3
        headerLabel.textColor = WOColors.primaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Recorded by nurse with traditional measurement tools"
        subtitleLabel.font = WOFonts.footnote
        subtitleLabel.textColor = WOColors.secondaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let card = WOCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let fieldStack = UIStackView()
        fieldStack.axis = .vertical
        fieldStack.spacing = WOSpacing.sm
        fieldStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(fieldStack)

        NSLayoutConstraint.activate([
            fieldStack.topAnchor.constraint(equalTo: card.topAnchor, constant: WOSpacing.cardPaddingV),
            fieldStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: WOSpacing.cardPaddingH),
            fieldStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -WOSpacing.cardPaddingH),
            fieldStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -WOSpacing.cardPaddingV),
        ])

        let lengthField = makeManualField(label: "Length (cm)", keyPath: \.manualLengthCm)
        let widthField = makeManualField(label: "Width (cm)", keyPath: \.manualWidthCm)
        let depthField = makeManualField(label: "Depth (cm)", keyPath: \.manualDepthCm)

        fieldStack.addArrangedSubview(lengthField)
        fieldStack.addArrangedSubview(widthField)
        fieldStack.addArrangedSubview(depthField)
        fieldStack.addArrangedSubview(makeMethodPicker())

        container.addSubview(headerLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(card)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),

            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),

            card.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: WOSpacing.md),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeManualField(label: String, keyPath: ReferenceWritableKeyPath<MeasurementResultViewModel, String>) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = WOSpacing.md
        row.alignment = .center

        let lbl = UILabel()
        lbl.text = label
        lbl.font = WOFonts.body
        lbl.textColor = WOColors.primaryText
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let field = UITextField()
        field.font = WOFonts.measurementValue
        field.textColor = WOColors.primaryGreen
        field.textAlignment = .right
        field.keyboardType = .decimalPad
        field.placeholder = "0.0"
        field.borderStyle = .roundedRect
        field.backgroundColor = WOColors.screenBackground
        field.text = viewModel[keyPath: keyPath]
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true

        field.addAction(UIAction { [weak self] action in
            guard let self, let tf = action.sender as? UITextField else { return }
            self.viewModel[keyPath: keyPath] = tf.text ?? ""
        }, for: .editingChanged)

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(field)
        return row
    }

    private func makeMethodPicker() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = WOSpacing.md
        row.alignment = .center

        let lbl = UILabel()
        lbl.text = "Method"
        lbl.font = WOFonts.body
        lbl.textColor = WOColors.primaryText
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let items = MeasurementResultViewModel.ManualMethod.allCases.map(\.rawValue)
        let seg = UISegmentedControl(items: items)
        seg.selectedSegmentIndex = 0
        seg.addAction(UIAction { [weak self] action in
            guard let sc = action.sender as? UISegmentedControl else { return }
            self?.viewModel.manualMethod = MeasurementResultViewModel.ManualMethod.allCases[sc.selectedSegmentIndex]
        }, for: .valueChanged)

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(seg)
        return row
    }

    private func makeSubduedSectionHeader(title: String, subtitle: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = WOFonts.subheadline
        titleLabel.textColor = WOColors.tertiaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = WOFonts.caption1
        subtitleLabel.textColor = WOColors.tertiaryText
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -WOSpacing.sm),
        ])

        return container
    }

    /// Compute L/W endpoints directly from the 2D boundary polygon.
    /// This avoids fragile 3D→2D reprojection through camera intrinsics.
    private func makeLengthEndpoints() -> (CGPoint, CGPoint)? {
        let dims = compute2DDimensions()
        return dims?.lengthEndpoints
    }

    private func makeWidthEndpoints() -> (CGPoint, CGPoint)? {
        let dims = compute2DDimensions()
        return dims?.widthEndpoints
    }

    private var cached2DDimensions: (lengthEndpoints: (CGPoint, CGPoint), widthEndpoints: (CGPoint, CGPoint))?
    private var dimensionsComputed = false

    private func compute2DDimensions() -> (lengthEndpoints: (CGPoint, CGPoint), widthEndpoints: (CGPoint, CGPoint))? {
        if dimensionsComputed { return cached2DDimensions }
        dimensionsComputed = true

        let pts = viewModel.boundaryPointsCG
        guard pts.count >= 3 else { return nil }

        // Find length: max distance pair in 2D boundary
        var maxDist: CGFloat = 0
        var p1 = pts[0], p2 = pts[0]
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dx = pts[i].x - pts[j].x
                let dy = pts[i].y - pts[j].y
                let d = dx * dx + dy * dy
                if d > maxDist {
                    maxDist = d
                    p1 = pts[i]
                    p2 = pts[j]
                }
            }
        }

        guard maxDist > 0 else { return nil }

        // Length direction
        let lenDx = p2.x - p1.x
        let lenDy = p2.y - p1.y
        let lenMag = sqrt(lenDx * lenDx + lenDy * lenDy)
        guard lenMag > 1e-6 else { return nil }
        let dirX = lenDx / lenMag
        let dirY = lenDy / lenMag

        // Width: max perpendicular extent
        var maxPerp: CGFloat = 0
        var w1 = pts[0], w2 = pts[0]
        for pt in pts {
            let dx = pt.x - p1.x
            let dy = pt.y - p1.y
            let perpDist = abs(-dirY * dx + dirX * dy)
            if perpDist > maxPerp {
                maxPerp = perpDist
                let proj = dirX * dx + dirY * dy
                let projPt = CGPoint(x: p1.x + proj * dirX, y: p1.y + proj * dirY)
                w1 = projPt
                w2 = pt
            }
        }

        cached2DDimensions = (lengthEndpoints: (p1, p2), widthEndpoints: (w1, w2))
        return cached2DDimensions
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

    @objc private func assessmentTapped() {
        viewModel.onContinueToAssessment?()
    }
}
