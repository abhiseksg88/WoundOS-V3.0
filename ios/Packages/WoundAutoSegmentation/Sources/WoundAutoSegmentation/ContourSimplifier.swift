import CoreGraphics
import Foundation

// MARK: - Contour Simplifier

/// Reduces a dense pixel-accurate contour (hundreds of vertices) down to a
/// clinically reasonable polygon (30–80 vertices) while preserving shape.
///
/// Pipeline:
///  1. **Douglas-Peucker** — drops colinear/near-colinear points.
///  2. **Min-edge-length filter** — merges tiny jitter segments.
///  3. **Vertex cap** — if still too dense, raise epsilon and repeat.
///
/// Output is a **closed polygon** (first point is not repeated at the end)
/// to match `BoundaryCanvasView` and `BoundaryProjector` conventions.
public enum ContourSimplifier {

    /// Target vertex count cap. Anything above this triggers re-simplification.
    public static let defaultMaxVertices = 80

    /// Default Douglas-Peucker epsilon in image pixels. ~1.5 px is a good
    /// starting point for a ~1080 × 1080 crop; the adaptive loop raises it
    /// if the contour is still too dense.
    public static let defaultEpsilonPx: CGFloat = 1.5

    /// Minimum acceptable edge length in image pixels. Shorter edges are
    /// collapsed. Set ~2 px so that two consecutive points from a mask's
    /// marching-squares walk don't become a degenerate zero-area edge.
    public static let defaultMinEdgePx: CGFloat = 2.0

    public static func simplify(
        _ polygon: [CGPoint],
        epsilon: CGFloat = defaultEpsilonPx,
        minEdge: CGFloat = defaultMinEdgePx,
        maxVertices: Int = defaultMaxVertices
    ) -> [CGPoint] {
        guard polygon.count > 3 else { return polygon }

        var simplified = douglasPeuckerClosed(polygon, epsilon: epsilon)
        simplified = dropShortEdges(simplified, minEdge: minEdge)

        // Adaptive loop: if still too dense, raise epsilon geometrically.
        var currentEpsilon = epsilon
        var iteration = 0
        while simplified.count > maxVertices && iteration < 6 {
            currentEpsilon *= 1.6
            simplified = douglasPeuckerClosed(polygon, epsilon: currentEpsilon)
            simplified = dropShortEdges(simplified, minEdge: minEdge)
            iteration += 1
        }

        return simplified
    }

    // MARK: - Closed Douglas-Peucker

    /// Douglas-Peucker adapted for a **closed** polygon. We anchor on the two
    /// points furthest apart to avoid the degenerate "start == end" failure
    /// mode of the classic open-curve version.
    public static func douglasPeuckerClosed(
        _ polygon: [CGPoint],
        epsilon: CGFloat
    ) -> [CGPoint] {
        guard polygon.count > 3 else { return polygon }

        // Find the two points with the maximum pairwise distance. These
        // become the anchors that split the polygon into two open chains.
        var anchorA = 0
        var anchorB = 0
        var maxDist: CGFloat = 0
        for i in 0..<polygon.count {
            for j in (i + 1)..<polygon.count {
                let d = polygon[i].squaredDistance(to: polygon[j])
                if d > maxDist {
                    maxDist = d
                    anchorA = i
                    anchorB = j
                }
            }
        }
        if maxDist == 0 { return polygon }

        let chain1 = Array(polygon[anchorA...anchorB])
        let chain2 = Array(polygon[anchorB...]) + Array(polygon[...anchorA])

        let s1 = douglasPeuckerOpen(chain1, epsilon: epsilon)
        let s2 = douglasPeuckerOpen(chain2, epsilon: epsilon)

        // Stitch back: s1 goes A→B, s2 goes B→A (drop duplicated endpoints).
        return Array(s1.dropLast()) + Array(s2.dropLast())
    }

    /// Classic recursive Douglas-Peucker for an open polyline.
    public static func douglasPeuckerOpen(
        _ points: [CGPoint],
        epsilon: CGFloat
    ) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let start = points.first!
        let end = points.last!

        var maxDistance: CGFloat = 0
        var maxIndex = 0
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(
                point: points[i],
                lineStart: start,
                lineEnd: end
            )
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeuckerOpen(Array(points[0...maxIndex]), epsilon: epsilon)
            let right = douglasPeuckerOpen(Array(points[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [start, end]
        }
    }

    // MARK: - Short-Edge Filter

    /// Collapse consecutive vertices that are closer than `minEdge` apart.
    /// Preserves polygon closure.
    public static func dropShortEdges(
        _ polygon: [CGPoint],
        minEdge: CGFloat
    ) -> [CGPoint] {
        guard polygon.count > 3 else { return polygon }
        let minSq = minEdge * minEdge

        var result: [CGPoint] = []
        result.reserveCapacity(polygon.count)

        for p in polygon {
            if let last = result.last, last.squaredDistance(to: p) < minSq {
                continue
            }
            result.append(p)
        }

        // Final closure check — if first and last collapsed, drop the tail.
        if result.count > 3,
           let first = result.first,
           let last = result.last,
           first.squaredDistance(to: last) < minSq {
            result.removeLast()
        }
        return result
    }

    // MARK: - Geometry

    private static func perpendicularDistance(
        point: CGPoint,
        lineStart: CGPoint,
        lineEnd: CGPoint
    ) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lineLength = (dx * dx + dy * dy).squareRoot()
        guard lineLength > 0 else {
            return point.distance(to: lineStart)
        }
        let num = abs(
            dy * point.x
            - dx * point.y
            + lineEnd.x * lineStart.y
            - lineEnd.y * lineStart.x
        )
        return num / lineLength
    }
}

// MARK: - CGPoint Distance Helpers

extension CGPoint {
    fileprivate func distance(to other: CGPoint) -> CGFloat {
        squaredDistance(to: other).squareRoot()
    }

    fileprivate func squaredDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
