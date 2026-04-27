import UIKit
import Combine
import WoundClinical

// MARK: - Post Scan Assignment View Controller

/// Shown after Quick Scan measurement — lets the nurse assign the scan
/// to an existing patient or create a new one, then select/create a wound.
final class PostScanAssignmentViewController: UIViewController {

    var onAssigned: ((Patient, Wound) -> Void)?
    var onSkip: (() -> Void)?

    private let storage: ClinicalStorageProvider
    private var patients: [Patient] = []
    private var filteredPatients: [Patient] = []
    private var selectedPatient: Patient?
    private var wounds: [Wound] = []
    private var selectedWound: Wound?

    // MARK: - UI

    private lazy var searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Search patients by name or MRN..."
        sb.searchBarStyle = .minimal
        sb.delegate = self
        sb.translatesAutoresizingMaskIntoConstraints = false
        return sb
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tv.dataSource = self
        tv.delegate = self
        tv.backgroundColor = WOColors.screenBackground
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 52
        return tv
    }()

    private lazy var continueButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Continue", for: .normal)
        btn.titleLabel?.font = WOFonts.bodyBold
        btn.setTitleColor(.white, for: .normal)
        btn.setTitleColor(.white.withAlphaComponent(0.5), for: .disabled)
        btn.backgroundColor = WOColors.primaryGreen
        btn.layer.cornerRadius = 14
        btn.layer.cornerCurve = .continuous
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isEnabled = false
        btn.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return btn
    }()

    private enum Section: Int, CaseIterable {
        case patient
        case wound
    }

    // MARK: - Init

    init(storage: ClinicalStorageProvider) {
        self.storage = storage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Assign to Patient"
        setupUI()
        loadPatients()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Skip",
            style: .plain,
            target: self,
            action: #selector(skipTapped)
        )
    }

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground

        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -WOSpacing.sm),

            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),
            continueButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func loadPatients() {
        Task { @MainActor in
            patients = (try? await storage.fetchAllPatients()) ?? []
            filteredPatients = patients
            tableView.reloadData()
        }
    }

    private func loadWounds(for patient: Patient) {
        Task { @MainActor in
            wounds = (try? await storage.fetchWounds(patientId: patient.id)) ?? []
            if wounds.isEmpty {
                let newWound = Wound(
                    patientId: patient.id,
                    label: "W1",
                    woundType: .other,
                    anatomicalLocation: AnatomicalLocation(region: .other, laterality: .notApplicable)
                )
                try? await storage.saveWound(newWound)
                wounds = [newWound]
            }
            selectedWound = wounds.first
            updateContinueButton()
            tableView.reloadData()
        }
    }

    private func updateContinueButton() {
        continueButton.isEnabled = selectedPatient != nil && selectedWound != nil
        continueButton.alpha = continueButton.isEnabled ? 1.0 : 0.5
    }

    @objc private func continueTapped() {
        guard let patient = selectedPatient, let wound = selectedWound else { return }
        onAssigned?(patient, wound)
    }

    @objc private func skipTapped() {
        onSkip?()
    }
}

// MARK: - UISearchBarDelegate

extension PostScanAssignmentViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            filteredPatients = patients
        } else {
            let q = searchText.lowercased()
            filteredPatients = patients.filter {
                $0.firstName.lowercased().contains(q) ||
                $0.lastName.lowercased().contains(q) ||
                $0.medicalRecordNumber.lowercased().contains(q)
            }
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension PostScanAssignmentViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        selectedPatient != nil ? 2 : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .patient: return "Select Patient"
        case .wound: return "Select Wound"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .patient: return filteredPatients.count
        case .wound: return max(wounds.count, 1)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.backgroundColor = WOColors.cardBackground

        switch Section(rawValue: indexPath.section)! {
        case .patient:
            let patient = filteredPatients[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = patient.fullName
            config.secondaryText = "MRN: \(patient.medicalRecordNumber)"
            config.textProperties.font = WOFonts.bodyBold
            config.secondaryTextProperties.font = WOFonts.footnote
            config.secondaryTextProperties.color = WOColors.secondaryText
            cell.contentConfiguration = config
            cell.accessoryType = selectedPatient?.id == patient.id ? .checkmark : .none

        case .wound:
            if wounds.isEmpty {
                var config = cell.defaultContentConfiguration()
                config.text = "No wounds — one will be created"
                config.textProperties.font = WOFonts.subheadline
                config.textProperties.color = WOColors.tertiaryText
                cell.contentConfiguration = config
                cell.accessoryType = .none
            } else {
                let wound = wounds[indexPath.row]
                var config = cell.defaultContentConfiguration()
                config.text = "\(wound.label) — \(wound.woundType.displayName)"
                config.secondaryText = wound.anatomicalLocation.displayName
                config.textProperties.font = WOFonts.bodyBold
                config.secondaryTextProperties.font = WOFonts.footnote
                config.secondaryTextProperties.color = WOColors.secondaryText
                cell.contentConfiguration = config
                cell.accessoryType = selectedWound?.id == wound.id ? .checkmark : .none
            }
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension PostScanAssignmentViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .patient:
            let patient = filteredPatients[indexPath.row]
            selectedPatient = patient
            loadWounds(for: patient)

        case .wound:
            guard !wounds.isEmpty else { return }
            selectedWound = wounds[indexPath.row]
            updateContinueButton()
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        }
    }
}
