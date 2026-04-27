import UIKit
import Combine
import WoundClinical

// MARK: - Dashboard View Controller

/// Home dashboard showing today's summary, pending work, and recent patients.
final class DashboardViewController: UIViewController {

    private let viewModel: DashboardViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        sv.refreshControl = rc
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WOSpacing.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // Summary cards
    private let scansCard = DashboardStatView(title: "Scans Today", icon: "camera.viewfinder")
    private let patientsCard = DashboardStatView(title: "Patients Seen", icon: "person.2")
    private let pendingDocsCard = DashboardStatView(title: "Pending Docs", icon: "doc.text")
    private let pendingUploadsCard = DashboardStatView(title: "Pending Uploads", icon: "icloud.and.arrow.up")

    private lazy var emptyPatientsLabel: UILabel = {
        let label = UILabel()
        label.text = "No patients yet. Add patients from the Patients tab."
        label.font = WOFonts.subheadline
        label.textColor = WOColors.tertiaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var patientsTableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PatientCell.self, forCellReuseIdentifier: PatientCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
        tv.layer.cornerRadius = WOSpacing.cardCornerRadius
        tv.layer.cornerCurve = .continuous
        tv.clipsToBounds = true
        return tv
    }()

    private var tableHeightConstraint: NSLayoutConstraint?

    // MARK: - Init

    init(viewModel: DashboardViewModel) {
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
        viewModel.loadDashboard()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = WOColors.screenBackground
        navigationController?.navigationBar.prefersLargeTitles = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: WOSpacing.lg),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: WOSpacing.lg),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -WOSpacing.lg),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -WOSpacing.xxxl),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -WOSpacing.lg * 2),
        ])

        // Summary grid
        let topRow = UIStackView(arrangedSubviews: [scansCard, patientsCard])
        topRow.axis = .horizontal
        topRow.spacing = WOSpacing.md
        topRow.distribution = .fillEqually

        let bottomRow = UIStackView(arrangedSubviews: [pendingDocsCard, pendingUploadsCard])
        bottomRow.axis = .horizontal
        bottomRow.spacing = WOSpacing.md
        bottomRow.distribution = .fillEqually

        let summaryHeader = WOSectionHeader(title: "Today's Summary")
        contentStack.addArrangedSubview(summaryHeader)
        contentStack.addArrangedSubview(topRow)
        contentStack.addArrangedSubview(bottomRow)

        // Patients section
        let patientsHeader = WOSectionHeader(title: "Recent Patients")
        contentStack.addArrangedSubview(patientsHeader)
        contentStack.addArrangedSubview(patientsTableView)
        contentStack.addArrangedSubview(emptyPatientsLabel)

        let heightConstraint = patientsTableView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        tableHeightConstraint = heightConstraint
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$summary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.scansCard.update(value: "\(summary.scansToday)")
                self?.patientsCard.update(value: "\(summary.patientsSeenToday)")
                self?.pendingDocsCard.update(value: "\(summary.pendingDocumentation)")
                self?.pendingUploadsCard.update(value: "\(summary.pendingUploads)")
            }
            .store(in: &cancellables)

        viewModel.$recentPatients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] patients in
                self?.patientsTableView.reloadData()
                self?.emptyPatientsLabel.isHidden = !patients.isEmpty
                self?.patientsTableView.isHidden = patients.isEmpty
                let rowHeight: CGFloat = 72
                self?.tableHeightConstraint?.constant = CGFloat(patients.count) * rowHeight
                self?.scrollView.refreshControl?.endRefreshing()
            }
            .store(in: &cancellables)
    }

    @objc private func refreshPulled() {
        viewModel.loadDashboard()
    }
}

// MARK: - UITableViewDataSource

extension DashboardViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.recentPatients.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PatientCell.reuseId, for: indexPath
        ) as? PatientCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.recentPatients[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DashboardViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.selectPatient(viewModel.recentPatients[indexPath.row])
    }
}

// MARK: - Dashboard Stat View

/// Card showing a single statistic with icon and title.
final class DashboardStatView: UIView {

    private let valueLabel = UILabel()

    init(title: String, icon: String) {
        super.init(frame: .zero)

        backgroundColor = WOColors.cardBackground
        layer.cornerRadius = WOSpacing.cardCornerRadius
        layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = WOColors.primaryGreen
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.text = "0"
        valueLabel.font = WOFonts.measurementValueLarge
        valueLabel.textColor = WOColors.primaryText

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = WOFonts.footnote
        titleLabel.textColor = WOColors.secondaryText

        let textStack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [iconView, textStack])
        mainStack.axis = .horizontal
        mainStack.spacing = WOSpacing.md
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: WOSpacing.lg),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WOSpacing.lg),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -WOSpacing.md),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -WOSpacing.lg),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(value: String) {
        valueLabel.text = value
    }
}
