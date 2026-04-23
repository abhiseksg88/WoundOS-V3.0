import Foundation
import WoundCore

// MARK: - Wound Type Override (Debug Only)

/// Debug-only wound type override for TestFlight testing.
/// Production builds always return `.unknown` (no override).
enum WoundTypeOverride {
    private static let key = "debug_wound_type_override"

    static var current: WoundType {
        get {
            #if DEBUG
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let woundType = WoundType(rawValue: raw) else {
                return .unknown
            }
            return woundType
            #else
            return .unknown
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            #endif
        }
    }
}
