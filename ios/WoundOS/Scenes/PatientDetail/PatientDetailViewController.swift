import UIKit
import Combine
import WoundClinical

// MARK: - Patient Detail View Controller

/// Patient detail screen with demographics, risk factors, wounds, and visit history.
final class PatientDetailViewController: UIViewController {

    private let viewModel: PatientDetailViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(WoundSummaryCell.self, forCellReuseIdentifier: WoundSummaryCell.reuseId)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "EncounterCell")
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "InfoCell")
        tv.dataSource = self
        tv.delegate = self
        tv.backgroundColor = WOColors.screenBackground
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        return tv
    }()

    private lazy var startAssessmentButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Start New Assessment", for: .normal)
        btn.titleLabel?.font = WOFonts.bodyBold
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = WOColors.primaryGreen
        btn.layer.cornerRadius = 14
        btn.layer.cornerCurve = .continuous
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(startAssessmentTapped), for: .touchUpInside)
        return btn
    }()

    private enum Section: Int, CaseIterable {
        case demographics
        case riskFactors
        case wounds
        case encounters
    }

    // MARK: - Init

    init(viewModel: PatientDetailViewModel) {
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
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadDetails()
    }

    func refreshData() {
        viewModel.loadDetails()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .edit,
            target: self,
            action: #selector(editTapped)
        )

        view.addSubview(tableView)
        view.addSubview(startAssessmentButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: startAssessmentButton.topAnchor, constant: -WOSpacing.sm),

            startAssessmentButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            startAssessmentButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),
            startAssessmentButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),
            startAssessmentButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$patient
            .combineLatest(viewModel.$wounds, viewModel.$encounters)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.tableView.reloadData()
                self?.title = self?.viewModel.patient.fullName
            }
            .store(in: &cancellables)
    }

    @objc private func editTapped() {
        viewModel.editPatient()
    }

    @objc private func startAssessmentTapped() {
        viewModel.startAssessment()
    }

    // MARK: - Helpers

    private var demographicsRows: [(String, String)] {
        let p = viewModel.patient
        let dobFormatter = DateFormatter()
        dobFormatter.dateStyle = .medium
        var rows: [(String, String)] = [
            ("MRN", p.medicalRecordNumber),
            ("Date of Birth", "\(dobFormatter.string(from: p.dateOfBirth)) (Age \(p.age))"),
            ("Gender", p.gender.rawValue.capitalized),
        ]
        if let room = p.roomNumber, !room.isEmpty {
            rows.append(("Room", room))
        }
        if let insurance = p.insuranceType {
            rows.append(("Insurance", insurance.displayName))
        }
        return rows
    }
}

// MARK: - UITableViewDataSource

extension PatientDetailViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .demographics: return "Demographics"
        case .riskFactors: return viewModel.patient.riskFactors.isEmpty ? nil : "Risk Factors"
        case .wounds: return "Active Wounds"
        case .encounters: return viewModel.encounters.isEmpty ? nil : "Visit History"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .demographics: return demographicsRows.count
        case .riskFactors: return viewModel.patient.riskFactors.isEmpty ? 0 : 1
        case .wounds: return max(viewModel.wounds.count, 1)
        case .encounters: return viewModel.encounters.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .demographics:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell", for: indexPath)
            let row = demographicsRows[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = row.0
            config.secondaryText = row.1
            config.prefersSideBySideTextAndSecondaryText = true
            config.textProperties.font = WOFonts.subheadline
            config.textProperties.color = WOColors.secondaryText
            config.secondaryTextProperties.font = WOFonts.body
            config.secondaryTextProperties.color = WOColors.primaryText
            cell.contentConfiguration = config
            cell.backgroundColor = WOColors.cardBackground
            cell.selectionStyle = .none
            return cell

        case .riskFactors:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell", for: indexPath)
            let factors = viewModel.patient.riskFactors.map { $0.displayName }.joined(separator: ", ")
            var config = cell.defaultContentConfiguration()
            config.text = factors
            config.textProperties.font = WOFonts.subheadline
            config.textProperties.color = WOColors.primaryText
            config.textProperties.numberOfLines = 0
            cell.contentConfiguration = config
            cell.backgroundColor = WOColors.cardBackground
            cell.selectionStyle = .none
            return cell

        case .wounds:
            if viewModel.wounds.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell", for: indexPath)
                var config = cell.defaultContentConfiguration()
                config.text = "No wounds recorded"
                config.textProperties.font = WOFonts.subheadline
                config.textProperties.color = WOColors.tertiaryText
                config.textProperties.alignment = .center
                cell.contentConfiguration = config
                cell.backgroundColor = WOColors.cardBackground
                cell.selectionStyle = .none
                return cell
            }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: WoundSummaryCell.reuseId, for: indexPath
            ) as? WoundSummaryCell else {
                return UITableViewCell()
            }
            cell.configure(with: viewModel.wounds[indexPath.row])
            return cell

        case .encounters:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell", for: indexPath)
            let encounter = viewModel.encounters[indexPath.row]
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            var config = cell.defaultContentConfiguration()
            config.text = formatter.string(from: encounter.visitDate)
            config.secondaryText = encounter.documentationStatus.rawValue.capitalized
            config.prefersSideBySideTextAndSecondaryText = true
            config.textProperties.font = WOFonts.body
            config.secondaryTextProperties.font = WOFonts.footnote
            config.secondaryTextProperties.color = WOColors.secondaryText
            cell.contentConfiguration = config
            cell.backgroundColor = WOColors.cardBackground
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension PatientDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .wounds:
            guard !viewModel.wounds.isEmpty else { return }
            viewModel.selectWound(viewModel.wounds[indexPath.row])
        default:
            break
        }
    }
}
