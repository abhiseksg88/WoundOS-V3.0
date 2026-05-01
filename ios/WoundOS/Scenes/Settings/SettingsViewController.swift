import UIKit
import CaptureSync

final class SettingsViewController: UIViewController {

    var onClinicalPlatformTapped: (() -> Void)?
    var onDeveloperToolsTapped: (() -> Void)?

    private let keychain: ClinicalPlatformKeychain

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.backgroundColor = WOColors.screenBackground
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        return tv
    }()

    // MARK: - Data

    private enum Section: Int, CaseIterable {
        case account
        case clinical
        case diagnostics
        case developer
    }

    private var sections: [Section] {
        var s: [Section] = [.account, .clinical, .diagnostics]
        if DeveloperMode.isEnabled {
            s.append(.developer)
        }
        return s
    }

    // MARK: - Init

    init(keychain: ClinicalPlatformKeychain) {
        self.keychain = keychain
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = WOColors.screenBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

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

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .account: return 2
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .account: return "ACCOUNT"
        case .clinical: return "SYNC"
        case .diagnostics: return "DIAGNOSTICS"
        case .developer: return "DEVELOPER"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator

        switch sections[indexPath.section] {
        case .account:
            if indexPath.row == 0 {
                content.image = UIImage(systemName: "person.circle.fill")
                content.imageProperties.tintColor = WOColors.primaryGreen
                if let user = keychain.loadVerifiedUser() {
                    content.text = user.name
                    content.secondaryText = "\(user.role) • \(user.tokenLabel ?? user.userId)"
                    content.secondaryTextProperties.color = WOColors.secondaryText
                } else {
                    content.text = "Not signed in"
                    content.secondaryTextProperties.color = WOColors.tertiaryText
                }
                cell.accessoryType = .none
            } else {
                content.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
                content.imageProperties.tintColor = WOColors.flagRed
                content.text = "Sign Out"
                content.textProperties.color = WOColors.flagRed
                cell.accessoryType = .none
            }

        case .clinical:
            content.image = UIImage(systemName: "arrow.up.doc")
            content.imageProperties.tintColor = WOColors.primaryGreen
            content.text = "Clinical Platform"

            if let user = keychain.loadVerifiedUser() {
                content.secondaryText = "Connected as \(user.name)"
                content.secondaryTextProperties.color = WOColors.primaryGreen
            } else {
                content.secondaryText = "Not configured"
                content.secondaryTextProperties.color = WOColors.tertiaryText
            }

        case .diagnostics:
            content.image = UIImage(systemName: "ladybug")
            content.imageProperties.tintColor = WOColors.warningOrange
            content.text = "Share Debug Logs"
            content.secondaryText = "Export crash & diagnostic logs"
            content.secondaryTextProperties.color = WOColors.tertiaryText

        case .developer:
            content.image = UIImage(systemName: "wrench.and.screwdriver")
            content.imageProperties.tintColor = WOColors.warningOrange
            content.text = "Developer Tools"
            content.secondaryText = "Segmenter debug, feature flags"
            content.secondaryTextProperties.color = WOColors.tertiaryText
        }

        cell.contentConfiguration = content
        cell.backgroundColor = WOColors.cardBackground
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .account:
            if indexPath.row == 1 {
                confirmSignOut()
            }
        case .clinical:
            onClinicalPlatformTapped?()
        case .diagnostics:
            showDiagnosticsMenu()
        case .developer:
            onDeveloperToolsTapped?()
        }
    }

    private func showDiagnosticsMenu() {
        let alert = UIAlertController(title: "Debug Logs", message: "Export crash & diagnostic logs for debugging.", preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Share Log Files", style: .default) { [weak self] _ in
            let urls = CrashLogger.shared.logFileURLs()
            guard !urls.isEmpty else {
                let empty = UIAlertController(title: "No Logs", message: "No log files found.", preferredStyle: .alert)
                empty.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(empty, animated: true)
                return
            }
            let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            self?.present(activityVC, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Copy Logs to Clipboard", style: .default) { _ in
            let logText = CrashLogger.shared.exportLogs()
            UIPasteboard.general.string = logText
        })

        alert.addAction(UIAlertAction(title: "Clear All Logs", style: .destructive) { _ in
            CrashLogger.shared.clearLogs()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

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
