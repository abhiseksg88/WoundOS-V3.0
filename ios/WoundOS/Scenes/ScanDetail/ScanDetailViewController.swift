import UIKit
import Combine
import WoundCore

// MARK: - Scan Detail View Controller

/// Apple Health-style detail view for a wound scan.
/// Shows wound image with overlay, measurements, PUSH score,
/// shadow AI comparison, agreement metrics, and clinical summary.
final class ScanDetailViewController: UIViewController {

    private let viewModel: ScanDetailViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
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

    // MARK: - Init

    init(viewModel: ScanDetailViewModel) {
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
        buildContent()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // MARK: - Build Content

    private func buildContent() {
        let scan = viewModel.scan

        // === Wound Image ===
        let imageOverlay = WoundImageOverlayView()
        imageOverlay.translatesAutoresizingMaskIntoConstraints = false

        let boundaryPoints = scan.nurseBoundary.points2D.map {
            CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
        }

        imageOverlay.configure(with: WoundImageOverlayView.Configuration(
            boundaryPoints: boundaryPoints,
            lengthEndpoints: nil,
            widthEndpoints: nil,
            lengthText: nil,
            widthText: nil,
            image: UIImage(data: scan.captureData.rgbImageData)
        ))

        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageOverlay)

        NSLayoutConstraint.activate([
            imageOverlay.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageOverlay.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageOverlay.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageOverlay.heightAnchor.constraint(equalTo: imageOverlay.widthAnchor, multiplier: 0.75),
            imageContainer.bottomAnchor.constraint(equalTo: imageOverlay.bottomAnchor),
        ])

        contentStack.addArrangedSubview(imageContainer)
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.lg))

        // === Status Row ===
        let statusCard = makeCard(rows: [
            ("Status", viewModel.uploadStatusText, ""),
        ])
        contentStack.addArrangedSubview(WOSectionHeader(title: "Status"))
        contentStack.addArrangedSubview(padCard(statusCard))

        // Flag warnings
        if viewModel.isFlagged {
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sm))
            let flagCard = WOCardView()
            flagCard.translatesAutoresizingMaskIntoConstraints = false
            flagCard.backgroundColor = WOColors.flagRed.withAlphaComponent(0.08)

            let flagStack = UIStackView()
            flagStack.axis = .vertical
            flagStack.spacing = WOSpacing.xs
            flagStack.translatesAutoresizingMaskIntoConstraints = false

            for reason in viewModel.flagReasons {
                let row = makeFlagRow(reason)
                flagStack.addArrangedSubview(row)
            }

            flagCard.addSubview(flagStack)
            NSLayoutConstraint.activate([
                flagStack.topAnchor.constraint(equalTo: flagCard.topAnchor, constant: WOSpacing.md),
                flagStack.leadingAnchor.constraint(equalTo: flagCard.leadingAnchor, constant: WOSpacing.lg),
                flagStack.trailingAnchor.constraint(equalTo: flagCard.trailingAnchor, constant: -WOSpacing.lg),
                flagStack.bottomAnchor.constraint(equalTo: flagCard.bottomAnchor, constant: -WOSpacing.md),
            ])

            contentStack.addArrangedSubview(padCard(flagCard))
        }

        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === Measurements (Nurse) ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "Measurements"))
        contentStack.addArrangedSubview(padCard(makeCard(rows: viewModel.measurements.enumerated().map { i, m in
            (m.label, m.value, "")
        })))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === PUSH Score ===
        contentStack.addArrangedSubview(WOSectionHeader(title: "PUSH Score 3.0"))
        let pushCard = WOPushScoreCard()
        pushCard.translatesAutoresizingMaskIntoConstraints = false
        pushCard.configure(
            score: scan.pushScore.totalScore,
            breakdown: viewModel.pushBreakdown
        )
        contentStack.addArrangedSubview(padCard(pushCard))
        contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))

        // === Capture Quality (from CaptureQualityScore) ===
        if viewModel.hasQualityScore {
            let title = "Capture Quality" + (viewModel.qualityTier.map { " — \($0)" } ?? "")
            contentStack.addArrangedSubview(WOSectionHeader(title: title))
            contentStack.addArrangedSubview(padCard(makeCard(rows: viewModel.qualityRows.map { ($0.label, $0.value, "") })))
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))
        }

        // === Nurse vs AI Comparison ===
        if viewModel.hasShadowData {
            contentStack.addArrangedSubview(WOSectionHeader(title: "Nurse vs AI Comparison"))

            let comparisonCard = WOCardView()
            comparisonCard.translatesAutoresizingMaskIntoConstraints = false

            let compStack = UIStackView()
            compStack.axis = .vertical
            compStack.translatesAutoresizingMaskIntoConstraints = false
            comparisonCard.addSubview(compStack)

            NSLayoutConstraint.activate([
                compStack.topAnchor.constraint(equalTo: comparisonCard.topAnchor),
                compStack.leadingAnchor.constraint(equalTo: comparisonCard.leadingAnchor),
                compStack.trailingAnchor.constraint(equalTo: comparisonCard.trailingAnchor),
                compStack.bottomAnchor.constraint(equalTo: comparisonCard.bottomAnchor),
            ])

            // Header row
            compStack.addArrangedSubview(makeComparisonHeader())

            for (i, item) in viewModel.shadowComparison.enumerated() {
                let isLast = i == viewModel.shadowComparison.count - 1
                compStack.addArrangedSubview(makeComparisonRow(
                    label: item.label, nurse: item.nurse, ai: item.ai, showSep: !isLast))
            }

            contentStack.addArrangedSubview(padCard(comparisonCard))
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))
        }

        // === Agreement Metrics ===
        if let metrics = viewModel.agreementMetrics {
            contentStack.addArrangedSubview(WOSectionHeader(title: "Agreement Metrics"))
            contentStack.addArrangedSubview(padCard(makeCard(rows: metrics.map { ($0.label, $0.value, "") })))
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))
        }

        // === Clinical Summary ===
        if let summary = viewModel.clinicalSummary {
            contentStack.addArrangedSubview(WOSectionHeader(title: "Clinical Summary"))

            let summaryCard = WOCardView()
            summaryCard.translatesAutoresizingMaskIntoConstraints = false

            let summaryLabel = UILabel()
            summaryLabel.text = summary.narrativeSummary
            summaryLabel.font = WOFonts.body
            summaryLabel.textColor = WOColors.primaryText
            summaryLabel.numberOfLines = 0
            summaryLabel.translatesAutoresizingMaskIntoConstraints = false

            let trajectoryLabel = UILabel()
            trajectoryLabel.font = WOFonts.bodyBold
            trajectoryLabel.textColor = WOColors.primaryGreen
            trajectoryLabel.text = summary.trajectory.displayName
            trajectoryLabel.translatesAutoresizingMaskIntoConstraints = false

            let trajectoryIcon = UIImageView(image: UIImage(systemName: summary.trajectory.symbolName))
            trajectoryIcon.tintColor = WOColors.primaryGreen
            trajectoryIcon.translatesAutoresizingMaskIntoConstraints = false
            trajectoryIcon.contentMode = .scaleAspectFit

            summaryCard.addSubview(trajectoryIcon)
            summaryCard.addSubview(trajectoryLabel)
            summaryCard.addSubview(summaryLabel)

            NSLayoutConstraint.activate([
                trajectoryIcon.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: WOSpacing.lg),
                trajectoryIcon.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: WOSpacing.lg),
                trajectoryIcon.widthAnchor.constraint(equalToConstant: 20),
                trajectoryIcon.heightAnchor.constraint(equalToConstant: 20),

                trajectoryLabel.centerYAnchor.constraint(equalTo: trajectoryIcon.centerYAnchor),
                trajectoryLabel.leadingAnchor.constraint(equalTo: trajectoryIcon.trailingAnchor, constant: WOSpacing.sm),

                summaryLabel.topAnchor.constraint(equalTo: trajectoryIcon.bottomAnchor, constant: WOSpacing.md),
                summaryLabel.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: WOSpacing.lg),
                summaryLabel.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -WOSpacing.lg),
                summaryLabel.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -WOSpacing.lg),
            ])

            contentStack.addArrangedSubview(padCard(summaryCard))
            contentStack.addArrangedSubview(makeSpacer(WOSpacing.sectionSpacing))
        }

        contentStack.addArrangedSubview(makeSpacer(WOSpacing.xxxl))
    }

    // MARK: - UI Helpers

    private func makeSpacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func padCard(_ card: UIView) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeCard(rows: [(String, String, String)]) -> WOCardView {
        let card = WOCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        for (i, row) in rows.enumerated() {
            let isLast = i == rows.count - 1
            stack.addArrangedSubview(
                WOMeasurementRow(label: row.0, value: row.1, unit: row.2, showSeparator: !isLast))
        }

        return card
    }

    private func makeFlagRow(_ text: String) -> UIView {
        let container = UIView()
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = WOColors.flagRed
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = text
        label.font = WOFonts.footnote
        label.textColor = WOColors.flagRed
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: WOSpacing.sm),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeComparisonHeader() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Metric"
        label.font = WOFonts.caption1
        label.textColor = WOColors.tertiaryText
        label.translatesAutoresizingMaskIntoConstraints = false

        let nurseLabel = UILabel()
        nurseLabel.text = "Nurse"
        nurseLabel.font = WOFonts.caption1
        nurseLabel.textColor = WOColors.tertiaryText
        nurseLabel.textAlignment = .right
        nurseLabel.translatesAutoresizingMaskIntoConstraints = false

        let aiLabel = UILabel()
        aiLabel.text = "AI"
        aiLabel.font = WOFonts.caption1
        aiLabel.textColor = WOColors.tertiaryText
        aiLabel.textAlignment = .right
        aiLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(nurseLabel)
        container.addSubview(aiLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aiLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),
            aiLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aiLabel.widthAnchor.constraint(equalToConstant: 70),
            nurseLabel.trailingAnchor.constraint(equalTo: aiLabel.leadingAnchor, constant: -WOSpacing.md),
            nurseLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nurseLabel.widthAnchor.constraint(equalToConstant: 70),
        ])

        return container
    }

    private func makeComparisonRow(label: String, nurse: String, ai: String, showSep: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = WOFonts.body
        nameLabel.textColor = WOColors.primaryText
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let nurseValue = UILabel()
        nurseValue.text = nurse
        nurseValue.font = WOFonts.measurementValue
        nurseValue.textColor = WOColors.primaryText
        nurseValue.textAlignment = .right
        nurseValue.translatesAutoresizingMaskIntoConstraints = false

        let aiValue = UILabel()
        aiValue.text = ai
        aiValue.font = WOFonts.measurementValue
        aiValue.textColor = WOColors.measurementAccent
        aiValue.textAlignment = .right
        aiValue.translatesAutoresizingMaskIntoConstraints = false

        let sep = UIView()
        sep.backgroundColor = WOColors.separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.isHidden = !showSep

        container.addSubview(nameLabel)
        container.addSubview(nurseValue)
        container.addSubview(aiValue)
        container.addSubview(sep)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aiValue.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -WOSpacing.lg),
            aiValue.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            aiValue.widthAnchor.constraint(equalToConstant: 70),
            nurseValue.trailingAnchor.constraint(equalTo: aiValue.leadingAnchor, constant: -WOSpacing.md),
            nurseValue.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nurseValue.widthAnchor.constraint(equalToConstant: 70),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: WOSpacing.lg),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        return container
    }
}
