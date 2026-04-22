import Foundation
import simd

// MARK: - Capture Bundle

/// V5 capture bundle. A richer envelope around the frozen capture data,
/// keyed by a unique captureUUID. Adds metadata that CaptureData lacks:
/// confidence summary, quality score at capture moment, capture mode,
/// and session metadata for 510(k) audit trail.
public struct CaptureBundle: Codable, Sendable, Identifiable {

    // MARK: - Identity

    /// Unique identifier for this capture event
    public let id: UUID

    // MARK: - Core Data (V4-compatible)

    /// The frozen capture data (RGB, depth, mesh, camera)
    public let captureData: CaptureData

    // MARK: - V5 Metadata

    /// How this capture was taken
    public let captureMode: CaptureMode

    /// Quality score at the exact moment of capture
    public let qualityScore: CaptureQualityScore

    /// Confidence summary across the depth map
    public let confidenceSummary: ConfidenceSummary

    /// Device and session metadata
    public let sessionMetadata: CaptureSessionMetadata

    /// When this bundle was created
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        captureData: CaptureData,
        captureMode: CaptureMode = .singleShot,
        qualityScore: CaptureQualityScore,
        confidenceSummary: ConfidenceSummary,
        sessionMetadata: CaptureSessionMetadata,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.captureData = captureData
        self.captureMode = captureMode
        self.qualityScore = qualityScore
        self.confidenceSummary = confidenceSummary
        self.sessionMetadata = sessionMetadata
        self.capturedAt = capturedAt
    }
}

// MARK: - Capture Mode

public enum CaptureMode: String, Codable, Sendable {
    case singleShot   // V4-style single frame capture
    case scanMode     // Object Capture Area Mode, iOS 18+
    case photoOnly    // Non-LiDAR fallback (no depth/mesh)
}

// MARK: - Confidence Summary

/// Summary of depth confidence across the captured frame.
public struct ConfidenceSummary: Codable, Sendable {
    /// Fraction of pixels at high confidence (confidence == 2)
    public let highFraction: Float
    /// Fraction of pixels at medium confidence (confidence == 1)
    public let mediumFraction: Float
    /// Fraction of pixels at low confidence (confidence == 0)
    public let lowFraction: Float

    /// Overall confidence score (0...1), weighted average
    public var overallScore: Float {
        highFraction * 1.0 + mediumFraction * 0.5
    }

    public init(
        highFraction: Float,
        mediumFraction: Float,
        lowFraction: Float
    ) {
        self.highFraction = highFraction
        self.mediumFraction = mediumFraction
        self.lowFraction = lowFraction
    }

    /// Compute from a raw confidence map (UInt8 array where 0=low, 1=medium, 2=high)
    public init(fromConfidenceMap map: [UInt8]) {
        guard !map.isEmpty else {
            self.init(highFraction: 0, mediumFraction: 0, lowFraction: 0)
            return
        }
        let total = Float(map.count)
        var high: Float = 0
        var medium: Float = 0
        var low: Float = 0
        for value in map {
            switch value {
            case 2: high += 1
            case 1: medium += 1
            default: low += 1
            }
        }
        self.init(
            highFraction: high / total,
            mediumFraction: medium / total,
            lowFraction: low / total
        )
    }
}

// MARK: - Session Metadata

/// Device and session context for 510(k) audit trail.
public struct CaptureSessionMetadata: Codable, Sendable {
    public let deviceModel: String
    public let osVersion: String
    public let appVersion: String
    public let lidarAvailable: Bool
    public let trackingStableSeconds: Double
    public let captureDistanceM: Float
    public let meshAnchorCount: Int
    public let sessionDurationSeconds: TimeInterval

    public init(
        deviceModel: String,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        lidarAvailable: Bool,
        trackingStableSeconds: Double,
        captureDistanceM: Float,
        meshAnchorCount: Int,
        sessionDurationSeconds: TimeInterval
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.lidarAvailable = lidarAvailable
        self.trackingStableSeconds = trackingStableSeconds
        self.captureDistanceM = captureDistanceM
        self.meshAnchorCount = meshAnchorCount
        self.sessionDurationSeconds = sessionDurationSeconds
    }
}
