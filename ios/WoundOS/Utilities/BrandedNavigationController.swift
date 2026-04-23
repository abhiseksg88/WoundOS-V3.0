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
        container.spacing = 6
        container.alignment = .center

        let imageView = UIImageView(image: UIImage(named: "WoundOSLogo")?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
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
