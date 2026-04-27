import UIKit
import WoundClinical

// MARK: - Wound Summary Cell

/// Compact wound summary row showing label, type, location, and status.
final class WoundSummaryCell: UITableViewCell {

    static let reuseId = "WoundSummaryCell"

    // MARK: - UI Elements

    private let woundDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = WOColors.primaryGreen
        view.layer.cornerRadius = 6
        return view
    }()

    private let labelText: UILabel = {
        let label = UILabel()
        label.font = WOFonts.bodyBold
        label.textColor = WOColors.primaryText
        return label
    }()

    private let typeLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.subheadline
        label.textColor = WOColors.secondaryText
        return label
    }()

    private let locationLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.footnote
        label.textColor = WOColors.tertiaryText
        return label
    }()

    private let statusBadge: UILabel = {
        let label = UILabel()
        label.font = WOFonts.badge
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
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

        let headerStack = UIStackView(arrangedSubviews: [woundDot, labelText])
        headerStack.axis = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [headerStack, typeLabel, locationLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [textStack, statusBadge])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            woundDot.widthAnchor.constraint(equalToConstant: 12),
            woundDot.heightAnchor.constraint(equalToConstant: 12),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: WOSpacing.md),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: WOSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -WOSpacing.lg),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -WOSpacing.md),
        ])

        accessoryType = .disclosureIndicator
    }

    // MARK: - Configure

    func configure(with wound: Wound) {
        labelText.text = wound.label
        typeLabel.text = wound.woundType.displayName
        locationLabel.text = wound.anatomicalLocation.displayName

        if wound.isHealed {
            statusBadge.text = " Healed "
            statusBadge.textColor = .white
            statusBadge.backgroundColor = WOColors.primaryGreen
            statusBadge.isHidden = false
            woundDot.backgroundColor = WOColors.primaryGreen.withAlphaComponent(0.4)
        } else {
            statusBadge.text = " Active "
            statusBadge.textColor = .white
            statusBadge.backgroundColor = WOColors.warningOrange
            statusBadge.isHidden = false
            woundDot.backgroundColor = WOColors.primaryGreen
        }
    }
}
