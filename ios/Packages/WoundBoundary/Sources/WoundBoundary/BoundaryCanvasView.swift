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
    public var strokeColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.8)
    public var fillColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.15)
    public var vertexColor: UIColor = .white
    public var strokeWidth: CGFloat = 2.5
    public var vertexRadius: CGFloat = 6.0

    /// Douglas-Peucker simplification epsilon for freeform mode (points)
    public var simplificationEpsilon: CGFloat = 2.0

    /// Proximity threshold to auto-close polygon (points)
    public var closeProximityThreshold: CGFloat = 25.0

    // MARK: - Internal State

    private(set) var tapPoint: CGPoint?
    private(set) var boundaryPoints: [CGPoint] = []
    private var isDrawingFreeform = false

    // Shape layers for rendering
    private let boundaryShapeLayer = CAShapeLayer()
    private let vertexLayer = CALayer()
    private let tapPointLayer = CAShapeLayer()

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

        tapPointLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.8).cgColor
        tapPointLayer.strokeColor = UIColor.white.cgColor
        tapPointLayer.lineWidth = 2.0
        layer.addSublayer(tapPointLayer)

        layer.addSublayer(vertexLayer)
    }

    // MARK: - Public API

    /// Clear all drawn content and reset state
    public func clearAll() {
        tapPoint = nil
        boundaryPoints.removeAll()
        isDrawingFreeform = false
        updateRendering()
        delegate?.canvasDidClearBoundary()
    }

    /// Remove the last vertex in polygon mode
    public func undoLastVertex() {
        guard drawingMode == .polygon, !boundaryPoints.isEmpty else { return }
        boundaryPoints.removeLast()
        updateRendering()
        delegate?.canvasDidUpdateBoundary(boundaryPoints)
    }

    // MARK: - Touch Handling

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        switch drawingMode {
        case .tapPoint:
            tapPoint = location
            updateRendering()
            delegate?.canvasDidPlaceTapPoint(location)

        case .polygon:
            // Check if close enough to first point to auto-close
            if boundaryPoints.count >= 3,
               let first = boundaryPoints.first,
               location.distance(to: first) < closeProximityThreshold {
                // Close the polygon
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
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drawingMode == .freeform, isDrawingFreeform,
              let touch = touches.first else { return }

        let location = touch.location(in: self)

        // Only add point if it's far enough from the last one (reduces noise)
        if let last = boundaryPoints.last, location.distance(to: last) > 3.0 {
            boundaryPoints.append(location)
            updateRendering()
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard drawingMode == .freeform, isDrawingFreeform else { return }
        isDrawingFreeform = false

        // Simplify the freeform path using Douglas-Peucker
        let simplified = douglasPeucker(boundaryPoints, epsilon: simplificationEpsilon)
        boundaryPoints = simplified

        updateRendering()
        delegate?.canvasDidFinalizeBoundary(boundaryPoints)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDrawingFreeform = false
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
            // Add crosshair
            path.move(to: CGPoint(x: tp.x - radius * 1.5, y: tp.y))
            path.addLine(to: CGPoint(x: tp.x + radius * 1.5, y: tp.y))
            path.move(to: CGPoint(x: tp.x, y: tp.y - radius * 1.5))
            path.addLine(to: CGPoint(x: tp.x, y: tp.y + radius * 1.5))
            tapPointLayer.path = path.cgPath
        } else {
            tapPointLayer.path = nil
        }

        // Render boundary
        if boundaryPoints.count >= 2 {
            let path = UIBezierPath()
            path.move(to: boundaryPoints[0])
            for i in 1..<boundaryPoints.count {
                path.addLine(to: boundaryPoints[i])
            }
            // Close the path if finalized (not actively drawing freeform)
            if !isDrawingFreeform && boundaryPoints.count >= 3 {
                path.close()
            }
            boundaryShapeLayer.path = path.cgPath
        } else {
            boundaryShapeLayer.path = nil
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

    /// Reduce point count while preserving shape. Essential for freeform traces
    /// that can produce hundreds of raw touch points.
    private func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDistance: CGFloat = 0
        var maxIndex = 0

        let start = points.first!
        let end = points.last!

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

// MARK: - CGPoint Distance Helper

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
