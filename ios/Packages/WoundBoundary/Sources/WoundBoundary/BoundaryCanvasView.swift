import UIKit
import WoundCore

// MARK: - Boundary Drawing Delegate

public protocol BoundaryCanvasDelegate: AnyObject {
    /// Called when the nurse taps to place the initial wound center point
    func canvasDidPlaceTapPoint(_ point: CGPoint)
    /// Called as the boundary is being drawn (live preview)
    func canvasDidUpdateBoundary(_ points: [CGPoint])
    /// Called when the boundary is finalized (finger lifted / polygon closed)
    func canvasDidFinalizeBoundary(_ points: [CGPoint])
    /// Called when the boundary is cleared
    func canvasDidClearBoundary()
}

// MARK: - Drawing Mode

public enum DrawingMode {
    case tapPoint   // Initial wound center tap
    case polygon    // Tap-to-place vertices
    case freeform   // Continuous drag tracing
    /// Nurse taps once; segmenter seeds a polygon; canvas becomes editable
    /// (switched to `.polygon` after the seed boundary is delivered).
    case auto
}

// MARK: - Boundary Canvas View

/// UIKit view overlaid on the captured wound image.
/// Handles touch input for wound boundary drawing in polygon or freeform mode.
/// Coordinates are in the view's local space; the delegate receives
/// them for normalization and 3D projection.
public final class BoundaryCanvasView: UIView {

    // MARK: - Public Properties

    public weak var delegate: BoundaryCanvasDelegate?
    public var drawingMode: DrawingMode = .tapPoint
    public var strokeColor: UIColor = UIColor(red: 0.0, green: 0.90, blue: 0.30, alpha: 0.9)
    public var fillColor: UIColor = UIColor(red: 0.0, green: 0.90, blue: 0.30, alpha: 0.12)
    public var vertexColor: UIColor = .white
    public var strokeWidth: CGFloat = 2.5
    public var vertexRadius: CGFloat = 6.0

    /// Douglas-Peucker simplification epsilon for freeform mode (points)
    public var simplificationEpsilon: CGFloat = 2.0

    /// Proximity threshold to auto-close polygon (points)
    public var closeProximityThreshold: CGFloat = 30.0

    // MARK: - Internal State

    private(set) var tapPoint: CGPoint?
    private(set) var boundaryPoints: [CGPoint] = []
    private var isDrawingFreeform = false

    // Shape layers for rendering
    private let boundaryShapeLayer = CAShapeLayer()
    private let inProgressStrokeLayer = CAShapeLayer()
    private let boundingBoxLayer = CAShapeLayer()
    private let vertexLayer = CALayer()
    private let tapPointLayer = CAShapeLayer()
    private let closeHintLayer = CAShapeLayer()

    // Magnifier loupe
    private let magnifierView = MagnifierLoupeView()
    private weak var sourceViewForMagnifier: UIView?

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        boundaryShapeLayer.fillColor = fillColor.cgColor
        boundaryShapeLayer.strokeColor = strokeColor.cgColor
        boundaryShapeLayer.lineWidth = strokeWidth
        boundaryShapeLayer.lineJoin = .round
        boundaryShapeLayer.lineCap = .round
        layer.addSublayer(boundaryShapeLayer)

        inProgressStrokeLayer.fillColor = UIColor.clear.cgColor
        inProgressStrokeLayer.strokeColor = strokeColor.cgColor
        inProgressStrokeLayer.lineWidth = 3.0
        inProgressStrokeLayer.lineJoin = .round
        inProgressStrokeLayer.lineCap = .round
        layer.addSublayer(inProgressStrokeLayer)

        boundingBoxLayer.fillColor = UIColor.clear.cgColor
        boundingBoxLayer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.7).cgColor
        boundingBoxLayer.lineWidth = 1.5
        boundingBoxLayer.lineDashPattern = [6, 4]
        boundingBoxLayer.lineJoin = .miter
        layer.addSublayer(boundingBoxLayer)

        tapPointLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.8).cgColor
        tapPointLayer.strokeColor = UIColor.white.cgColor
        tapPointLayer.lineWidth = 2.0
        layer.addSublayer(tapPointLayer)

        closeHintLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
        closeHintLayer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.6).cgColor
        closeHintLayer.lineWidth = 2.0
        closeHintLayer.lineDashPattern = [4, 3]
        layer.addSublayer(closeHintLayer)

        layer.addSublayer(vertexLayer)

        magnifierView.isHidden = true
        addSubview(magnifierView)
    }

    /// Set the view that the magnifier captures content from (typically the parent imageView).
    public func setMagnifierSource(_ view: UIView) {
        sourceViewForMagnifier = view
    }

    // MARK: - Public API

    /// Seed the canvas with a boundary produced by an auto-segmenter.
    /// Moves the canvas into `.polygon` mode so the nurse can edit vertices.
    /// Does **not** re-fire `canvasDidPlaceTapPoint`; that has already been
    /// delivered by the tap that triggered segmentation.
    ///
    /// Pass `notifyDelegate: false` when the caller will handle finalization
    /// separately (e.g. auto-seg flow calls `autoFinalizeBoundary` instead).
    public func setBoundary(points: [CGPoint], keepTapPoint: Bool = true, notifyDelegate: Bool = true) {
        guard points.count >= 3 else { return }
        if !keepTapPoint { tapPoint = nil }
        boundaryPoints = points
        isDrawingFreeform = false
        drawingMode = .polygon
        updateRendering()
        if notifyDelegate {
            delegate?.canvasDidFinalizeBoundary(boundaryPoints)
        }
    }

    /// Clear all drawn content and reset state
    public func clearAll() {
        tapPoint = nil
        boundaryPoints.removeAll()
        isDrawingFreeform = false
        boundingBoxLayer.path = nil
        inProgressStrokeLayer.path = nil
        closeHintLayer.path = nil
        updateRendering()
        delegate?.canvasDidClearBoundary()
    }

    /// Remove the last vertex in polygon mode
    public func undoLastVertex() {
        guard !boundaryPoints.isEmpty else { return }
        boundaryPoints.removeLast()
        updateRendering()
        delegate?.canvasDidUpdateBoundary(boundaryPoints)
    }

    // MARK: - Touch Handling

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        switch drawingMode {
        case .tapPoint, .auto:
            tapPoint = location
            updateRendering()
            delegate?.canvasDidPlaceTapPoint(location)

        case .polygon:
            if boundaryPoints.count >= 3,
               let first = boundaryPoints.first,
               location.distance(to: first) < closeProximityThreshold {
                updateRendering()
                delegate?.canvasDidFinalizeBoundary(boundaryPoints)
            } else {
                boundaryPoints.append(location)
                updateRendering()
                delegate?.canvasDidUpdateBoundary(boundaryPoints)
            }

        case .freeform:
            boundaryPoints = [location]
            isDrawingFreeform = true
            updateRendering()
            showMagnifier(at: location)
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drawingMode == .freeform, isDrawingFreeform,
              let touch = touches.first else { return }

        let location = touch.location(in: self)

        if let last = boundaryPoints.last, location.distance(to: last) > 3.0 {
            boundaryPoints.append(location)
            updateInProgressStroke()
            updateCloseHint(currentPoint: location)
        }
        updateMagnifier(at: location)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        hideMagnifier()
        inProgressStrokeLayer.path = nil
        closeHintLayer.path = nil

        guard drawingMode == .freeform, isDrawingFreeform else { return }
        isDrawingFreeform = false

        guard boundaryPoints.count >= 3 else {
            boundaryPoints.removeAll()
            updateRendering()
            return
        }

        if let first = boundaryPoints.first, let last = boundaryPoints.last {
            let gap = first.distance(to: last)
            if gap > closeProximityThreshold {
                let steps = max(2, Int(gap / 8.0))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let midPoint = CGPoint(
                        x: last.x + (first.x - last.x) * t,
                        y: last.y + (first.y - last.y) * t
                    )
                    boundaryPoints.append(midPoint)
                }
            }
        }

        let simplified = douglasPeucker(boundaryPoints, epsilon: simplificationEpsilon)
        boundaryPoints = simplified

        updateRendering()
        delegate?.canvasDidFinalizeBoundary(boundaryPoints)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDrawingFreeform = false
        hideMagnifier()
        inProgressStrokeLayer.path = nil
        closeHintLayer.path = nil
    }

    // MARK: - In-Progress Stroke (real-time feedback during freeform drawing)

    private func updateInProgressStroke() {
        guard isDrawingFreeform, boundaryPoints.count >= 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        path.move(to: boundaryPoints[0])
        for i in 1..<boundaryPoints.count {
            path.addLine(to: boundaryPoints[i])
        }
        inProgressStrokeLayer.path = path.cgPath
        CATransaction.commit()
    }

    // MARK: - Close Hint (visual guide when near start point)

    private func updateCloseHint(currentPoint: CGPoint) {
        guard let first = boundaryPoints.first, boundaryPoints.count >= 3 else {
            closeHintLayer.path = nil
            return
        }

        let distance = currentPoint.distance(to: first)
        if distance < closeProximityThreshold * 2 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let hintPath = UIBezierPath()
            hintPath.move(to: currentPoint)
            hintPath.addLine(to: first)

            let ringRadius: CGFloat = closeProximityThreshold
            let ringRect = CGRect(
                x: first.x - ringRadius,
                y: first.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            hintPath.append(UIBezierPath(ovalIn: ringRect))

            let alpha = max(0.2, 1.0 - (distance / (closeProximityThreshold * 2)))
            closeHintLayer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.6 * alpha).cgColor
            closeHintLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15 * alpha).cgColor
            closeHintLayer.path = hintPath.cgPath
            CATransaction.commit()
        } else {
            closeHintLayer.path = nil
        }
    }

    // MARK: - Magnifier

    private func showMagnifier(at point: CGPoint) {
        guard let source = sourceViewForMagnifier ?? superview else { return }
        magnifierView.isHidden = false
        magnifierView.updateContent(at: point, in: source, canvasView: self)
    }

    private func updateMagnifier(at point: CGPoint) {
        guard let source = sourceViewForMagnifier ?? superview else { return }
        magnifierView.updateContent(at: point, in: source, canvasView: self)
    }

    private func hideMagnifier() {
        magnifierView.isHidden = true
    }

    // MARK: - Rendering

    private func updateRendering() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Render tap point
        if let tp = tapPoint {
            let radius: CGFloat = 10.0
            let path = UIBezierPath(
                arcCenter: tp,
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            path.move(to: CGPoint(x: tp.x - radius * 1.5, y: tp.y))
            path.addLine(to: CGPoint(x: tp.x + radius * 1.5, y: tp.y))
            path.move(to: CGPoint(x: tp.x, y: tp.y - radius * 1.5))
            path.addLine(to: CGPoint(x: tp.x, y: tp.y + radius * 1.5))
            tapPointLayer.path = path.cgPath
        } else {
            tapPointLayer.path = nil
        }

        // Render boundary (filled only when NOT actively drawing)
        if boundaryPoints.count >= 2 && !isDrawingFreeform {
            let path = UIBezierPath()
            path.move(to: boundaryPoints[0])
            for i in 1..<boundaryPoints.count {
                path.addLine(to: boundaryPoints[i])
            }
            if boundaryPoints.count >= 3 {
                path.close()
            }
            boundaryShapeLayer.fillColor = fillColor.cgColor
            boundaryShapeLayer.path = path.cgPath
        } else if !isDrawingFreeform {
            boundaryShapeLayer.path = nil
        } else {
            boundaryShapeLayer.path = nil
        }

        // Render bounding box around finalized boundary
        if boundaryPoints.count >= 3 && !isDrawingFreeform {
            let xs = boundaryPoints.map(\.x)
            let ys = boundaryPoints.map(\.y)
            if let minX = xs.min(), let maxX = xs.max(),
               let minY = ys.min(), let maxY = ys.max() {
                let padding: CGFloat = 8.0
                let bboxRect = CGRect(
                    x: minX - padding,
                    y: minY - padding,
                    width: (maxX - minX) + padding * 2,
                    height: (maxY - minY) + padding * 2
                )
                boundingBoxLayer.path = UIBezierPath(roundedRect: bboxRect, cornerRadius: 4).cgPath
            } else {
                boundingBoxLayer.path = nil
            }
        } else {
            boundingBoxLayer.path = nil
        }

        // Render vertex dots (polygon mode only)
        vertexLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        if drawingMode == .polygon {
            for (index, point) in boundaryPoints.enumerated() {
                let dot = CAShapeLayer()
                let isFirst = index == 0
                let radius = isFirst ? vertexRadius * 1.3 : vertexRadius
                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                dot.path = UIBezierPath(ovalIn: rect).cgPath
                dot.fillColor = isFirst
                    ? UIColor.systemGreen.cgColor
                    : vertexColor.cgColor
                dot.strokeColor = strokeColor.cgColor
                dot.lineWidth = 1.5
                vertexLayer.addSublayer(dot)
            }
        }

        CATransaction.commit()
    }

    // MARK: - Douglas-Peucker Simplification

    private func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2,
              let start = points.first,
              let end = points.last else { return points }

        var maxDistance: CGFloat = 0
        var maxIndex = 0

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(point: points[i], lineStart: start, lineEnd: end)
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeucker(Array(points[0...maxIndex]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [start, end]
        }
    }

    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lineLength = sqrt(dx * dx + dy * dy)

        guard lineLength > 0 else {
            return point.distance(to: lineStart)
        }

        let num = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        return num / lineLength
    }
}

// MARK: - Magnifier Loupe View

private final class MagnifierLoupeView: UIView {

    private let magnification: CGFloat = 2.0
    private let loupeSize: CGFloat = 90.0
    private let loupeOffset: CGFloat = 80.0

    private let contentImageView = UIImageView()
    private let crosshairLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setup() {
        bounds = CGRect(x: 0, y: 0, width: loupeSize, height: loupeSize)
        layer.cornerRadius = loupeSize / 2
        layer.masksToBounds = true
        layer.borderWidth = 2.5
        layer.borderColor = UIColor.white.cgColor

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
        clipsToBounds = false

        contentImageView.frame = bounds
        contentImageView.contentMode = .scaleToFill
        contentImageView.clipsToBounds = true
        contentImageView.layer.cornerRadius = loupeSize / 2
        addSubview(contentImageView)

        let crossPath = UIBezierPath()
        let center = loupeSize / 2
        let armLen: CGFloat = 8
        crossPath.move(to: CGPoint(x: center - armLen, y: center))
        crossPath.addLine(to: CGPoint(x: center + armLen, y: center))
        crossPath.move(to: CGPoint(x: center, y: center - armLen))
        crossPath.addLine(to: CGPoint(x: center, y: center + armLen))
        crosshairLayer.path = crossPath.cgPath
        crosshairLayer.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        crosshairLayer.lineWidth = 1.0
        layer.addSublayer(crosshairLayer)
    }

    func updateContent(at touchPoint: CGPoint, in sourceView: UIView, canvasView: UIView) {
        let captureRadius = loupeSize / (2 * magnification)
        let captureRect = CGRect(
            x: touchPoint.x - captureRadius,
            y: touchPoint.y - captureRadius,
            width: captureRadius * 2,
            height: captureRadius * 2
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: captureRadius * 2, height: captureRadius * 2))
        let snapshot = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -captureRect.origin.x, y: -captureRect.origin.y)
            sourceView.layer.render(in: ctx.cgContext)
            canvasView.layer.render(in: ctx.cgContext)
        }
        contentImageView.image = snapshot

        var loupeCenter = CGPoint(x: touchPoint.x, y: touchPoint.y - loupeOffset)
        if loupeCenter.y - loupeSize / 2 < 0 {
            loupeCenter.y = touchPoint.y + loupeOffset
        }
        loupeCenter.x = max(loupeSize / 2, min(loupeCenter.x, canvasView.bounds.width - loupeSize / 2))

        center = loupeCenter
    }
}

// MARK: - CGPoint Distance Helper

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
