# Feature Flag Defaults — Pre-Submission Checklist

Before submitting to the App Store, review and flip these flags in
`ios/WoundOS/Utilities/FeatureFlags.swift` → `UserDefaultsFlagStore.init()`.

## Flags Requiring Review

| Flag | TestFlight Default | App Store Default | Reason |
|------|-------------------|-------------------|--------|
| `v5LidarCapture` | `true` | `true` | Core V5 functionality, ship enabled |
| `onDeviceSegmentation` | `true` | **`false`** | Pending FDA 510(k) validation of on-device CoreML model |
| `tissueClassification` | `false` | `false` | Not yet implemented |
| `scanMode` | `false` | `false` | Not yet implemented |
| `medgemmaNarrative` | `false` | `false` | Not yet implemented |
| `healthkitSync` | `false` | `false` | Not yet implemented |

## How to Flip

In `UserDefaultsFlagStore.init()`, change the `defaults.register` dictionary:

```swift
defaults.register(defaults: [
    FeatureFlag.v5LidarCapture.rawValue: true,
    // FeatureFlag.onDeviceSegmentation.rawValue: true,  // REMOVE for App Store
])
```

## Developer Mode

`DeveloperMode` (5-tap activation on Scans title) ships in all builds.
It has no visible UI affordance and does not affect default flag values.
No action needed for App Store submission.
