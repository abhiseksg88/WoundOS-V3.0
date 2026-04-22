import Foundation

// MARK: - Feature Flag Definitions

/// All V5 feature flags. Each flag gates a distinct V5 capability.
/// Default value for all flags is `false` (OFF).
public enum FeatureFlag: String, CaseIterable, Sendable {
    case v5LidarCapture       = "v5_lidar_capture_enabled"
    case onDeviceSegmentation = "v5_on_device_segmentation_enabled"
    case tissueClassification = "v5_tissue_classification_enabled"
    case scanMode             = "v5_scan_mode_enabled"
    case medgemmaNarrative    = "v5_medgemma_narrative_enabled"
    case healthkitSync        = "v5_healthkit_sync_enabled"
}

// MARK: - Abstract Store Protocol

/// Protocol-backed feature flag store. Swap implementations to change
/// the backing store (UserDefaults, Firebase Remote Config, etc.)
/// without touching any call sites.
public protocol FeatureFlagStore: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
    func setEnabled(_ flag: FeatureFlag, _ value: Bool)
}

// MARK: - UserDefaults Backing Store

public final class UserDefaultsFlagStore: FeatureFlagStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        defaults.bool(forKey: flag.rawValue)
    }

    public func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        defaults.set(value, forKey: flag.rawValue)
    }
}

// MARK: - In-Memory Store (Test Double)

public final class InMemoryFlagStore: FeatureFlagStore, @unchecked Sendable {
    private var flags: [FeatureFlag: Bool] = [:]

    public init() {}

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        flags[flag] ?? false
    }

    public func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        flags[flag] = value
    }
}

// MARK: - Singleton Accessor

/// Convenience accessor for feature flags throughout the app.
/// Configure once at launch via `FeatureFlags.configure(store:)`.
public enum FeatureFlags {
    private static var _store: FeatureFlagStore = UserDefaultsFlagStore()

    public static func configure(store: FeatureFlagStore) {
        _store = store
    }

    public static func isEnabled(_ flag: FeatureFlag) -> Bool {
        _store.isEnabled(flag)
    }

    public static func setEnabled(_ flag: FeatureFlag, _ value: Bool) {
        _store.setEnabled(flag, value)
    }
}
