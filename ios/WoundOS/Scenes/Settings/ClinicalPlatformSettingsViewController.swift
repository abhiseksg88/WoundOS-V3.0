import UIKit
import CaptureSync

final class ClinicalPlatformSettingsViewController: UIViewController {

    private let keychain: ClinicalPlatformKeychain
    private let client: ClinicalPlatformClient

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.backgroundColor = WOColors.screenBackground
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        return tv
    }()

    // MARK: - Data

    private enum Section: Int, CaseIterable {
        case status
        case actions
    }

    private var verifiedUser: VerifiedUser? {
        keychain.loadVerifiedUser()
    }

    // MARK: - Init

    init(keychain: ClinicalPlatformKeychain, client: ClinicalPlatformClient) {
        self.keychain = keychain
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clinical Platform"
        view.backgroundColor = WOColors.screenBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - Actions

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: "Sign Out",
            message: "Are you sure you want to sign out? You will need your CarePlix ID and Passcode to sign back in.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { _ in
            NotificationCenter.default.post(name: .carePlixLogout, object: nil)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ClinicalPlatformSettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .status: return verifiedUser != nil ? 4 : 1
        case .actions: return verifiedUser != nil ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .status: return "CONNECTION"
        case .actions: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none
        cell.accessoryType = .none

        switch Section(rawValue: indexPath.section)! {
        case .status:
            if let user = verifiedUser {
                switch indexPath.row {
                case 0:
                    content.image = UIImage(systemName: "checkmark.circle.fill")
                    content.imageProperties.tintColor = WOColors.primaryGreen
                    content.text = "Connected"
                    content.secondaryText = user.name
                    content.secondaryTextProperties.color = WOColors.secondaryText
                case 1:
                    content.image = UIImage(systemName: "person.badge.shield.checkmark")
                    content.imageProperties.tintColor = WOColors.secondaryText
                    content.text = "Role"
                    content.secondaryText = user.role.capitalized
                    content.secondaryTextProperties.color = WOColors.secondaryText
                case 2:
                    content.image = UIImage(systemName: "building.2")
                    content.imageProperties.tintColor = WOColors.secondaryText
                    content.text = "Facility"
                    content.secondaryText = user.facilityId
                    content.secondaryTextProperties.color = WOColors.secondaryText
                case 3:
                    content.image = UIImage(systemName: "key")
                    content.imageProperties.tintColor = WOColors.secondaryText
                    content.text = "CarePlix ID"
                    content.secondaryText = user.tokenLabel ?? user.userId
                    content.secondaryTextProperties.color = WOColors.secondaryText
                default:
                    break
                }
            } else {
                content.image = UIImage(systemName: "xmark.circle")
                content.imageProperties.tintColor = WOColors.tertiaryText
                content.text = "Not connected"
                content.secondaryText = "Sign in from the login screen"
                content.secondaryTextProperties.color = WOColors.tertiaryText
            }

        case .actions:
            content.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            content.imageProperties.tintColor = WOColors.flagRed
            content.text = "Sign Out"
            content.textProperties.color = WOColors.flagRed
            cell.selectionStyle = .default
        }

        cell.contentConfiguration = content
        cell.backgroundColor = WOColors.cardBackground
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ClinicalPlatformSettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if Section(rawValue: indexPath.section) == .actions {
            confirmSignOut()
        }
    }
}
