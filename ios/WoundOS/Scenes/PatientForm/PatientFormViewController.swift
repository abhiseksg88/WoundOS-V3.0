import UIKit
import Combine
import WoundClinical

// MARK: - Patient Form View Controller

/// Modal form for creating or editing a patient.
final class PatientFormViewController: UIViewController {

    private let viewModel: PatientFormViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "TextFieldCell")
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "PickerCell")
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "RiskFactorCell")
        tv.backgroundColor = WOColors.screenBackground
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 52
        return tv
    }()

    private lazy var saveButton = UIBarButtonItem(
        barButtonSystemItem: .save,
        target: self,
        action: #selector(saveTapped)
    )

    private lazy var cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(cancelTapped)
    )

    private enum Section: Int, CaseIterable {
        case name
        case details
        case insurance
        case riskFactors
    }

    // MARK: - Text Fields (retained for reading values)

    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let mrnField = UITextField()
    private let roomField = UITextField()
    private let dobPicker = UIDatePicker()

    // MARK: - Init

    init(viewModel: PatientFormViewModel) {
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
        configureFields()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItem = saveButton

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureFields() {
        firstNameField.text = viewModel.firstName
        firstNameField.placeholder = "First Name *"
        firstNameField.font = WOFonts.body
        firstNameField.autocapitalizationType = .words
        firstNameField.returnKeyType = .next
        firstNameField.addTarget(self, action: #selector(firstNameChanged), for: .editingChanged)

        lastNameField.text = viewModel.lastName
        lastNameField.placeholder = "Last Name *"
        lastNameField.font = WOFonts.body
        lastNameField.autocapitalizationType = .words
        lastNameField.returnKeyType = .next
        lastNameField.addTarget(self, action: #selector(lastNameChanged), for: .editingChanged)

        mrnField.text = viewModel.medicalRecordNumber
        mrnField.placeholder = "Medical Record Number *"
        mrnField.font = WOFonts.body
        mrnField.autocapitalizationType = .allCharacters
        mrnField.returnKeyType = .next
        mrnField.addTarget(self, action: #selector(mrnChanged), for: .editingChanged)

        roomField.text = viewModel.roomNumber
        roomField.placeholder = "Room Number"
        roomField.font = WOFonts.body
        roomField.returnKeyType = .done
        roomField.addTarget(self, action: #selector(roomChanged), for: .editingChanged)

        dobPicker.datePickerMode = .date
        dobPicker.preferredDatePickerStyle = .compact
        dobPicker.maximumDate = Date()
        dobPicker.date = viewModel.dateOfBirth
        dobPicker.addTarget(self, action: #selector(dobChanged), for: .valueChanged)
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saving in
                self?.saveButton.isEnabled = !saving
                self?.cancelButton.isEnabled = !saving
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.save()
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
    }

    @objc private func firstNameChanged() { viewModel.firstName = firstNameField.text ?? "" }
    @objc private func lastNameChanged() { viewModel.lastName = lastNameField.text ?? "" }
    @objc private func mrnChanged() { viewModel.medicalRecordNumber = mrnField.text ?? "" }
    @objc private func roomChanged() { viewModel.roomNumber = roomField.text ?? "" }
    @objc private func dobChanged() { viewModel.dateOfBirth = dobPicker.date }
}

// MARK: - UITableViewDataSource

extension PatientFormViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name: return "Patient Name"
        case .details: return "Details"
        case .insurance: return "Insurance"
        case .riskFactors: return "Risk Factors"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .name: return 2
        case .details: return 3
        case .insurance: return InsuranceType.allCases.count
        case .riskFactors: return RiskFactor.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TextFieldCell", for: indexPath)
            cell.backgroundColor = WOColors.cardBackground
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let field = indexPath.row == 0 ? firstNameField : lastNameField
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.lg),
                field.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.lg),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: WOSpacing.sm),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -WOSpacing.sm),
            ])
            return cell

        case .details:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TextFieldCell", for: indexPath)
            cell.backgroundColor = WOColors.cardBackground
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            if indexPath.row == 0 {
                mrnField.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(mrnField)
                NSLayoutConstraint.activate([
                    mrnField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.lg),
                    mrnField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.lg),
                    mrnField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: WOSpacing.sm),
                    mrnField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -WOSpacing.sm),
                ])
            } else if indexPath.row == 1 {
                roomField.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(roomField)
                NSLayoutConstraint.activate([
                    roomField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.lg),
                    roomField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.lg),
                    roomField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: WOSpacing.sm),
                    roomField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -WOSpacing.sm),
                ])
            } else {
                let label = UILabel()
                label.text = "Date of Birth"
                label.font = WOFonts.body
                label.textColor = WOColors.primaryText
                label.translatesAutoresizingMaskIntoConstraints = false
                dobPicker.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(label)
                cell.contentView.addSubview(dobPicker)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.lg),
                    label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    dobPicker.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.lg),
                    dobPicker.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    dobPicker.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: WOSpacing.md),
                    cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                ])
            }
            return cell

        case .insurance:
            let cell = tableView.dequeueReusableCell(withIdentifier: "PickerCell", for: indexPath)
            let type = InsuranceType.allCases[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = type.displayName
            config.textProperties.font = WOFonts.body
            cell.contentConfiguration = config
            cell.backgroundColor = WOColors.cardBackground
            cell.accessoryType = viewModel.insuranceType == type ? .checkmark : .none
            return cell

        case .riskFactors:
            let cell = tableView.dequeueReusableCell(withIdentifier: "RiskFactorCell", for: indexPath)
            let factor = RiskFactor.allCases[indexPath.row]
            var config = cell.defaultContentConfiguration()
            config.text = factor.displayName
            config.textProperties.font = WOFonts.body
            cell.contentConfiguration = config
            cell.backgroundColor = WOColors.cardBackground
            cell.accessoryType = viewModel.selectedRiskFactors.contains(factor) ? .checkmark : .none
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension PatientFormViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .insurance:
            let type = InsuranceType.allCases[indexPath.row]
            viewModel.insuranceType = viewModel.insuranceType == type ? nil : type
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)

        case .riskFactors:
            let factor = RiskFactor.allCases[indexPath.row]
            viewModel.toggleRiskFactor(factor)
            tableView.reloadRows(at: [indexPath], with: .none)

        default:
            break
        }
    }
}
