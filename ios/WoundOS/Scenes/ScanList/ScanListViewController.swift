import UIKit
import Combine
import WoundCore

// MARK: - Scan List View Controller

/// Apple Health-style list of wound scans with large title navigation.
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
        view.backgroundColor = WOColors.screenBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

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
}
