import UIKit
import WoundCore

// MARK: - Scan Cell

/// Apple Health-style table cell displaying a wound scan summary.
/// Shows wound thumbnail, date, key measurements, and status.
final class ScanCell: UITableViewCell {

    static let reuseId = "ScanCell"

    // MARK: - UI Elements

    private let woundThumbnail: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 10
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = UIColor.systemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.bodyBold
        label.textColor = WOColors.primaryText
        return label
    }()

    private let measurementLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.subheadline
        label.textColor = WOColors.secondaryText
        return label
    }()

    private let dimensionsLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.footnote
        label.textColor = WOColors.tertiaryText
        return label
    }()

    private let pushContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pushScoreLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        label.textColor = WOColors.primaryText
        label.textAlignment = .center
        return label
    }()

    private let pushSubtitle: UILabel = {
        let label = UILabel()
        label.text = "PUSH"
        label.font = WOFonts.caption2
        label.textColor = WOColors.tertiaryText
        label.textAlignment = .center
        return label
    }()

    private let statusDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 4
        return view
    }()

    private let agreementBadge: UILabel = {
        let label = UILabel()
        label.font = WOFonts.badge
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        return label
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    private func setupLayout() {
        backgroundColor = WOColors.cardBackground

        let pushStack = UIStackView(arrangedSubviews: [pushScoreLabel, pushSubtitle])
        pushStack.axis = .vertical
        pushStack.alignment = .center
        pushStack.spacing = 0

        let textStack = UIStackView(arrangedSubviews: [dateLabel, measurementLabel, dimensionsLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let statusRow = UIStackView(arrangedSubviews: [statusDot, agreementBadge])
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        textStack.addArrangedSubview(statusRow)

        let mainStack = UIStackView(arrangedSubviews: [woundThumbnail, textStack, pushStack])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            woundThumbnail.widthAnchor.constraint(equalToConstant: 56),
            woundThumbnail.heightAnchor.constraint(equalToConstant: 56),

            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            pushStack.widthAnchor.constraint(equalToConstant: 48),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: WOSpacing.md),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: WOSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -WOSpacing.lg),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -WOSpacing.md),
        ])

        accessoryType = .disclosureIndicator
    }

    // MARK: - Configure

    func configure(with scan: WoundScan) {
        // Thumbnail
        woundThumbnail.image = UIImage(data: scan.captureData.rgbImageData)

        // Date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: scan.capturedAt)

        // Measurements
        let m = scan.primaryMeasurement
        measurementLabel.text = "Area: \(String(format: "%.1f", m.areaCm2)) cm²"
        dimensionsLabel.text = "\(String(format: "%.1f", m.lengthMm / 10)) × \(String(format: "%.1f", m.widthMm / 10)) cm"

        // PUSH
        pushScoreLabel.text = "\(scan.pushScore.totalScore)"

        // Upload status
        switch scan.uploadStatus {
        case .pending, .failed: statusDot.backgroundColor = WOColors.statusPending
        case .uploading:        statusDot.backgroundColor = WOColors.statusUploading
        case .uploaded:         statusDot.backgroundColor = WOColors.statusUploaded
        case .processed:        statusDot.backgroundColor = WOColors.statusProcessed
        }

        // Agreement badge
        if let agreement = scan.agreementMetrics {
            agreementBadge.isHidden = false
            if agreement.isFlagged {
                agreementBadge.text = " Flagged "
                agreementBadge.textColor = .white
                agreementBadge.backgroundColor = WOColors.agreementPoor
            } else {
                agreementBadge.text = String(format: " IoU %.0f%% ", agreement.iou * 100)
                agreementBadge.textColor = .white
                agreementBadge.backgroundColor = agreement.iou > 0.85
                    ? WOColors.agreementGood : WOColors.agreementFair
            }
        } else {
            agreementBadge.isHidden = true
        }
    }
}
