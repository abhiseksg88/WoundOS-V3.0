import UIKit
import Combine
import WoundCore
import WoundClinical

// MARK: - Wound Assessment View Controller

/// Clinical wound assessment form. Appears after measurement results.
/// Captures wound bed tissue %, exudate, surrounding skin, pain, odor,
/// optional manual depth, and clinical notes.
final class WoundAssessmentViewController: UIViewController {

    private let viewModel: WoundAssessmentViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "SliderCell")
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "TextCell")
        tv.backgroundColor = WOColors.screenBackground
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 52
        tv.keyboardDismissMode = .interactive
        return tv
    }()

    private lazy var saveButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Save Assessment", for: .normal)
        btn.titleLabel?.font = WOFonts.bodyBold
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = WOColors.primaryGreen
        btn.layer.cornerRadius = 14
        btn.layer.cornerCurve = .continuous
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return btn
    }()

    private enum Section: Int, CaseIterable {
        case woundBed
        case exudate
        case surroundingSkin
        case pain
        case odor
        case manualDepth
        case notes
    }

    // MARK: - Init

    init(viewModel: WoundAssessmentViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Wound Assessment"
        setupUI()
        bindViewModel()
    }

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground

        view.addSubview(tableView)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -WOSpacing.sm),

            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WOSpacing.lg),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WOSpacing.lg),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WOSpacing.md),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func bindViewModel() {
        viewModel.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saving in
                self?.saveButton.isEnabled = !saving
                self?.saveButton.alpha = saving ? 0.6 : 1.0
            }
            .store(in: &cancellables)

        viewModel.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                let alert = UIAlertController(title: "Error", message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        viewModel.saveAssessment()
    }

    // MARK: - Section Helpers

    private var visibleSections: [Section] {
        var sections = Section.allCases
        if !viewModel.needsManualDepth {
            sections.removeAll { $0 == .manualDepth }
        }
        return sections
    }

    private func section(at index: Int) -> Section {
        visibleSections[index]
    }
}

// MARK: - UITableViewDataSource

extension WoundAssessmentViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch self.section(at: section) {
        case .woundBed: return "Wound Bed Tissue (%)"
        case .exudate: return "Exudate"
        case .surroundingSkin: return "Surrounding Skin"
        case .pain: return "Pain Assessment"
        case .odor: return "Odor"
        case .manualDepth: return "Manual Depth Entry"
        case .notes: return "Clinical Notes"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch self.section(at: section) {
        case .woundBed:
            let total = viewModel.woundBedTotal
            return total == 100 ? "Total: 100% \u{2713}" : "Total: \(total)% — must equal 100%"
        case .manualDepth:
            return "LiDAR depth not captured. Enter depth measured with probe."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.section(at: section) {
        case .woundBed: return 5
        case .exudate: return 3
        case .surroundingSkin: return PeriwoundCondition.allCases.count
        case .pain: return 2
        case .odor: return OdorLevel.allCases.count
        case .manualDepth: return 1
        case .notes: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch self.section(at: indexPath.section) {
        case .woundBed:
            return woundBedCell(for: indexPath)
        case .exudate:
            return exudateCell(for: indexPath)
        case .surroundingSkin:
            return surroundingSkinCell(for: indexPath)
        case .pain:
            return painCell(for: indexPath)
        case .odor:
            return odorCell(for: indexPath)
        case .manualDepth:
            return manualDepthCell(for: indexPath)
        case .notes:
            return notesCell(for: indexPath)
        }
    }

    // MARK: - Cell Builders

    private func woundBedCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let labels = ["Granulation", "Slough", "Necrotic", "Epithelial", "Other"]
        let values = [viewModel.granulationPercent, viewModel.sloughPercent, viewModel.necroticPercent, viewModel.epithelialPercent, viewModel.otherTissuePercent]
        var config = cell.defaultContentConfiguration()
        config.text = labels[indexPath.row]
        config.secondaryText = "\(values[indexPath.row])%"
        config.prefersSideBySideTextAndSecondaryText = true
        config.textProperties.font = WOFonts.body
        config.secondaryTextProperties.font = WOFonts.measurementValue
        config.secondaryTextProperties.color = WOColors.primaryGreen
        cell.contentConfiguration = config
        cell.backgroundColor = WOColors.cardBackground
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func exudateCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.prefersSideBySideTextAndSecondaryText = true
        config.textProperties.font = WOFonts.body
        config.secondaryTextProperties.font = WOFonts.body
        config.secondaryTextProperties.color = WOColors.secondaryText

        switch indexPath.row {
        case 0:
            config.text = "Amount"
            config.secondaryText = viewModel.exudateAmount.displayName
        case 1:
            config.text = "Type"
            config.secondaryText = viewModel.exudateType.rawValue.capitalized
        default:
            config.text = "Color"
            config.secondaryText = viewModel.exudateColor.rawValue.capitalized
        }

        cell.contentConfiguration = config
        cell.backgroundColor = WOColors.cardBackground
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func surroundingSkinCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let condition = PeriwoundCondition.allCases[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = condition.rawValue.capitalized
        config.textProperties.font = WOFonts.body
        cell.contentConfiguration = config
        cell.backgroundColor = WOColors.cardBackground
        cell.accessoryType = viewModel.selectedPeriwoundConditions.contains(condition) ? .checkmark : .none
        return cell
    }

    private func painCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.prefersSideBySideTextAndSecondaryText = true
        config.textProperties.font = WOFonts.body

        if indexPath.row == 0 {
            config.text = "Pain Level (0-10)"
            config.secondaryText = "\(viewModel.painLevel)"
            config.secondaryTextProperties.font = WOFonts.measurementValue
            config.secondaryTextProperties.color = viewModel.painLevel > 0 ? WOColors.warningOrange : WOColors.primaryGreen
        } else {
            config.text = "Timing"
            config.secondaryText = viewModel.painTiming.rawValue.capitalized
            config.secondaryTextProperties.font = WOFonts.body
            config.secondaryTextProperties.color = WOColors.secondaryText
        }

        cell.contentConfiguration = config
        cell.backgroundColor = WOColors.cardBackground
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func odorCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let level = OdorLevel.allCases[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = level.rawValue.capitalized
        config.textProperties.font = WOFonts.body
        cell.contentConfiguration = config
        cell.backgroundColor = WOColors.cardBackground
        cell.accessoryType = viewModel.odorLevel == level ? .checkmark : .none
        return cell
    }

    private func manualDepthCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TextCell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.backgroundColor = WOColors.cardBackground
        cell.selectionStyle = .none

        let field = UITextField()
        field.placeholder = "Depth in cm"
        field.font = WOFonts.body
        field.keyboardType = .decimalPad
        field.text = viewModel.manualDepthCm
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addAction(UIAction { [weak self] action in
            self?.viewModel.manualDepthCm = (action.sender as? UITextField)?.text ?? ""
        }, for: .editingChanged)

        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.lg),
            field.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.lg),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: WOSpacing.sm),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -WOSpacing.sm),
        ])
        return cell
    }

    private func notesCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TextCell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.backgroundColor = WOColors.cardBackground
        cell.selectionStyle = .none

        let textView = UITextView()
        textView.font = WOFonts.body
        textView.textColor = WOColors.primaryText
        textView.backgroundColor = .clear
        textView.text = viewModel.clinicalNotes
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self

        if viewModel.clinicalNotes.isEmpty {
            textView.text = "Add clinical observations..."
            textView.textColor = WOColors.tertiaryText
        }

        cell.contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: WOSpacing.md),
            textView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -WOSpacing.md),
            textView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: WOSpacing.sm),
            textView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -WOSpacing.sm),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension WoundAssessmentViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch self.section(at: indexPath.section) {
        case .woundBed:
            showPercentagePicker(for: indexPath)
        case .exudate:
            showExudatePicker(for: indexPath)
        case .surroundingSkin:
            let condition = PeriwoundCondition.allCases[indexPath.row]
            if viewModel.selectedPeriwoundConditions.contains(condition) {
                viewModel.selectedPeriwoundConditions.remove(condition)
            } else {
                viewModel.selectedPeriwoundConditions.insert(condition)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
        case .pain:
            showPainPicker(for: indexPath)
        case .odor:
            viewModel.odorLevel = OdorLevel.allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        default:
            break
        }
    }

    // MARK: - Pickers

    private func showPercentagePicker(for indexPath: IndexPath) {
        let labels = ["Granulation", "Slough", "Necrotic", "Epithelial", "Other"]
        let alert = UIAlertController(title: "\(labels[indexPath.row]) %", message: "Enter percentage (0-100)", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "0-100"
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let value = Int(text), value >= 0, value <= 100 else { return }
            switch indexPath.row {
            case 0: self?.viewModel.granulationPercent = value
            case 1: self?.viewModel.sloughPercent = value
            case 2: self?.viewModel.necroticPercent = value
            case 3: self?.viewModel.epithelialPercent = value
            default: self?.viewModel.otherTissuePercent = value
            }
            self?.tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showExudatePicker(for indexPath: IndexPath) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        switch indexPath.row {
        case 0:
            for amount in ExudateAmount.allCases {
                alert.addAction(UIAlertAction(title: amount.displayName, style: .default) { [weak self] _ in
                    self?.viewModel.exudateAmount = amount
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                })
            }
        case 1:
            for type in ExudateType.allCases {
                alert.addAction(UIAlertAction(title: type.rawValue.capitalized, style: .default) { [weak self] _ in
                    self?.viewModel.exudateType = type
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                })
            }
        default:
            for color in ExudateColor.allCases {
                alert.addAction(UIAlertAction(title: color.rawValue.capitalized, style: .default) { [weak self] _ in
                    self?.viewModel.exudateColor = color
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showPainPicker(for indexPath: IndexPath) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if indexPath.row == 0 {
            for level in stride(from: 0, through: 10, by: 1) {
                alert.addAction(UIAlertAction(title: "\(level)", style: .default) { [weak self] _ in
                    self?.viewModel.painLevel = level
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                })
            }
        } else {
            for timing in PainTiming.allCases {
                alert.addAction(UIAlertAction(title: timing.rawValue.capitalized, style: .default) { [weak self] _ in
                    self?.viewModel.painTiming = timing
                    self?.tableView.reloadRows(at: [indexPath], with: .none)
                })
            }
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UITextViewDelegate

extension WoundAssessmentViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == WOColors.tertiaryText {
            textView.text = ""
            textView.textColor = WOColors.primaryText
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        viewModel.clinicalNotes = textView.text
        if textView.text.isEmpty {
            textView.text = "Add clinical observations..."
            textView.textColor = WOColors.tertiaryText
        }
    }
}
