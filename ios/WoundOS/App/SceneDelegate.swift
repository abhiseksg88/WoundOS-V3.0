import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let container = DependencyContainer()
        let navigationController = UINavigationController()

        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            dependencies: container
        )
        appCoordinator?.start()

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
