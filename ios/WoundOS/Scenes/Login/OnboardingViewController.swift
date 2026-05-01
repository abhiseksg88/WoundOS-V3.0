import UIKit

protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingDidComplete()
}

final class OnboardingViewController: UIViewController {

    weak var delegate: OnboardingViewControllerDelegate?

    private let userName: String

    private struct Page {
        let icon: String
        let iconColor: UIColor
        let title: String
        let subtitle: String
    }

    private let pages: [Page]

    private var currentPage = 0

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.bounces = false
        return sv
    }()

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.currentPageIndicatorTintColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
        pc.pageIndicatorTintColor = UIColor.tertiaryLabel
        return pc
    }()

    private let skipButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Skip"
        config.baseForegroundColor = .secondaryLabel
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            return outgoing
        }
        return UIButton(configuration: config)
    }()

    private let nextButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Next"
        config.baseBackgroundColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 48, bottom: 16, trailing: 48)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        return UIButton(configuration: config)
    }()

    // MARK: - Init

    init(userName: String) {
        self.userName = userName
        let firstName = userName.components(separatedBy: " ").first ?? userName
        self.pages = [
            Page(
                icon: "camera.viewfinder",
                iconColor: UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0),
                title: "Capture",
                subtitle: "LiDAR-powered 3D wound scanning\nin seconds"
            ),
            Page(
                icon: "ruler",
                iconColor: .systemTeal,
                title: "Measure",
                subtitle: "Length, width, depth, area, volume\nall automated with clinical precision"
            ),
            Page(
                icon: "doc.text.fill",
                iconColor: .systemIndigo,
                title: "Document",
                subtitle: "PUSH scores, wound bed assessment,\nand clinical notes in one flow"
            ),
            Page(
                icon: "checkmark.circle.fill",
                iconColor: UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0),
                title: "Welcome, \(firstName)",
                subtitle: "Your wound care workflow\nstarts here"
            ),
        ]
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
        pageControl.numberOfPages = pages.count
        updateButtonForPage(0)
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self

        view.addSubview(skipButton)
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -24),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -24),

            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
    }

    private func layoutPages() {
        scrollView.subviews.forEach { $0.removeFromSuperview() }

        let pageWidth = scrollView.bounds.width
        let pageHeight = scrollView.bounds.height

        guard pageWidth > 0, pageHeight > 0 else { return }

        scrollView.contentSize = CGSize(width: pageWidth * CGFloat(pages.count), height: pageHeight)

        for (index, page) in pages.enumerated() {
            let pageView = makePageView(page: page)
            pageView.frame = CGRect(
                x: pageWidth * CGFloat(index),
                y: 0,
                width: pageWidth,
                height: pageHeight
            )
            scrollView.addSubview(pageView)
        }
    }

    private func makePageView(page: Page) -> UIView {
        let container = UIView()

        let iconBackground = UIView()
        iconBackground.backgroundColor = page.iconColor.withAlphaComponent(0.1)
        iconBackground.layer.cornerRadius = 44
        iconBackground.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: page.icon))
        iconView.tintColor = page.iconColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = page.title
        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = page.subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconBackground.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconBackground.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -80),
            iconBackground.widthAnchor.constraint(equalToConstant: 88),
            iconBackground.heightAnchor.constraint(equalToConstant: 88),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),
        ])

        return container
    }

    // MARK: - Actions

    private func setupActions() {
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
    }

    @objc private func skipTapped() {
        complete()
    }

    @objc private func nextTapped() {
        if currentPage == pages.count - 1 {
            complete()
        } else {
            let nextPage = currentPage + 1
            let offset = CGFloat(nextPage) * scrollView.bounds.width
            scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
        }
    }

    private func complete() {
        delegate?.onboardingDidComplete()
    }

    private func updateButtonForPage(_ page: Int) {
        currentPage = page
        pageControl.currentPage = page

        let isLast = page == pages.count - 1

        UIView.animate(withDuration: 0.25) {
            self.skipButton.alpha = isLast ? 0 : 1
        }

        if isLast {
            nextButton.configuration?.title = "Get Started"
            nextButton.configuration?.image = UIImage(systemName: "arrow.right")
            nextButton.configuration?.imagePlacement = .trailing
            nextButton.configuration?.imagePadding = 8
        } else {
            nextButton.configuration?.title = "Next"
            nextButton.configuration?.image = nil
        }
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        let clampedPage = max(0, min(page, pages.count - 1))
        if clampedPage != currentPage {
            updateButtonForPage(clampedPage)
        }
    }
}
