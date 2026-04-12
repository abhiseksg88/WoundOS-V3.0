import UIKit
import Combine
import WoundCore
import WoundBoundary

// MARK: - Boundary Drawing View Controller

/// Displays the frozen captured image with a drawing canvas overlay.
/// Nurse first taps wound center, then draws boundary around the wound.
final class BoundaryDrawingViewController: UIViewController {

    private let viewModel: BoundaryDrawingViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = .black
        return iv
    }()

    private lazy var canvasView: BoundaryCanvasView = {
        let canvas = BoundaryCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.delegate = self
        return canvas
    }()

    private lazy var instructionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        return label
    }()

    private lazy var modeToggle: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Polygon", "Freeform"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    private lazy var toolbar: UIStackView = {
        let undoButton = makeToolbarButton(title: "Undo", icon: "arrow.uturn.backward", action: #selector(undoTapped))
        let clearButton = makeToolbarButton(title: "Clear", icon: "trash", action: #selector(clearTapped))
        let confirmButton = makeToolbarButton(title: "Measure", icon: "checkmark.circle.fill", action: #selector(confirmTapped))
        confirmButton.tintColor = .systemGreen

        let stack = UIStackView(arrangedSubviews: [undoButton, clearButton, modeToggle, confirmButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()

    // MARK: - Init

    init(viewModel: BoundaryDrawingViewModel) {
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
        imageView.image = viewModel.capturedImage
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(imageView)
        view.addSubview(canvasView)
        view.addSubview(instructionLabel)
        view.addSubview(toolbar)
        view.addSubview(errorLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),

            canvasView.topAnchor.constraint(equalTo: imageView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.heightAnchor.constraint(equalToConstant: 36),

            errorLabel.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -4),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 50),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func makeToolbarButton(title: String, icon: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.title = title
        config.imagePadding = 4
        config.preferredSymbolConfigurationForImage = .init(pointSize: 16)
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Bindings

    private func bindViewModel() {
        viewModel.$drawingMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.canvasView.drawingMode = mode
                self?.instructionLabel.text = "  \(self?.viewModel.instructionText ?? "")  "
            }
            .store(in: &cancellables)

        viewModel.$validationErrors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errors in
                if errors.isEmpty {
                    self?.errorLabel.isHidden = true
                } else {
                    self?.errorLabel.isHidden = false
                    self?.errorLabel.text = errors.map(\.localizedDescription).joined(separator: "\n")
                }
            }
            .store(in: &cancellables)

        viewModel.$isComputing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] computing in
                if computing {
                    self?.activityIndicator.startAnimating()
                    self?.canvasView.isUserInteractionEnabled = false
                } else {
                    self?.activityIndicator.stopAnimating()
                    self?.canvasView.isUserInteractionEnabled = true
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        viewModel.drawingMode = modeToggle.selectedSegmentIndex == 0 ? .polygon : .freeform
    }

    @objc private func undoTapped() {
        canvasView.undoLastVertex()
    }

    @objc private func clearTapped() {
        canvasView.clearAll()
        viewModel.clearBoundary()
    }

    @objc private func confirmTapped() {
        guard viewModel.boundaryFinalized else { return }
        showPUSHInputSheet()
    }

    // MARK: - PUSH Input Sheet

    private func showPUSHInputSheet() {
        let alert = UIAlertController(
            title: "Clinical Assessment",
            message: "Please enter wound assessment details for PUSH scoring",
            preferredStyle: .actionSheet
        )

        // For production, this would be a proper form.
        // Here we use a simplified input via action sheets.
        alert.addAction(UIAlertAction(title: "Enter Assessment", style: .default) { [weak self] _ in
            self?.viewModel.computeMeasurements(
                patientId: "patient-001",  // From session context
                nurseId: "nurse-001",      // From auth
                facilityId: "facility-001", // From auth
                exudateAmount: .moderate,  // From nurse input
                tissueType: .granulation   // From nurse input
            )
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - BoundaryCanvasDelegate

extension BoundaryDrawingViewController: BoundaryCanvasDelegate {

    func canvasDidPlaceTapPoint(_ point: CGPoint) {
        viewModel.didPlaceTapPoint(point, in: canvasView.bounds.size)
    }

    func canvasDidUpdateBoundary(_ points: [CGPoint]) {
        viewModel.didUpdateBoundary(points, in: canvasView.bounds.size)
    }

    func canvasDidFinalizeBoundary(_ points: [CGPoint]) {
        viewModel.didFinalizeBoundary(points, in: canvasView.bounds.size)
    }

    func canvasDidClearBoundary() {
        viewModel.clearBoundary()
    }
}
