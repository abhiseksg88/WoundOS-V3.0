import Foundation
import os
import simd

private let logger = Logger(subsystem: "com.woundos.app", category: "Perimeter")

// MARK: - Perimeter Calculator

/// Computes the wound perimeter as the sum of Euclidean distances
/// between consecutive 3D boundary points projected onto the mesh.
///
/// Raw 3D boundary points from mesh projection often zigzag on the
/// surface due to LiDAR noise, inflating the path length. A moving-
/// average smoother is applied before summation to reduce this effect.
public enum PerimeterCalculator {

    /// Minimum point count to apply smoothing. Below this threshold,
    /// the boundary is a low-resolution shape where smoothing would
    /// distort geometry rather than reduce noise.
    private static let smoothingMinPoints = 20

    /// Compute perimeter from 3D boundary points.
    /// For high-density boundaries (>= 20 points), applies moving-average
    /// smoothing (window=3, 2 iterations) to reduce LiDAR noise.
    /// - Parameter points3D: Ordered 3D points along the wound boundary (closed polygon)
    /// - Returns: Perimeter in mm
    public static func computePerimeter(points3D: [SIMD3<Float>]) -> Double {
        guard points3D.count >= 3 else { return 0 }

        // Only smooth high-density boundaries where LiDAR noise is an issue
        let smoothed: [SIMD3<Float>]
        if points3D.count >= smoothingMinPoints {
            smoothed = smoothBoundary(points3D, windowSize: 3, iterations: 2)
        } else {
            smoothed = points3D
        }

        var perimeter: Float = 0
        let n = smoothed.count

        for i in 0..<n {
            let j = (i + 1) % n
            perimeter += simd_distance(smoothed[i], smoothed[j])
        }

        let resultMm = Double(perimeter) * 1000.0
        logger.info("Perimeter: \(points3D.count) pts → smoothed \(smoothed.count) pts, result=\(resultMm)mm")

        // Meters to millimeters
        return Double(perimeter) * 1000.0
    }

    /// Compute raw perimeter without smoothing (for testing/comparison).
    /// - Parameter points3D: Ordered 3D points along the wound boundary (closed polygon)
    /// - Returns: Perimeter in mm
    public static func computeRawPerimeter(points3D: [SIMD3<Float>]) -> Double {
        guard points3D.count >= 3 else { return 0 }

        var perimeter: Float = 0
        let n = points3D.count

        for i in 0..<n {
            let j = (i + 1) % n
            perimeter += simd_distance(points3D[i], points3D[j])
        }

        return Double(perimeter) * 1000.0
    }

    // MARK: - Boundary Smoothing

    /// Moving-average smoother for a closed polygon of 3D points.
    /// Each point is replaced by the average of itself and its neighbors
    /// within the given window, wrapping around for the closed polygon.
    /// - Parameters:
    ///   - points: Input 3D boundary points (closed polygon)
    ///   - windowSize: Number of neighbors on each side (total window = 2*windowSize+1)
    ///   - iterations: Number of smoothing passes
    /// - Returns: Smoothed 3D boundary points (same count)
    public static func smoothBoundary(
        _ points: [SIMD3<Float>],
        windowSize: Int = 3,
        iterations: Int = 2
    ) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }

        var current = points
        let n = current.count
        let halfWindow = windowSize / 2

        for _ in 0..<iterations {
            var smoothed = [SIMD3<Float>]()
            smoothed.reserveCapacity(n)

            for i in 0..<n {
                var sum = SIMD3<Float>(0, 0, 0)
                var count: Float = 0

                for offset in -halfWindow...halfWindow {
                    let idx = (i + offset + n) % n
                    sum += current[idx]
                    count += 1
                }

                smoothed.append(sum / count)
            }

            current = smoothed
        }

        return current
    }
}
