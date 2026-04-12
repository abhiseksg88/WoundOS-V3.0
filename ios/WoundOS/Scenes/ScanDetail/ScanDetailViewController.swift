import UIKit
import Combine
import WoundCore

// MARK: - Scan Detail View Controller

/// Full detail view for a single wound scan.
/// Shows measurements, PUSH score, shadow AI comparison,
/// agreement metrics, and clinical summary.
final class ScanDetailViewController: UIViewController {

    private let viewModel: ScanDetailViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        return tv
    }()

    // Section definitions
    private enum Section: Int, CaseIterable {
        case status
        case measurements
        case pushScore
        case shadowComparison
        case agreementMetrics
        case clinicalSummary
    }

    // MARK: - Init

    init(viewModel: ScanDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource

extension ScanDetailViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .status: return "Status"
        case .measurements: return "Measurements (Nurse)"
        case .pushScore: return "PUSH Score 3.0"
        case .shadowComparison: return viewModel.hasShadowData ? "Nurse vs AI Comparison" : nil
        case .agreementMetrics: return viewModel.agreementMetrics != nil ? "Agreement Metrics" : nil
        case .clinicalSummary: return viewModel.clinicalSummary != nil ? "Clinical Summary" : nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .status:
            return 1 + (viewModel.isFlagged ? viewModel.flagReasons.count : 0)
        case .measurements:
            return viewModel.measurements.count
        case .pushScore:
            return viewModel.pushDetails.count + 1 // +1 for total
        case .shadowComparison:
            return viewModel.hasShadowData ? viewModel.shadowComparison.count : 0
        case .agreementMetrics:
            return viewModel.agreementMetrics?.count ?? 0
        case .clinicalSummary:
            return viewModel.clinicalSummary != nil ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none

        switch Section(rawValue: indexPath.section)! {
        case .status:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Upload Status"
                cell.detailTextLabel?.text = viewModel.uploadStatusText
            } else {
                cell.textLabel?.text = viewModel.flagReasons[indexPath.row - 1]
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.font = .systemFont(ofSize: 13)
                cell.imageView?.image = UIImage(systemName: "exclamationmark.triangle.fill")
                cell.imageView?.tintColor = .systemRed
            }

        case .measurements:
            let item = viewModel.measurements[indexPath.row]
            cell.textLabel?.text = item.label
            cell.detailTextLabel?.text = item.value

        case .pushScore:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Total Score"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .bold)
                cell.detailTextLabel?.text = viewModel.pushScore
                cell.detailTextLabel?.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
            } else {
                let item = viewModel.pushDetails[indexPath.row - 1]
                cell.textLabel?.text = item.label
                cell.detailTextLabel?.text = item.value
            }

        case .shadowComparison:
            let item = viewModel.shadowComparison[indexPath.row]
            cell.textLabel?.text = item.label
            cell.detailTextLabel?.text = "N: \(item.nurse)  AI: \(item.ai)"
            cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        case .agreementMetrics:
            if let metrics = viewModel.agreementMetrics {
                let item = metrics[indexPath.row]
                cell.textLabel?.text = item.label
                cell.detailTextLabel?.text = item.value
            }

        case .clinicalSummary:
            if let summary = viewModel.clinicalSummary {
                cell.textLabel?.text = summary.narrativeSummary
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.font = .systemFont(ofSize: 14)
                cell.detailTextLabel?.text = nil
            }
        }

        return cell
    }
}
