import UIKit
import WoundCore

// MARK: - Scan Cell

/// Table view cell displaying a wound scan summary.
final class ScanCell: UITableViewCell {

    static let reuseId = "ScanCell"

    // MARK: - UI Elements

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let measurementLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let pushLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private let pushSubLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = "PUSH"
        return label
    }()

    private let statusBadge: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        return view
    }()

    private let agreementBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
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
        let pushStack = UIStackView(arrangedSubviews: [pushLabel, pushSubLabel])
        pushStack.axis = .vertical
        pushStack.alignment = .center
        pushStack.spacing = 2

        let textStack = UIStackView(arrangedSubviews: [dateLabel, measurementLabel, agreementBadge])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading

        let mainStack = UIStackView(arrangedSubviews: [statusBadge, textStack, pushStack])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            statusBadge.widthAnchor.constraint(equalToConstant: 8),
            statusBadge.heightAnchor.constraint(equalToConstant: 8),

            pushStack.widthAnchor.constraint(equalToConstant: 50),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        accessoryType = .disclosureIndicator
    }

    // MARK: - Configure

    func configure(with scan: WoundScan) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: scan.capturedAt)

        let m = scan.primaryMeasurement
        measurementLabel.text = "Area: \(String(format: "%.1f", m.areaCm2)) cm² · Depth: \(String(format: "%.1f", m.maxDepthMm)) mm\nL: \(String(format: "%.0f", m.lengthMm)) × W: \(String(format: "%.0f", m.widthMm)) mm"

        pushLabel.text = "\(scan.pushScore.totalScore)"

        // Upload status indicator
        switch scan.uploadStatus {
        case .pending, .failed:
            statusBadge.backgroundColor = .systemOrange
        case .uploading:
            statusBadge.backgroundColor = .systemYellow
        case .uploaded:
            statusBadge.backgroundColor = .systemBlue
        case .processed:
            statusBadge.backgroundColor = .systemGreen
        }

        // Agreement badge
        if let agreement = scan.agreementMetrics {
            agreementBadge.isHidden = false
            if agreement.isFlagged {
                agreementBadge.text = " Flagged "
                agreementBadge.textColor = .white
                agreementBadge.backgroundColor = .systemRed
            } else {
                agreementBadge.text = String(format: " IoU: %.0f%% ", agreement.iou * 100)
                agreementBadge.textColor = .white
                agreementBadge.backgroundColor = agreement.iou > 0.85 ? .systemGreen : .systemOrange
            }
        } else {
            agreementBadge.isHidden = true
        }
    }
}
