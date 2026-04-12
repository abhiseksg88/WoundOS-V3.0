import UIKit
import Combine
import WoundCore

// MARK: - Scan List View Controller

/// Displays a list of all wound scans for a patient.
/// Shows key measurements, upload status, and agreement badges.
final class ScanListViewController: UIViewController {

    private let viewModel: ScanListViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ScanCell.self, forCellReuseIdentifier: ScanCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.refreshControl = refreshControl
        return tv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return rc
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No scans yet.\nCapture your first wound scan."
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // MARK: - Init

    init(viewModel: ScanListViewModel) {
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
        viewModel.loadScans()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$scans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scans in
                self?.tableView.reloadData()
                self?.emptyLabel.isHidden = !scans.isEmpty
                self?.refreshControl.endRefreshing()
            }
            .store(in: &cancellables)
    }

    @objc private func refreshPulled() {
        viewModel.loadScans()
    }
}

// MARK: - UITableViewDataSource

extension ScanListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.scans.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ScanCell.reuseId, for: indexPath) as! ScanCell
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

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        88
    }
}
