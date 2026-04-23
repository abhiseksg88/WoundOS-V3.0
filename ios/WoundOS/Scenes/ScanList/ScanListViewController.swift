import UIKit
import Combine
import WoundCore

// MARK: - Scan List View Controller

/// Apple Health-style list of wound scans with large title navigation.
final class ScanListViewController: UIViewController {

    private let viewModel: ScanListViewModel
    private let dependencies: DependencyContainer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ScanCell.self, forCellReuseIdentifier: ScanCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.refreshControl = refreshControl
        tv.backgroundColor = WOColors.screenBackground
        tv.separatorInset = UIEdgeInsets(top: 0, left: 84, bottom: 0, right: 0)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 88
        return tv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return rc
    }()

    private lazy var emptyStateView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true

        let icon = UIImageView(image: UIImage(systemName: "camera.viewfinder"))
        icon.tintColor = WOColors.tertiaryText
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "No Scans Yet"
        titleLabel.font = WOFonts.title3
        titleLabel.textColor = WOColors.secondaryText
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Capture your first wound scan\nusing the Capture tab."
        subtitleLabel.font = WOFonts.subheadline
        subtitleLabel.textColor = WOColors.tertiaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = WOSpacing.md
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: WOSpacing.xxxl),
        ])

        return container
    }()

    // MARK: - Init

    init(viewModel: ScanListViewModel, dependencies: DependencyContainer? = nil) {
        self.viewModel = viewModel
        self.dependencies = dependencies
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
        setupDeveloperModeGesture()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadScans()
        updateDebugButton()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationController?.navigationBar.prefersLargeTitles = false

        // "Share Logs" button for testers to export crash logs
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ladybug"),
            style: .plain,
            target: self,
            action: #selector(shareLogsTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Share Debug Logs"

        updateDebugButton()

        view.addSubview(tableView)
        view.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: view.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$scans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scans in
                self?.tableView.reloadData()
                self?.emptyStateView.isHidden = !scans.isEmpty
                self?.refreshControl.endRefreshing()
            }
            .store(in: &cancellables)
    }

    @objc private func refreshPulled() {
        viewModel.loadScans()
    }

    /// Show/hide gear icon based on DeveloperMode state.
    private func updateDebugButton() {
        if DeveloperMode.isEnabled {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: self,
                action: #selector(debugTapped)
            )
            navigationItem.leftBarButtonItem?.accessibilityLabel = "Segmenter Debug"
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    /// 5-tap on nav bar activates Developer Mode. No visible UI affordance.
    private func setupDeveloperModeGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(developerModeTapped))
        tap.numberOfTapsRequired = 5
        navigationController?.navigationBar.addGestureRecognizer(tap)
    }

    @objc private func developerModeTapped() {
        DeveloperMode.toggle()
        updateDebugButton()
        let state = DeveloperMode.isEnabled ? "ON" : "OFF"
        let alert = UIAlertController(
            title: "Developer Mode: \(state)",
            message: DeveloperMode.isEnabled
                ? "Gear icon added. Restart capture flow for full effect."
                : "Developer tools hidden.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func debugTapped() {
        guard let deps = dependencies else { return }
        let debugVC = SegmenterDebugViewController(dependencies: deps)
        let nav = UINavigationController(rootViewController: debugVC)
        present(nav, animated: true)
    }

    @objc private func shareLogsTapped() {
        CrashLogger.shared.log("User tapped Share Logs", category: .app)

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
            activityVC.popoverPresentationController?.barButtonItem = self?.navigationItem.rightBarButtonItem
            self?.present(activityVC, animated: true)
        })

        alert.addAction(UIAlertAction(title: "Copy Logs to Clipboard", style: .default) { _ in
            let logText = CrashLogger.shared.exportLogs()
            UIPasteboard.general.string = logText
            CrashLogger.shared.log("Logs copied to clipboard (\(logText.count) chars)", category: .app)
        })

        alert.addAction(UIAlertAction(title: "Clear All Logs", style: .destructive) { _ in
            CrashLogger.shared.clearLogs()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ScanListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.scans.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ScanCell.reuseId, for: indexPath) as? ScanCell,
              indexPath.row < viewModel.scans.count else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.scans[indexPath.row])
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        if editingStyle == .delete {
            viewModel.deleteScan(at: indexPath.row)
        }
    }
}

// MARK: - UITableViewDelegate

extension ScanListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.selectScan(viewModel.scans[indexPath.row])
    }
}
