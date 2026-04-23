import Foundation

// MARK: - Developer Mode

/// Runtime developer mode gate for TestFlight / internal dogfooding builds.
///
/// Activated via 5-tap gesture on the "Wound Scans" nav title.
/// Persisted in UserDefaults across app launches.
/// No visible UI affordance — invisible to end users who don't know the gesture.
///
/// Use `DeveloperMode.isEnabled` instead of `#if DEBUG` for developer UI
/// that must be reachable in Release (TestFlight) builds.
public enum DeveloperMode {
    private static let key = "com.woundos.developerMode.enabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public static func enable() {
        UserDefaults.standard.set(true, forKey: key)
    }

    public static func disable() {
        UserDefaults.standard.set(false, forKey: key)
    }

    public static func toggle() {
        UserDefaults.standard.set(!isEnabled, forKey: key)
    }
}
