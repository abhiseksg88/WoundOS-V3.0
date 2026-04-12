import UIKit
import Combine

// MARK: - Measurement Result View Controller

/// Displays all computed wound measurements, PUSH score,
/// and save/upload actions.
final class MeasurementResultViewController: UIViewController {

    private let viewModel: MeasurementResultViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        return stack
    }()

    private lazy var saveButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Save & Upload"
        config.image = UIImage(systemName: "arrow.up.circle")
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseBackgroundColor = .systemBlue
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Init

    init(viewModel: MeasurementResultViewModel) {
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

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -16),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            saveButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Build measurement cards
        let headerLabel = makeSectionHeader("Wound Measurements")
        contentStack.addArrangedSubview(headerLabel)

        contentStack.addArrangedSubview(makeMeasurementRow("Area", viewModel.areaCm2))
        contentStack.addArrangedSubview(makeMeasurementRow("Max Depth", viewModel.maxDepthMm))
        contentStack.addArrangedSubview(makeMeasurementRow("Mean Depth", viewModel.meanDepthMm))
        contentStack.addArrangedSubview(makeMeasurementRow("Volume", viewModel.volumeMl))
        contentStack.addArrangedSubview(makeMeasurementRow("Length", viewModel.lengthMm))
        contentStack.addArrangedSubview(makeMeasurementRow("Width", viewModel.widthMm))
        contentStack.addArrangedSubview(makeMeasurementRow("Perimeter", viewModel.perimeterMm))

        contentStack.addArrangedSubview(makeSeparator())

        let pushHeader = makeSectionHeader("PUSH Score 3.0")
        contentStack.addArrangedSubview(pushHeader)
        contentStack.addArrangedSubview(makeMeasurementRow("Total Score", viewModel.pushTotalScore))
        contentStack.addArrangedSubview(makeMeasurementRow("Breakdown", viewModel.pushBreakdown))

        contentStack.addArrangedSubview(makeSeparator())

        let metaHeader = makeSectionHeader("Capture Info")
        contentStack.addArrangedSubview(metaHeader)
        contentStack.addArrangedSubview(makeMeasurementRow("Processing Time", viewModel.processingTime))
        contentStack.addArrangedSubview(makeMeasurementRow("Computed", "On Device"))
    }

    // MARK: - UI Helpers

    private func makeSectionHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        return label
    }

    private func makeMeasurementRow(_ label: String, _ value: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 10

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = .systemFont(ofSize: 15, weight: .regular)
        nameLabel.textColor = .secondaryLabel
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(nameLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            container.heightAnchor.constraint(equalToConstant: 48),
        ])

        return container
    }

    private func makeSeparator() -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        view.backgroundColor = .separator
        return view
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$isSaving
            .receive(on: DispatchQueue.main)
            .sink { [weak self] saving in
                self?.saveButton.isEnabled = !saving
                self?.saveButton.configuration?.showsActivityIndicator = saving
            }
            .store(in: &cancellables)

        viewModel.$saveError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                let alert = UIAlertController(title: "Save Error", message: error, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        viewModel.saveAndUpload()
    }
}
