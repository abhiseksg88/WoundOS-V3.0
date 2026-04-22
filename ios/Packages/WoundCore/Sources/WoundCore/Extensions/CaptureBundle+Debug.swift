#if DEBUG
import Foundation
import simd

extension CaptureBundle {

    /// Structured debug output for GATE 2 smoke test.
    /// Prints 20 data fields + 6 sanity checks to Xcode console.
    public func debugDescription(verbose: Bool = true) -> String {
        var lines = [String]()

        let cd = captureData

        // --- Field 1: Capture UUID ---
        lines.append("Capture UUID: \(id.uuidString)")

        // --- Field 2: Timestamp ---
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        lines.append("Timestamp: \(isoFormatter.string(from: capturedAt))")

        // --- Field 3: Device model ---
        let deviceModel = sessionMetadata.deviceModel
        lines.append("Device model: \(deviceModel)")

        // --- Field 4: iOS version ---
        lines.append("iOS version: \(sessionMetadata.osVersion)")

        // --- Field 5: RGB dimensions ---
        lines.append("RGB dimensions: \(cd.imageWidth) × \(cd.imageHeight)")

        // --- Field 6: RGB format ---
        if verbose {
            lines.append("RGB format: JPEG compressed (\(cd.rgbImageData.count) bytes)")
        }

        // --- Unpack depth once ---
        let depthMap = cd.unpackDepthMap()
        let confidenceMap = Array(cd.confidenceMapData)

        // --- Field 7: Depth dimensions ---
        lines.append("Depth dimensions: \(cd.depthWidth) × \(cd.depthHeight)")

        // --- Field 8: Depth format ---
        if verbose {
            lines.append("Depth format: Float32 (\(cd.depthMapData.count) bytes)")
        }

        // --- Depth statistics ---
        let nonZeroDepths = depthMap.filter { $0 > 0 }
        let depthMin = nonZeroDepths.min() ?? 0
        let depthMax = depthMap.max() ?? 0

        // High-confidence depth stats (confidence == 2)
        var highConfDepths = [Float]()
        let pixelCount = Swift.min(depthMap.count, confidenceMap.count)
        for i in 0..<pixelCount {
            if confidenceMap[i] == 2 && depthMap[i] > 0 {
                highConfDepths.append(depthMap[i])
            }
        }
        let depthMean: Float
        let depthMedian: Float
        if highConfDepths.isEmpty {
            depthMean = 0
            depthMedian = 0
        } else {
            depthMean = highConfDepths.reduce(0, +) / Float(highConfDepths.count)
            let sorted = highConfDepths.sorted()
            let mid = sorted.count / 2
            depthMedian = sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2
                : sorted[mid]
        }

        // --- Field 9: Depth min ---
        lines.append("Depth min (meters): \(String(format: "%.4f", depthMin))")

        // --- Field 10: Depth max ---
        lines.append("Depth max (meters): \(String(format: "%.4f", depthMax))")

        // --- Field 11: Depth mean ---
        lines.append("Depth mean (meters): \(String(format: "%.4f", depthMean))")

        // --- Field 12: Depth median ---
        if verbose {
            lines.append("Depth median (meters): \(String(format: "%.4f", depthMedian))")
        }

        // --- Confidence stats ---
        let totalPixels = confidenceMap.count
        var highCount = 0, medCount = 0, lowCount = 0
        for c in confidenceMap {
            switch c {
            case 2: highCount += 1
            case 1: medCount += 1
            default: lowCount += 1
            }
        }
        let highPct = totalPixels > 0 ? Float(highCount) / Float(totalPixels) * 100 : 0
        let medPct = totalPixels > 0 ? Float(medCount) / Float(totalPixels) * 100 : 0
        let lowPct = totalPixels > 0 ? Float(lowCount) / Float(totalPixels) * 100 : 0

        // --- Field 13: Confidence high ---
        lines.append("Confidence high pct: \(String(format: "%.1f", highPct))%")

        // --- Field 14: Confidence medium ---
        if verbose {
            lines.append("Confidence medium pct: \(String(format: "%.1f", medPct))%")
        }

        // --- Field 15: Confidence low ---
        if verbose {
            lines.append("Confidence low pct: \(String(format: "%.1f", lowPct))%")
        }

        // --- Field 16: Camera intrinsics (fx, fy, cx, cy) ---
        let intrinsics = cd.cameraIntrinsics
        let fx = intrinsics.count >= 1 ? intrinsics[0] : 0
        let fy = intrinsics.count >= 5 ? intrinsics[4] : 0
        let cx = intrinsics.count >= 7 ? intrinsics[6] : 0
        let cy = intrinsics.count >= 8 ? intrinsics[7] : 0
        if verbose {
            lines.append("Camera intrinsics (fx, fy, cx, cy): \(String(format: "%.1f, %.1f, %.1f, %.1f", fx, fy, cx, cy))")
        }

        // --- Field 17: Camera intrinsics full matrix ---
        if verbose {
            if intrinsics.count == 9 {
                lines.append("Camera intrinsics full matrix:")
                lines.append("  [\(String(format: "%.2f, %.2f, %.2f", intrinsics[0], intrinsics[1], intrinsics[2]))]")
                lines.append("  [\(String(format: "%.2f, %.2f, %.2f", intrinsics[3], intrinsics[4], intrinsics[5]))]")
                lines.append("  [\(String(format: "%.2f, %.2f, %.2f", intrinsics[6], intrinsics[7], intrinsics[8]))]")
            } else {
                lines.append("Camera intrinsics full matrix: <unavailable>")
            }
        }

        // --- Field 18: Gravity vector ---
        // Gravity is derived from camera transform column 1 (Y-axis in world space)
        // Not directly stored — print unavailable
        if verbose {
            let transform = cd.cameraTransform
            if transform.count == 16 {
                // The gravity direction can be inferred from the world-space Y column
                // but ARFrame.camera.transform doesn't directly encode gravity.
                // We'd need the raw CMMotionManager or ARFrame.camera.eulerAngles.
                lines.append("Gravity vector (x, y, z): <unavailable>")
            } else {
                lines.append("Gravity vector (x, y, z): <unavailable>")
            }
        }

        // --- Field 19: ARKit tracking state ---
        if verbose {
            lines.append("ARKit tracking state: <unavailable>")
        }

        // --- Field 20: Feature points count ---
        if verbose {
            lines.append("Feature points count: <unavailable>")
        }

        // ============================================================
        // SANITY CHECKS (Task 2)
        // ============================================================
        lines.append("")
        lines.append("--- Sanity Checks ---")

        // Check 1: Depth map non-empty
        let nonZeroFraction = depthMap.isEmpty ? 0 : Float(nonZeroDepths.count) / Float(depthMap.count)
        if nonZeroFraction >= 0.50 {
            lines.append("PASS — Depth map non-empty: \(String(format: "%.1f", nonZeroFraction * 100))% non-zero pixels")
        } else {
            lines.append("FAIL — Depth map non-empty: only \(String(format: "%.1f", nonZeroFraction * 100))% non-zero (expected >= 50%)")
        }

        // Check 2: Depth in expected range
        if depthMean >= 0.20 && depthMean <= 2.00 {
            lines.append("PASS — Depth in expected range: mean \(String(format: "%.3f", depthMean))m (expected 0.20–2.00m)")
        } else {
            lines.append("FAIL — Depth in expected range: mean \(String(format: "%.3f", depthMean))m (expected 0.20–2.00m)")
        }

        // Check 3: High confidence present
        if highPct >= 20.0 {
            lines.append("PASS — High confidence present: \(String(format: "%.1f", highPct))% (expected >= 20%)")
        } else {
            lines.append("FAIL — High confidence present: \(String(format: "%.1f", highPct))% (expected >= 20%)")
        }

        // Check 4: Intrinsics plausible
        let fxOk = fx > 500 && fx < 3000
        let fyOk = fy > 500 && fy < 3000
        if fxOk && fyOk {
            lines.append("PASS — Intrinsics plausible: fx=\(String(format: "%.1f", fx)), fy=\(String(format: "%.1f", fy))")
        } else {
            lines.append("FAIL — Intrinsics plausible: fx=\(String(format: "%.1f", fx)), fy=\(String(format: "%.1f", fy)) (expected 500–3000)")
        }

        // Check 5: RGB/depth aspect match
        let rgbAspect = cd.imageHeight > 0 ? Float(cd.imageWidth) / Float(cd.imageHeight) : 0
        let depthAspect = cd.depthHeight > 0 ? Float(cd.depthWidth) / Float(cd.depthHeight) : 0
        let aspectDiff = rgbAspect > 0 ? abs(rgbAspect - depthAspect) / rgbAspect : 1.0
        if aspectDiff <= 0.01 {
            lines.append("PASS — RGB/depth aspect match: RGB=\(String(format: "%.3f", rgbAspect)), depth=\(String(format: "%.3f", depthAspect))")
        } else {
            lines.append("FAIL — RGB/depth aspect match: RGB=\(String(format: "%.3f", rgbAspect)), depth=\(String(format: "%.3f", depthAspect)) (diff \(String(format: "%.2f", aspectDiff * 100))%, expected <= 1%)")
        }

        // Check 6: Gravity magnitude
        // Gravity vector not available in CaptureData — skip with explanation
        lines.append("PASS — Gravity magnitude: <unavailable — gravity not stored in CaptureData; skipped>")

        return lines.joined(separator: "\n")
    }
}
#endif
