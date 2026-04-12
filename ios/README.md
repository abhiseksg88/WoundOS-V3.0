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

1. Open `ios/` directory in Xcode
2. Add local SPM packages from `Packages/`
3. Build and run on a LiDAR-equipped device
