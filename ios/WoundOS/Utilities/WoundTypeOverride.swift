import Foundation
import WoundCore

// MARK: - Wound Type Override (Debug Only)

/// Wound type override for TestFlight / internal testing.
/// Returns `.unknown` when DeveloperMode is off (no override applied).
/// Activated via DeveloperMode (5-tap on Scans title).
enum WoundTypeOverride {
    private static let key = "debug_wound_type_override"

    static var current: WoundType {
        get {
            guard DeveloperMode.isEnabled else { return .unknown }
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let woundType = WoundType(rawValue: raw) else {
                return .unknown
            }
            return woundType
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
