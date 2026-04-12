import UIKit

// MARK: - Coordinator Protocol

/// MVVM-C coordinator pattern. Each coordinator owns a navigation controller
/// and manages the flow between screens in its domain.
public protocol Coordinator: AnyObject {
    var navigationController: UINavigationController { get }
    var childCoordinators: [Coordinator] { get set }
    func start()
}

extension Coordinator {

    /// Add a child coordinator and retain it.
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }

    /// Remove a child coordinator when its flow is complete.
    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}
