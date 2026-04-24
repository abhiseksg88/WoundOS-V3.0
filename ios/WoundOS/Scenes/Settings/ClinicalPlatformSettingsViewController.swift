import UIKit
import CaptureSync

final class ClinicalPlatformSettingsViewController: UIViewController {

    private let keychain: ClinicalPlatformKeychain
    private let client: ClinicalPlatformClient

    // MARK: - UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WOSpacing.lg
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var baseURLField: UITextField = {
        let tf = makeTextField(placeholder: "API Base URL")
        tf.text = keychain.loadBaseURL() ?? "https://wound-os.replit.app"
        tf.keyboardType = .URL
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        return tf
    }()

    private lazy var tokenField: UITextField = {
        let tf = makeTextField(placeholder: "API Token (cpx_...)")
        tf.isSecureTextEntry = true
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        if keychain.loadToken() != nil {
            tf.text = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
        }
        return tf
    }()

    private lazy var testConnectionButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Test Connection"
        config.baseBackgroundColor = WOColors.primaryGreen
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(testConnectionTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var statusCard: UIView = {
        let card = WOCardView()
        card.isHidden = true
        return card
    }()

    private lazy var statusIcon: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 24)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private lazy var statusLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = WOFonts.body
        lbl.textColor = WOColors.primaryText
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private lazy var statusDetailLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = WOFonts.footnote
        lbl.textColor = WOColors.secondaryText
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private lazy var signOutButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Sign Out"
        config.baseForegroundColor = WOColors.flagRed
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        btn.isHidden = true
        return btn
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var helpLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Enter your Clinical Platform API token to enable automatic upload of wound captures. Tokens are stored securely in the iOS Keychain."
        lbl.font = WOFonts.footnote
        lbl.textColor = WOColors.tertiaryText
        lbl.numberOfLines = 0
        return lbl
    }()

    // MARK: - Init

    init(keychain: ClinicalPlatformKeychain, client: ClinicalPlatformClient) {
        self.keychain = keychain
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clinical Platform"
        view.backgroundColor = WOColors.screenBackground
        setupUI()
        loadSavedState()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let urlSection = makeSection(title: "API CONFIGURATION", views: [baseURLField, tokenField])
        let actionSection = makeSection(title: nil, views: [testConnectionButton])

        setupStatusCard()

        contentStack.addArrangedSubview(urlSection)
        contentStack.addArrangedSubview(actionSection)
        contentStack.addArrangedSubview(statusCard)
        contentStack.addArrangedSubview(signOutButton)
        contentStack.addArrangedSubview(helpLabel)

        let padding = WOSpacing.lg

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: padding),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -padding),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -padding),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -padding * 2),

            baseURLField.heightAnchor.constraint(equalToConstant: 44),
            tokenField.heightAnchor.constraint(equalToConstant: 44),
            testConnectionButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupStatusCard() {
        let stack = UIStackView(arrangedSubviews: [statusIcon, statusLabel])
        stack.axis = .horizontal
        stack.spacing = WOSpacing.sm
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusCard.addSubview(stack)
        statusCard.addSubview(statusDetailLabel)
        statusCard.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: WOSpacing.cardPaddingV),
            stack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: WOSpacing.cardPaddingH),
            stack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -WOSpacing.cardPaddingH),

            statusDetailLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: WOSpacing.sm),
            statusDetailLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: WOSpacing.cardPaddingH),
            statusDetailLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -WOSpacing.cardPaddingH),
            statusDetailLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -WOSpacing.cardPaddingV),

            activityIndicator.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -WOSpacing.cardPaddingH),
        ])
    }

    // MARK: - State

    private func loadSavedState() {
        if let user = keychain.loadVerifiedUser() {
            showConnectedState(user: user)
        }
    }

    private func showConnectedState(user: VerifiedUser) {
        statusCard.isHidden = false
        signOutButton.isHidden = false
        statusIcon.text = "\u{2705}"
        statusLabel.text = "Connected as \(user.name) (\(user.role))"
        var detail = "Facility: \(user.facilityId)"
        if let label = user.tokenLabel {
            detail += "\nToken: \(label)"
        }
        statusDetailLabel.text = detail
    }

    private func showErrorState(message: String) {
        statusCard.isHidden = false
        signOutButton.isHidden = true
        statusIcon.text = "\u{274C}"
        statusLabel.text = message
        statusDetailLabel.text = nil
    }

    // MARK: - Actions

    @objc private func testConnectionTapped() {
        view.endEditing(true)

        guard let urlString = baseURLField.text, !urlString.isEmpty,
              let baseURL = URL(string: urlString) else {
            showErrorState(message: "Invalid API URL")
            return
        }

        let token: String
        if let fieldText = tokenField.text,
           !fieldText.isEmpty,
           !fieldText.hasPrefix("\u{2022}") {
            token = fieldText
        } else if let stored = keychain.loadToken() {
            token = stored
        } else {
            showErrorState(message: "Please enter an API token")
            return
        }

        testConnectionButton.isEnabled = false
        activityIndicator.startAnimating()
        statusCard.isHidden = false
        statusIcon.text = ""
        statusLabel.text = "Testing connection..."
        statusDetailLabel.text = nil

        CrashLogger.shared.log("Testing Clinical Platform connection", category: .network)

        Task {
            do {
                let user = try await client.verify(token: token, baseURL: baseURL)

                try keychain.saveToken(token)
                try keychain.saveBaseURL(urlString)
                try keychain.saveVerifiedUser(user)

                tokenField.text = "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"

                CrashLogger.shared.log(
                    "Clinical Platform connected: \(user.name) (\(user.role)) at \(user.facilityId)",
                    category: .network
                )

                await MainActor.run {
                    activityIndicator.stopAnimating()
                    testConnectionButton.isEnabled = true
                    showConnectedState(user: user)
                }
            } catch let error as ClinicalPlatformError {
                CrashLogger.shared.log(
                    "Clinical Platform connection failed: \(error.localizedDescription)",
                    category: .network,
                    level: .warning
                )

                await MainActor.run {
                    activityIndicator.stopAnimating()
                    testConnectionButton.isEnabled = true

                    switch error {
                    case .unauthorized:
                        showErrorState(message: "Invalid or expired token")
                    case .networkError:
                        showErrorState(message: "Could not reach server")
                    default:
                        showErrorState(message: error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    activityIndicator.stopAnimating()
                    testConnectionButton.isEnabled = true
                    showErrorState(message: "Could not reach server: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func signOutTapped() {
        let alert = UIAlertController(
            title: "Sign Out",
            message: "This will clear your Clinical Platform token. Uploads will stop until you reconfigure.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.performSignOut()
        })
        present(alert, animated: true)
    }

    private func performSignOut() {
        keychain.deleteToken()
        keychain.deleteVerifiedUser()
        tokenField.text = nil
        statusCard.isHidden = true
        signOutButton.isHidden = true
        CrashLogger.shared.log("Signed out of Clinical Platform", category: .network)
    }

    // MARK: - Helpers

    private func makeTextField(placeholder: String) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.font = WOFonts.body
        tf.backgroundColor = WOColors.cardBackground
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    private func makeSection(title: String?, views: [UIView]) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WOSpacing.sm

        if let title {
            let header = UILabel()
            header.text = title
            header.font = WOFonts.sectionHeaderUppercase
            header.textColor = WOColors.secondaryText
            stack.addArrangedSubview(header)
        }

        for v in views {
            stack.addArrangedSubview(v)
        }

        return stack
    }
}
