import UIKit

// MARK: - Branded Navigation Controller

/// UINavigationController subclass that automatically sets a logo + "WoundOS"
/// title view on every pushed view controller. Ensures consistent branding
/// across all screens without modifying individual view controllers.
final class BrandedNavigationController: UINavigationController {

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        viewControllers.forEach { applyBrandedTitle(to: $0) }
        super.setViewControllers(viewControllers, animated: animated)
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        applyBrandedTitle(to: viewController)
        super.pushViewController(viewController, animated: animated)
    }

    // MARK: - Branded Title View

    private func applyBrandedTitle(to viewController: UIViewController) {
        // Don't override if a custom titleView is already set
        guard viewController.navigationItem.titleView == nil else { return }

        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 8
        container.alignment = .center

        // Logo — template rendering so it tints with .label color (visible on any background)
        let imageView = UIImageView(image: UIImage(named: "WoundOSLogo")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let logoHeight: CGFloat = 17
        let logoAspect: CGFloat = 440.0 / 138.0
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: logoHeight),
            imageView.widthAnchor.constraint(equalToConstant: logoHeight * logoAspect),
        ])

        let label = UILabel()
        label.text = "WoundOS"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label

        container.addArrangedSubview(imageView)
        container.addArrangedSubview(label)

        viewController.navigationItem.titleView = container
    }
}
