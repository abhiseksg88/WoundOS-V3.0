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
        case clinical
        case developer
    }

    private var sections: [Section] {
        var s: [Section] = [.clinical]
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
        1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .clinical: return "SYNC"
        case .developer: return "DEVELOPER"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        var content = cell.defaultContentConfiguration()

        switch sections[indexPath.section] {
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

        case .developer:
            content.image = UIImage(systemName: "wrench.and.screwdriver")
            content.imageProperties.tintColor = WOColors.warningOrange
            content.text = "Developer Tools"
            content.secondaryText = "Segmenter debug, feature flags"
            content.secondaryTextProperties.color = WOColors.tertiaryText
        }

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = WOColors.cardBackground
        return cell
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch sections[indexPath.section] {
        case .clinical:
            onClinicalPlatformTapped?()
        case .developer:
            onDeveloperToolsTapped?()
        }
    }
}
