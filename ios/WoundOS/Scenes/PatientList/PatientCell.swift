import UIKit
import WoundClinical

// MARK: - Patient Cell

/// Apple Health-style table cell displaying a patient summary.
final class PatientCell: UITableViewCell {

    static let reuseId = "PatientCell"

    // MARK: - UI Elements

    private let avatarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.backgroundColor = WOColors.primaryGreen.withAlphaComponent(0.15)
        return view
    }()

    private let initialsLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.bodyBold
        label.textColor = WOColors.primaryGreen
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.bodyBold
        label.textColor = WOColors.primaryText
        return label
    }()

    private let mrnLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.subheadline
        label.textColor = WOColors.secondaryText
        return label
    }()

    private let roomLabel: UILabel = {
        let label = UILabel()
        label.font = WOFonts.footnote
        label.textColor = WOColors.tertiaryText
        return label
    }()

    private let woundCountBadge: UILabel = {
        let label = UILabel()
        label.font = WOFonts.badge
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = WOColors.primaryGreen
        label.layer.cornerRadius = 10
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

        avatarView.addSubview(initialsLabel)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, mrnLabel, roomLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [avatarView, textStack, woundCountBadge])
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            woundCountBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            woundCountBadge.heightAnchor.constraint(equalToConstant: 20),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: WOSpacing.md),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: WOSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -WOSpacing.lg),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -WOSpacing.md),
        ])

        accessoryType = .disclosureIndicator
    }

    // MARK: - Configure

    func configure(with patient: Patient, woundCount: Int = 0) {
        let first = patient.firstName.prefix(1).uppercased()
        let last = patient.lastName.prefix(1).uppercased()
        initialsLabel.text = "\(first)\(last)"

        nameLabel.text = patient.fullName

        mrnLabel.text = "MRN: \(patient.medicalRecordNumber)"

        if let room = patient.roomNumber, !room.isEmpty {
            roomLabel.text = "Room \(room)"
            roomLabel.isHidden = false
        } else {
            roomLabel.isHidden = true
        }

        if woundCount > 0 {
            woundCountBadge.text = " \(woundCount) "
            woundCountBadge.isHidden = false
        } else {
            woundCountBadge.isHidden = true
        }
    }
}
