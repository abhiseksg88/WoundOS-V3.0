import CoreGraphics
import simd

// MARK: - Image View Geometry

/// Captures the relationship between a UIImageView's bounds and the
/// displayed image when using `.scaleAspectFit`. Used to convert
/// between view-local touch coordinates and image-pixel / image-
/// normalized coordinates.
///
/// The pipeline requires all boundary points to be normalized against
/// the **image** dimensions (matching `CaptureSnapshot.imageWidth/Height`
/// and `BoundaryProjector`'s expectations), NOT the view dimensions.
/// With `.scaleAspectFit`, the image is letterboxed inside the view,
/// so view-normalized coords ≠ image-normalized coords.
struct ImageViewGeometry {

    /// Original image size in pixels (matches snapshot.imageWidth/Height).
    let imageSize: CGSize

    /// Canvas / image-view size in points.
    let viewSize: CGSize

    /// The `.scaleAspectFit` rect of the image within the view.
    let fittedRect: CGRect

    init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize

        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            self.fittedRect = .zero
            return
        }
        let scale = min(viewSize.width / imageSize.width,
                        viewSize.height / imageSize.height)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = CGPoint(
            x: (viewSize.width - fittedSize.width) / 2,
            y: (viewSize.height - fittedSize.height) / 2
        )
        self.fittedRect = CGRect(origin: origin, size: fittedSize)
    }

    /// Convert a view-local point to image-normalized [0…1] coords
    /// suitable for `BoundaryProjector`.
    func viewToImageNormalized(_ viewPoint: CGPoint) -> SIMD2<Float> {
        guard fittedRect.width > 0, fittedRect.height > 0 else {
            return .zero
        }
        return SIMD2<Float>(
            Float((viewPoint.x - fittedRect.minX) / fittedRect.width),
            Float((viewPoint.y - fittedRect.minY) / fittedRect.height)
        )
    }

    /// Convert an image-pixel point to view-local points for canvas display.
    func imagePointToViewPoint(_ imagePoint: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(
            x: fittedRect.minX + imagePoint.x / imageSize.width * fittedRect.width,
            y: fittedRect.minY + imagePoint.y / imageSize.height * fittedRect.height
        )
    }

    /// Convert a view-local point to image-pixel coordinates.
    func viewPointToImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        guard fittedRect.width > 0, fittedRect.height > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - fittedRect.minX) / fittedRect.width * imageSize.width,
            y: (viewPoint.y - fittedRect.minY) / fittedRect.height * imageSize.height
        )
    }
}
