import UIKit
import Combine
import WoundClinical

// MARK: - Patient List View Controller

/// Apple Health-style patient list with search and grouped sections.
final class PatientListViewController: UIViewController {

    private let viewModel: PatientListViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Search patients..."
        return sc
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PatientCell.self, forCellReuseIdentifier: PatientCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.refreshControl = refreshControl
        tv.backgroundColor = WOColors.screenBackground
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
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

        let icon = UIImageView(image: UIImage(systemName: "person.2"))
        icon.tintColor = WOColors.tertiaryText
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "No Patients"
        titleLabel.font = WOFonts.title3
        titleLabel.textColor = WOColors.secondaryText
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Add your first patient to get started\nwith clinical documentation."
        subtitleLabel.font = WOFonts.subheadline
        subtitleLabel.textColor = WOColors.tertiaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let addButton = UIButton(type: .system)
        addButton.setTitle("Add Patient", for: .normal)
        addButton.titleLabel?.font = WOFonts.bodyBold
        addButton.setTitleColor(.white, for: .normal)
        addButton.backgroundColor = WOColors.primaryGreen
        addButton.layer.cornerRadius = 12
        addButton.layer.cornerCurve = .continuous
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addPatientTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel, addButton])
        stack.axis = .vertical
        stack.spacing = WOSpacing.md
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            addButton.widthAnchor.constraint(equalToConstant: 200),
            addButton.heightAnchor.constraint(equalToConstant: 44),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: WOSpacing.xxxl),
        ])

        return container
    }()

    // MARK: - Init

    init(viewModel: PatientListViewModel) {
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
        viewModel.loadPatients()
    }

    func refreshData() {
        viewModel.loadPatients()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPatientTapped)
        )

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
        viewModel.$activePatients
            .combineLatest(viewModel.$inactivePatients)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active, inactive in
                self?.tableView.reloadData()
                self?.emptyStateView.isHidden = !(active.isEmpty && inactive.isEmpty)
                self?.refreshControl.endRefreshing()
            }
            .store(in: &cancellables)
    }

    @objc private func refreshPulled() {
        viewModel.loadPatients()
    }

    @objc private func addPatientTapped() {
        viewModel.addPatient()
    }
}

// MARK: - UISearchResultsUpdating

extension PatientListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
        viewModel.loadPatients()
    }
}

// MARK: - UITableViewDataSource

extension PatientListViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        var sections = 0
        if !viewModel.activePatients.isEmpty { sections += 1 }
        if !viewModel.inactivePatients.isEmpty { sections += 1 }
        return max(sections, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !viewModel.activePatients.isEmpty && section == 0 {
            return "Active Patients"
        }
        if !viewModel.inactivePatients.isEmpty {
            return "Inactive Patients"
        }
        return nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !viewModel.activePatients.isEmpty && section == 0 {
            return viewModel.activePatients.count
        }
        if !viewModel.inactivePatients.isEmpty {
            return viewModel.inactivePatients.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PatientCell.reuseId,
            for: indexPath
        ) as? PatientCell else {
            return UITableViewCell()
        }

        let patient: Patient
        if !viewModel.activePatients.isEmpty && indexPath.section == 0 {
            patient = viewModel.activePatients[indexPath.row]
        } else {
            patient = viewModel.inactivePatients[indexPath.row]
        }

        cell.configure(with: patient)
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        if editingStyle == .delete {
            let isActive = !viewModel.activePatients.isEmpty && indexPath.section == 0
            viewModel.deletePatient(at: indexPath.row, isActive: isActive)
        }
    }
}

// MARK: - UITableViewDelegate

extension PatientListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let patient: Patient
        if !viewModel.activePatients.isEmpty && indexPath.section == 0 {
            patient = viewModel.activePatients[indexPath.row]
        } else {
            patient = viewModel.inactivePatients[indexPath.row]
        }

        viewModel.selectPatient(patient)
    }
}
