import UIKit
import CaptureSync

protocol LoginViewControllerDelegate: AnyObject {
    func loginDidSucceed(user: VerifiedUser)
}

final class LoginViewController: UIViewController {

    // MARK: - Properties

    weak var delegate: LoginViewControllerDelegate?

    private let keychain: ClinicalPlatformKeychain
    private let client: ClinicalPlatformClient
    private var isLoggingIn = false

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.keyboardDismissMode = .interactive
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let contentView = UIView()

    private let gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.colors = [
            UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0).cgColor,
            UIColor(red: 0.15, green: 0.68, blue: 0.38, alpha: 1.0).cgColor,
        ]
        gl.startPoint = CGPoint(x: 0, y: 0)
        gl.endPoint = CGPoint(x: 1, y: 1)
        return gl
    }()

    private let headerView = UIView()

    private let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(named: "WoundOSLogo")?.withRenderingMode(.alwaysTemplate)
        iv.tintColor = .white
        return iv
    }()

    private let taglineLabel: UILabel = {
        let label = UILabel()
        label.text = "Clinical Wound Intelligence"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        return label
    }()

    private let formCard: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 24
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.08
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
        v.layer.shadowRadius = 16
        return v
    }()

    private let welcomeLabel: UILabel = {
        let label = UILabel()
        label.text = "Sign in to continue"
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private lazy var idFieldContainer: UIView = makeFieldContainer(
        icon: "person.fill",
        field: carePlixIdField
    )

    private lazy var passcodeFieldContainer: UIView = makeFieldContainer(
        icon: "lock.fill",
        field: passcodeField
    )

    private let carePlixIdField: UITextField = {
        let field = UITextField()
        field.placeholder = "CarePlix ID"
        field.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .asciiCapable
        field.returnKeyType = .next
        field.borderStyle = .none
        return field
    }()

    private let passcodeField: UITextField = {
        let field = UITextField()
        field.placeholder = "Passcode"
        field.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        field.isSecureTextEntry = true
        field.returnKeyType = .go
        field.borderStyle = .none
        return field
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Sign In"
        config.baseBackgroundColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: config)
        return button
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        return s
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let lidarBadge: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor.secondarySystemFill

        container.layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(systemName: "eye.fill"))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Powered by CarePlix Vision 3.0"
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        return container
    }()

    private let versionLabel: UILabel = {
        let label = UILabel()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        label.text = "v\(version) (\(build))"
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        return label
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
        view.backgroundColor = .systemBackground
        setupLayout()
        setupActions()
        prepareEntranceAnimation()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        runEntranceAnimation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = headerView.bounds
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false
        formCard.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        taglineLabel.translatesAutoresizingMaskIntoConstraints = false
        welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        idFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        passcodeFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        lidarBadge.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        headerView.layer.insertSublayer(gradientLayer, at: 0)
        contentView.addSubview(headerView)
        headerView.addSubview(logoImageView)
        headerView.addSubview(taglineLabel)

        contentView.addSubview(formCard)
        formCard.addSubview(welcomeLabel)
        formCard.addSubview(idFieldContainer)
        formCard.addSubview(passcodeFieldContainer)
        formCard.addSubview(errorLabel)
        formCard.addSubview(loginButton)
        loginButton.addSubview(spinner)

        contentView.addSubview(lidarBadge)
        contentView.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Green gradient header
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 280),

            logoImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 80),
            logoImageView.widthAnchor.constraint(equalToConstant: 200),
            logoImageView.heightAnchor.constraint(equalToConstant: 52),

            taglineLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 8),
            taglineLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),

            // Form card overlapping the header
            formCard.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -40),
            formCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            formCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            welcomeLabel.topAnchor.constraint(equalTo: formCard.topAnchor, constant: 32),
            welcomeLabel.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 24),
            welcomeLabel.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -24),

            idFieldContainer.topAnchor.constraint(equalTo: welcomeLabel.bottomAnchor, constant: 28),
            idFieldContainer.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 24),
            idFieldContainer.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -24),
            idFieldContainer.heightAnchor.constraint(equalToConstant: 52),

            passcodeFieldContainer.topAnchor.constraint(equalTo: idFieldContainer.bottomAnchor, constant: 12),
            passcodeFieldContainer.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 24),
            passcodeFieldContainer.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -24),
            passcodeFieldContainer.heightAnchor.constraint(equalToConstant: 52),

            errorLabel.topAnchor.constraint(equalTo: passcodeFieldContainer.bottomAnchor, constant: 12),
            errorLabel.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -24),

            loginButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
            loginButton.leadingAnchor.constraint(equalTo: formCard.leadingAnchor, constant: 24),
            loginButton.trailingAnchor.constraint(equalTo: formCard.trailingAnchor, constant: -24),
            loginButton.heightAnchor.constraint(equalToConstant: 52),
            loginButton.bottomAnchor.constraint(equalTo: formCard.bottomAnchor, constant: -28),

            spinner.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: -20),

            // Footer
            lidarBadge.topAnchor.constraint(equalTo: formCard.bottomAnchor, constant: 32),
            lidarBadge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: lidarBadge.bottomAnchor, constant: 12),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
        ])
    }

    private func makeFieldContainer(icon: String, field: UITextField) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(field)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    // MARK: - Entrance Animation

    private func prepareEntranceAnimation() {
        logoImageView.alpha = 0
        logoImageView.transform = CGAffineTransform(translationX: 0, y: -20)
        taglineLabel.alpha = 0
        formCard.alpha = 0
        formCard.transform = CGAffineTransform(translationX: 0, y: 30)
        lidarBadge.alpha = 0
        versionLabel.alpha = 0
    }

    private func runEntranceAnimation() {
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: []) {
            self.logoImageView.alpha = 1
            self.logoImageView.transform = .identity
        }

        UIView.animate(withDuration: 0.5, delay: 0.3, options: .curveEaseOut) {
            self.taglineLabel.alpha = 1
        }

        UIView.animate(withDuration: 0.6, delay: 0.4, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
            self.formCard.alpha = 1
            self.formCard.transform = .identity
        } completion: { _ in
            self.carePlixIdField.becomeFirstResponder()
        }

        UIView.animate(withDuration: 0.4, delay: 0.7, options: .curveEaseOut) {
            self.lidarBadge.alpha = 1
            self.versionLabel.alpha = 1
        }
    }

    // MARK: - Actions

    private func setupActions() {
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        carePlixIdField.delegate = self
        passcodeField.delegate = self

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func loginTapped() {
        performLogin()
    }

    private func performLogin() {
        let carePlixId = carePlixIdField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let passcode = passcodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !carePlixId.isEmpty else {
            showError("Please enter your CarePlix ID")
            shakeField(idFieldContainer)
            return
        }
        guard !passcode.isEmpty else {
            showError("Please enter your Passcode")
            shakeField(passcodeFieldContainer)
            return
        }

        guard !isLoggingIn else { return }
        isLoggingIn = true
        setLoading(true)
        errorLabel.isHidden = true

        CrashLogger.shared.log("Login attempt - carePlixId=\(carePlixId)", category: .network)

        let baseURL = ClinicalPlatformClient.defaultBaseURL

        Task { @MainActor in
            do {
                let response = try await client.login(
                    carePlixId: carePlixId,
                    passcode: passcode,
                    baseURL: baseURL
                )

                try keychain.saveToken(response.token)
                try keychain.saveBaseURL(baseURL.absoluteString)

                let user = VerifiedUser(
                    userId: response.user.id,
                    name: response.user.name,
                    email: response.user.email,
                    role: response.user.role,
                    facilityId: response.user.facilityId,
                    tokenLabel: carePlixId
                )
                try keychain.saveVerifiedUser(user)

                CrashLogger.shared.log("Login succeeded - userId=\(user.userId), name=\(user.name)", category: .network)

                isLoggingIn = false
                setLoading(false)

                UIView.animate(withDuration: 0.15) {
                    self.loginButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
                } completion: { _ in
                    UIView.animate(withDuration: 0.15) {
                        self.loginButton.transform = .identity
                    } completion: { _ in
                        self.delegate?.loginDidSucceed(user: user)
                    }
                }
            } catch let error as ClinicalPlatformError {
                CrashLogger.shared.error("Login failed", category: .network, error: error)
                isLoggingIn = false
                setLoading(false)
                showError(error.errorDescription ?? "Login failed")
                shakeField(formCard)
            } catch {
                CrashLogger.shared.error("Login failed (unexpected)", category: .network, error: error)
                isLoggingIn = false
                setLoading(false)
                showError("Connection error. Please check your network and try again.")
            }
        }
    }

    // MARK: - UI Helpers

    private func setLoading(_ loading: Bool) {
        loginButton.isEnabled = !loading
        carePlixIdField.isEnabled = !loading
        passcodeField.isEnabled = !loading

        if loading {
            loginButton.configuration?.title = "Signing In..."
            spinner.startAnimating()
        } else {
            loginButton.configuration?.title = "Sign In"
            spinner.stopAnimating()
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        errorLabel.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.errorLabel.alpha = 1
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func shakeField(_ view: UIView) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-8, 8, -6, 6, -3, 3, 0]
        view.layer.add(animation, forKey: "shake")
    }
}

// MARK: - UITextFieldDelegate

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == carePlixIdField {
            passcodeField.becomeFirstResponder()
        } else if textField == passcodeField {
            performLogin()
        }
        return true
    }
}
