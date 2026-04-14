# WoundOS V3.0 — iOS App

Clinical wound measurement system using ARKit + LiDAR.

## Architecture

**UIKit + MVVM-C** with modular Swift packages:

| Package | Purpose |
|---------|---------|
| `WoundCore` | Domain models, protocols, extensions |
| `WoundCapture` | ARKit session, LiDAR depth, mesh reconstruction |
| `WoundBoundary` | Nurse boundary drawing, 2D→3D projection, validation |
| `WoundMeasurement` | Area, depth, volume, perimeter, length/width, PUSH score |
| `WoundNetworking` | API client, background upload, serialization |

## Clinical Workflow

1. **Capture** — Camera + ARKit freezes RGB, depth, mesh, camera pose
2. **Tap** — Nurse taps wound center (used as SAM 2 point prompt on backend)
3. **Draw** — Nurse traces wound boundary (polygon or freeform)
4. **Measure** — On-device: boundary → 3D projection → mesh clipping → area/depth/volume/perimeter/length/width
5. **PUSH Score** — Nurse enters exudate + tissue type, system computes PUSH 3.0
6. **Save & Upload** — Saved locally, uploaded to backend for shadow AI validation

## Requirements

- iPhone 12 Pro or later (LiDAR required)
- iOS 16+
- Xcode 15+

## Setup

```bash
git clone <repo>
cd WoundOS-V3.0
open ios/WoundOS.xcodeproj
```

In Xcode:
1. Select the **WoundOS** target
2. Under **Signing & Capabilities**, set your development team
3. Select a connected LiDAR iPhone as the run destination
4. Build and run (⌘R)

Xcode will automatically resolve the five local Swift packages
(WoundCore, WoundCapture, WoundBoundary, WoundMeasurement,
WoundNetworking) via the project's local-package references. No
manual "Add Package" step is needed.

## Project Structure

```
ios/
├── WoundOS.xcodeproj/                  # Xcode project — open this
├── WoundOS/                            # App sources (UIKit + MVVM-C)
│   ├── App/                            # AppDelegate, SceneDelegate, DI
│   ├── Coordinators/                   # Flow coordinators
│   ├── Scenes/
│   │   ├── Capture/                    # AR capture screen
│   │   ├── BoundaryDrawing/            # Nurse boundary tracing
│   │   ├── Measurement/                # Computed measurements UI
│   │   ├── ScanDetail/                 # Historical detail + AI comparison
│   │   └── ScanList/                   # Scan history
│   ├── Views/                          # Shared UI components
│   └── Resources/                      # Info.plist
├── Packages/                           # Local Swift packages
│   ├── WoundCore/                      # Domain models, protocols
│   ├── WoundCapture/                   # ARKit + LiDAR + quality monitor
│   ├── WoundBoundary/                  # Drawing + 2D→3D projection
│   ├── WoundMeasurement/               # Area, depth, volume, PUSH
│   └── WoundNetworking/                # API client, upload manager
└── README.md
```

## Running Tests

Each package has its own test target. Run them from the command line:

```bash
cd ios/Packages/WoundCore && swift test
cd ios/Packages/WoundMeasurement && swift test
```

Or inside Xcode, the tests appear under the Package Dependencies
section of the project navigator and can be run from the Test
navigator (⌘6 → click the diamond next to a test class).

## On-device Validation

Before clinical use, validate measurement accuracy on real hardware
using a printed reference square:

1. Print a **50 × 50 mm** black square on white paper, lay flat
2. Hold device ~20 cm above the square
3. Wait for the "Ready" state — all four strict quality gates must
   pass (tracking stable ≥ 1.5s, distance 15–30 cm, mesh density,
   steady hold)
4. Capture, draw polygon boundary along the square edges, tap Measure
5. Verify:
   - Area ≈ 25.0 cm² ± 1.0
   - Length ≈ 50 mm ± 2
   - Width ≈ 50 mm ± 2
   - Max depth ≈ 0 mm (flat surface)

If these tolerances hold, measurements are trustworthy for clinical
pilot use.
