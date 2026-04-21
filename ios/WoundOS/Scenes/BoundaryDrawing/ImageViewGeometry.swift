import CoreGraphics
import simd

// MARK: - Image View Geometry

/// Captures the relationship between a UIImageView's bounds, the
/// displayed (orientation-corrected) image, and the raw sensor pixel
/// buffer from ARKit.
///
/// ARKit's `capturedImage` is **always** in landscape-right orientation
/// regardless of device posture. The app is portrait-only, so the
/// displayed image is rotated 90° CW (UIImage.Orientation.right).
///
/// This struct handles the full chain:
///     view-local touch  →  display-normalized  →  sensor-normalized
/// so that `BoundaryProjector` always receives coords in the raw
/// landscape-right space that matches `cameraIntrinsics`.
struct ImageViewGeometry {

    /// Sensor (raw pixel buffer) size — matches snapshot.imageWidth/Height.
    /// Always landscape-right (e.g. 1920 × 1440).
    let sensorSize: CGSize

    /// Displayed image size in points after orientation is applied.
    /// For portrait display of a landscape buffer this is (1440 × 1920).
    let displayedSize: CGSize

    /// Canvas / image-view size in points.
    let viewSize: CGSize

    /// The `.scaleAspectFit` rect of the **displayed** image within the view.
    let fittedRect: CGRect

    init(sensorSize: CGSize, displayedSize: CGSize, viewSize: CGSize) {
        self.sensorSize = sensorSize
        self.displayedSize = displayedSize
        self.viewSize = viewSize

        guard displayedSize.width > 0, displayedSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            self.fittedRect = .zero
            return
        }
        let scale = min(viewSize.width / displayedSize.width,
                        viewSize.height / displayedSize.height)
        let fittedW = displayedSize.width * scale
        let fittedH = displayedSize.height * scale
        self.fittedRect = CGRect(
            x: (viewSize.width - fittedW) / 2,
            y: (viewSize.height - fittedH) / 2,
            width: fittedW,
            height: fittedH
        )
    }

    // MARK: - View ↔ Sensor Conversions

    /// Convert a view-local point to **sensor-space** normalized [0…1]
    /// coordinates suitable for `BoundaryProjector`.
    ///
    /// Accounts for both `.scaleAspectFit` letterboxing and the 90° CW
    /// rotation from portrait display to landscape-right sensor.
    func viewToSensorNormalized(_ viewPoint: CGPoint) -> SIMD2<Float> {
        guard fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        // Step 1: view-local → display-normalized (0…1 in portrait space)
        let dNormX = Float((viewPoint.x - fittedRect.minX) / fittedRect.width)
        let dNormY = Float((viewPoint.y - fittedRect.minY) / fittedRect.height)
        // Step 2: portrait display → landscape sensor
        // 90° CCW rotation to undo the .right display rotation:
        //   sensor_x = 1 - display_y
        //   sensor_y = display_x
        return SIMD2<Float>(1.0 - dNormY, dNormX)
    }

    /// Convert a point in sensor pixel coordinates to view-local points
    /// for canvas display. Used to project auto-segmentation results back
    /// onto the portrait canvas.
    func sensorPixelToViewPoint(_ sensorPixel: CGPoint) -> CGPoint {
        guard sensorSize.width > 0, sensorSize.height > 0,
              fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        // Step 1: sensor pixel → sensor normalized
        let sNormX = sensorPixel.x / sensorSize.width
        let sNormY = sensorPixel.y / sensorSize.height
        // Step 2: landscape sensor → portrait display
        //   display_x = sensor_y
        //   display_y = 1 - sensor_x
        let dNormX = sNormY
        let dNormY = 1.0 - sNormX
        // Step 3: display normalized → view-local
        return CGPoint(
            x: fittedRect.minX + dNormX * fittedRect.width,
            y: fittedRect.minY + dNormY * fittedRect.height
        )
    }

    /// Convert a view-local point to sensor pixel coordinates.
    /// Used to convert the nurse's tap point for the segmenter.
    func viewToSensorPixel(_ viewPoint: CGPoint) -> CGPoint {
        guard fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        let sNorm = viewToSensorNormalized(viewPoint)
        return CGPoint(
            x: CGFloat(sNorm.x) * sensorSize.width,
            y: CGFloat(sNorm.y) * sensorSize.height
        )
    }
}
