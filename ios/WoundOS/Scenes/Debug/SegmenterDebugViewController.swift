#if DEBUG
import UIKit
import WoundCore
import WoundAutoSegmentation

// MARK: - Segmenter Debug View Controller

/// Developer-only diagnostics screen for segmentation pipeline.
/// Shows feature flags, canary status, telemetry, and wound type override.
/// All code compiled out in Release builds.
final class SegmenterDebugViewController: UITableViewController {

    private let dependencies: DependencyContainer
    private var telemetryRecords: [SegmentationTelemetryRecord] = []

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case featureFlags = 0
        case segmenterStatus
        case canaryValidation
        case lastSegmentation
        case recentCaptures
        case woundType
    }

    private let sectionTitles: [Section: String] = [
        .featureFlags: "Feature Flags",
        .segmenterStatus: "Segmenter Status",
        .canaryValidation: "Canary Validation",
        .lastSegmentation: "Last Segmentation",
        .recentCaptures: "Recent Captures",
        .woundType: "Wound Type Override",
    ]

    // MARK: - Init

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Segmenter Debug"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "switchCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "valueCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    private func reloadData() {
        telemetryRecords = SegmentationTelemetryStore.shared.fetchRecords()
        tableView.reloadData()
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        return sectionTitles[sec]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == Section.featureFlags.rawValue {
            return "Restart capture flow for changes to take effect."
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .featureFlags:
            return FeatureFlag.allCases.count
        case .segmenterStatus:
            return 3
        case .canaryValidation:
            return 5
        case .lastSegmentation:
            return telemetryRecords.isEmpty ? 1 : 7
        case .recentCaptures:
            return max(1, min(10, telemetryRecords.count))
        case .woundType:
            return WoundType.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sec = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch sec {
        case .featureFlags:
            return featureFlagCell(at: indexPath)
        case .segmenterStatus:
            return segmenterStatusCell(at: indexPath)
        case .canaryValidation:
            return canaryCell(at: indexPath)
        case .lastSegmentation:
            return lastSegmentationCell(at: indexPath)
        case .recentCaptures:
            return recentCaptureCell(at: indexPath)
        case .woundType:
            return woundTypeCell(at: indexPath)
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sec = Section(rawValue: indexPath.section) else { return }
        if sec == .woundType {
            let allCases = Array(WoundType.allCases)
            guard indexPath.row < allCases.count else { return }
            WoundTypeOverride.current = allCases[indexPath.row]
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        }
    }

    // MARK: - Feature Flags Section

    private func featureFlagCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "switchCell", for: indexPath)
        cell.selectionStyle = .none
        let allFlags = Array(FeatureFlag.allCases)
        guard indexPath.row < allFlags.count else { return cell }
        let flag = allFlags[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = flag.rawValue
        config.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        cell.contentConfiguration = config

        let toggle = UISwitch()
        toggle.isOn = FeatureFlags.isEnabled(flag)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(flagToggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func flagToggled(_ sender: UISwitch) {
        let allFlags = Array(FeatureFlag.allCases)
        guard sender.tag < allFlags.count else { return }
        FeatureFlags.setEnabled(allFlags[sender.tag], sender.isOn)
    }

    // MARK: - Segmenter Status Section

    private func segmenterStatusCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "valueCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.font = .systemFont(ofSize: 14)
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        switch indexPath.row {
        case 0:
            config.text = "On-Device Flag"
            config.secondaryText = FeatureFlags.isEnabled(.onDeviceSegmentation) ? "ON" : "OFF"
        case 1:
            config.text = "Active Segmenter"
            if dependencies.autoSegmenter is ChainedSegmenter {
                config.secondaryText = "ChainedSegmenter"
            } else if dependencies.autoSegmenter != nil {
                config.secondaryText = "ServerSegmenter"
            } else {
                config.secondaryText = "None"
            }
        case 2:
            config.text = "Wound Type Override"
            config.secondaryText = WoundTypeOverride.current.rawValue
        default:
            break
        }
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Canary Validation Section

    private func canaryCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "valueCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.font = .systemFont(ofSize: 14)
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        let chained = dependencies.autoSegmenter as? ChainedSegmenter
        let canary = chained?.lastCanaryResult

        switch indexPath.row {
        case 0:
            config.text = "Status"
            if let canary {
                config.secondaryText = canary.passed ? "Passed" : "FAILED"
                config.secondaryTextProperties.color = canary.passed ? .systemGreen : .systemRed
            } else {
                config.secondaryText = chained != nil ? "Not Run Yet" : "N/A (No ChainedSegmenter)"
            }
        case 1:
            config.text = "IoU"
            config.secondaryText = canary.map { String(format: "%.4f", $0.iou) } ?? "-"
        case 2:
            config.text = "Expected Pixels"
            config.secondaryText = canary.map { "\($0.expectedPositivePixels)" } ?? "-"
        case 3:
            config.text = "Actual Pixels"
            config.secondaryText = canary.map { "\($0.actualPositivePixels)" } ?? "-"
        case 4:
            config.text = "Latency"
            config.secondaryText = canary.map { String(format: "%.0f ms", $0.latencyMs) } ?? "-"
        default:
            break
        }
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Last Segmentation Section

    private func lastSegmentationCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "valueCell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.font = .systemFont(ofSize: 14)
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        guard let record = telemetryRecords.last else {
            config.text = "No segmentation data"
            config.secondaryText = nil
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        }

        switch indexPath.row {
        case 0:
            config.text = "Model"
            config.secondaryText = record.segmenterIdentifier
        case 1:
            config.text = "Latency"
            config.secondaryText = String(format: "%.0f ms", record.inferenceLatencyMs)
        case 2:
            config.text = "Confidence"
            config.secondaryText = String(format: "%.2f", record.rawConfidence)
        case 3:
            config.text = "Coverage"
            config.secondaryText = String(format: "%.1f%%", record.rawCoveragePct)
        case 4:
            config.text = "Quality"
            config.secondaryText = record.qualityResult
        case 5:
            config.text = "Fallback Reason"
            config.secondaryText = record.fallbackReason ?? "none"
        case 6:
            config.text = "Chained"
            config.secondaryText = record.chainedSegmenterUsed ? "Yes" : "No"
        default:
            break
        }
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Recent Captures Section

    private func recentCaptureCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let recentRecords = Array(telemetryRecords.suffix(10).reversed())
        guard indexPath.row < recentRecords.count else {
            config.text = "No captures"
            cell.contentConfiguration = config
            cell.selectionStyle = .none
            return cell
        }

        let record = recentRecords[indexPath.row]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let time = dateFormatter.string(from: record.timestamp)
        let model = record.segmenterIdentifier.count > 20
            ? String(record.segmenterIdentifier.suffix(18))
            : record.segmenterIdentifier
        let latency = String(format: "%.0fms", record.inferenceLatencyMs)
        config.text = "\(time)  \(model)  \(record.qualityResult)  \(latency)"
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Wound Type Section

    private func woundTypeCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let allCases = Array(WoundType.allCases)
        guard indexPath.row < allCases.count else { return cell }
        let woundType = allCases[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = woundType.rawValue
        config.textProperties.font = .systemFont(ofSize: 14)
        cell.contentConfiguration = config
        cell.accessoryType = woundType == WoundTypeOverride.current ? .checkmark : .none
        return cell
    }
}
#endif
