import UIKit

// MARK: - WoundOS Design System
// Inspired by Apple Health app design language.
// Clean, medical-grade, trustworthy aesthetic.

// MARK: - Colors

enum WOColors {

    // Primary brand
    static let primaryGreen = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0) // #2ECC71
    static let boundaryGreen = UIColor(red: 0.0, green: 0.90, blue: 0.30, alpha: 1.0)  // Bright wound boundary

    // Semantic
    static let measurementAccent = UIColor.systemTeal
    static let depthAccent = UIColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1.0) // Indigo-ish
    static let flagRed = UIColor.systemRed
    static let warningOrange = UIColor.systemOrange

    // Backgrounds
    static let screenBackground = UIColor.systemGroupedBackground
    static let cardBackground = UIColor.secondarySystemGroupedBackground
    static let elevatedCard = UIColor.tertiarySystemGroupedBackground

    // Text
    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let tertiaryText = UIColor.tertiaryLabel

    // Separators
    static let separator = UIColor.separator
    static let thinSeparator = UIColor.opaqueSeparator

    // Status
    static let statusPending = UIColor.systemOrange
    static let statusUploading = UIColor.systemYellow
    static let statusUploaded = UIColor.systemBlue
    static let statusProcessed = UIColor.systemGreen
    static let statusFailed = UIColor.systemRed

    // Agreement badges
    static let agreementGood = UIColor.systemGreen
    static let agreementFair = UIColor.systemOrange
    static let agreementPoor = UIColor.systemRed
}

// MARK: - Typography

enum WOFonts {

    // Large titles & headers
    static let largeTitle = UIFont.systemFont(ofSize: 34, weight: .bold)
    static let title1 = UIFont.systemFont(ofSize: 28, weight: .bold)
    static let title2 = UIFont.systemFont(ofSize: 22, weight: .bold)
    static let title3 = UIFont.systemFont(ofSize: 20, weight: .semibold)

    // Section headers
    static let sectionHeader = UIFont.systemFont(ofSize: 13, weight: .regular)
    static let sectionHeaderUppercase = UIFont.systemFont(ofSize: 13, weight: .medium)

    // Body
    static let body = UIFont.systemFont(ofSize: 17, weight: .regular)
    static let bodyBold = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let callout = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let subheadline = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let footnote = UIFont.systemFont(ofSize: 13, weight: .regular)
    static let caption1 = UIFont.systemFont(ofSize: 12, weight: .regular)
    static let caption2 = UIFont.systemFont(ofSize: 11, weight: .regular)

    // Measurements — monospaced digits for clean alignment
    static let measurementValue = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)
    static let measurementValueLarge = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
    static let measurementUnit = UIFont.systemFont(ofSize: 15, weight: .regular)

    // PUSH score
    static let pushScore = UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold)
    static let pushLabel = UIFont.systemFont(ofSize: 13, weight: .medium)

    // Wound label
    static let woundLabel = UIFont.systemFont(ofSize: 17, weight: .semibold)

    // Badge
    static let badge = UIFont.systemFont(ofSize: 12, weight: .medium)
}

// MARK: - Spacing & Layout

enum WOSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    // Card
    static let cardCornerRadius: CGFloat = 12
    static let cardPaddingH: CGFloat = 16
    static let cardPaddingV: CGFloat = 12

    // Section
    static let sectionSpacing: CGFloat = 24
    static let sectionHeaderBottom: CGFloat = 8
}

// MARK: - Reusable Card View

/// Apple Health-style rounded card container.
final class WOCardView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = WOColors.cardBackground
        layer.cornerRadius = WOSpacing.cardCornerRadius
        layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Measurement Row View

/// A single measurement row: label on left, value + unit on right.
/// Matches the screenshot's clean row layout.
final class WOMeasurementRow: UIView {

    private let labelView = UILabel()
    private let valueView = UILabel()
    private let unitView = UILabel()
    private let separatorView = UIView()

    init(label: String, value: String, unit: String, showSeparator: Bool = true) {
        super.init(frame: .zero)

        labelView.text = label
        labelView.font = WOFonts.body
        labelView.textColor = WOColors.primaryText
        labelView.translatesAutoresizingMaskIntoConstraints = false

        valueView.text = value
        valueView.font = WOFonts.measurementValue
        valueView.textColor = WOColors.primaryText
        valueView.textAlignment = .right
        valueView.translatesAutoresizingMaskIntoConstraints = false

        unitView.text = unit
        unitView.font = WOFonts.measurementUnit
        unitView.textColor = WOColors.secondaryText
        unitView.translatesAutoresizingMaskIntoConstraints = false

        separatorView.backgroundColor = WOColors.separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.isHidden = !showSeparator

        addSubview(labelView)
        addSubview(valueView)
        addSubview(unitView)
        addSubview(separatorView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.cardPaddingH),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),

            unitView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WOSpacing.cardPaddingH),
            unitView.firstBaselineAnchor.constraint(equalTo: valueView.firstBaselineAnchor),

            valueView.trailingAnchor.constraint(equalTo: unitView.leadingAnchor, constant: -4),
            valueView.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: WOSpacing.sm),

            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.cardPaddingH),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(value: String) {
        valueView.text = value
    }
}

// MARK: - Section Header Label

/// Apple Health-style uppercase section header.
final class WOSectionHeader: UIView {

    private let label = UILabel()

    init(title: String, uppercase: Bool = true) {
        super.init(frame: .zero)

        label.text = uppercase ? title.uppercased() : title
        label.font = uppercase ? WOFonts.sectionHeaderUppercase : WOFonts.title3
        label.textColor = WOColors.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.cardPaddingH),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -WOSpacing.sectionHeaderBottom),
            label.topAnchor.constraint(equalTo: topAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Wound Label Badge

/// "Wound W1" label with green dot indicator, matching the screenshot.
final class WOWoundBadge: UIView {

    init(label: String) {
        super.init(frame: .zero)

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = WOColors.primaryGreen
        dot.layer.cornerRadius = 5

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = label
        titleLabel.font = WOFonts.woundLabel
        titleLabel.textColor = WOColors.primaryText

        addSubview(dot)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.cardPaddingH),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: WOSpacing.sm),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -WOSpacing.cardPaddingH),

            heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - PUSH Score Card

/// Large PUSH score display with circular progress indicator.
final class WOPushScoreCard: UIView {

    private let scoreLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let ringLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(score: Int, maxScore: Int = 17, breakdown: String) {
        scoreLabel.text = "\(score)"
        subtitleLabel.text = breakdown

        let progress = CGFloat(score) / CGFloat(maxScore)
        ringLayer.strokeEnd = progress

        // Color based on score severity
        if score <= 5 {
            ringLayer.strokeColor = WOColors.primaryGreen.cgColor
        } else if score <= 11 {
            ringLayer.strokeColor = WOColors.warningOrange.cgColor
        } else {
            ringLayer.strokeColor = WOColors.flagRed.cgColor
        }
    }

    private func setup() {
        backgroundColor = WOColors.cardBackground
        layer.cornerRadius = WOSpacing.cardCornerRadius
        layer.cornerCurve = .continuous

        scoreLabel.font = WOFonts.pushScore
        scoreLabel.textColor = WOColors.primaryText
        scoreLabel.textAlignment = .center
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "PUSH Score"
        titleLabel.font = WOFonts.pushLabel
        titleLabel.textColor = WOColors.secondaryText
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = WOFonts.footnote
        subtitleLabel.textColor = WOColors.tertiaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let ringContainer = UIView()
        ringContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(ringContainer)
        addSubview(scoreLabel)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        let ringSize: CGFloat = 90

        NSLayoutConstraint.activate([
            ringContainer.topAnchor.constraint(equalTo: topAnchor, constant: WOSpacing.xl),
            ringContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),

            scoreLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: WOSpacing.sm),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: WOSpacing.xs),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.cardPaddingH),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WOSpacing.cardPaddingH),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -WOSpacing.lg),
        ])

        // Draw ring
        let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
        let radius = ringSize / 2 - 4
        let path = UIBezierPath(
            arcCenter: center, radius: radius,
            startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true
        )

        trackLayer.path = path.cgPath
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.systemFill.cgColor
        trackLayer.lineWidth = 6
        trackLayer.lineCap = .round
        ringContainer.layer.addSublayer(trackLayer)

        ringLayer.path = path.cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 6
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        ringContainer.layer.addSublayer(ringLayer)
    }
}

// MARK: - Depth Prompt View

/// "Scroll down to view wound depth" prompt — depth is auto-computed from LiDAR mesh.
final class WODepthPromptView: UIView {

    init(text: String = "Scroll down to view wound depth") {
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
        icon.tintColor = WOColors.secondaryText
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = text
        label.font = WOFonts.footnote
        label.textColor = WOColors.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = WOSpacing.sm
        stack.alignment = .center

        backgroundColor = WOColors.cardBackground.withAlphaComponent(0.85)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: WOSpacing.md),
            heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
