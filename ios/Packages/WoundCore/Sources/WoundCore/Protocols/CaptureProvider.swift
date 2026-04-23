import Foundation
import simd

// MARK: - Capture Provider Protocol

/// Contract for the ARKit capture system.
/// Abstracts the hardware dependency so view models and tests
/// can work with mock capture data.
public protocol CaptureProviderProtocol: AnyObject {

    /// Whether the current device supports LiDAR depth
    var isLiDARAvailable: Bool { get }

    /// Whether an AR session is currently running
    var isSessionActive: Bool { get }

    /// Start the AR session with scene reconstruction enabled
    func startSession() throws

    /// Pause the AR session
    func pauseSession()

    /// Resume the AR session after a pause without resetting tracking.
    /// Default implementation falls back to startSession() for providers
    /// that don't distinguish between start and resume.
    func resumeSession() throws

    /// Freeze the current ARKit frame and produce a capture snapshot.
    /// All spatial data (RGB, depth, mesh, camera pose) is locked
    /// at this instant.
    func captureSnapshot() throws -> CaptureSnapshot

    /// Register a callback for tracking state changes
    var onTrackingStateChanged: ((TrackingState) -> Void)? { get set }
}

// MARK: - Default Resume (falls back to start)

public extension CaptureProviderProtocol {
    func resumeSession() throws {
        try startSession()
    }
}

// MARK: - Capture Snapshot

/// Lightweight, in-memory representation of a frozen ARKit frame.
/// This is the intermediate form before serialization into CaptureData.
public struct CaptureSnapshot {
    public let rgbImageData: Data
    public let imageWidth: Int
    public let imageHeight: Int
    public let depthMap: [Float]
    public let depthWidth: Int
    public let depthHeight: Int
    public let confidenceMap: [UInt8]
    public let vertices: [SIMD3<Float>]
    public let faces: [SIMD3<UInt32>]
    public let normals: [SIMD3<Float>]
    public let cameraIntrinsics: simd_float3x3
    public let cameraTransform: simd_float4x4
    public let deviceModel: String
    public let timestamp: Date

    public init(
        rgbImageData: Data,
        imageWidth: Int,
        imageHeight: Int,
        depthMap: [Float],
        depthWidth: Int,
        depthHeight: Int,
        confidenceMap: [UInt8],
        vertices: [SIMD3<Float>],
        faces: [SIMD3<UInt32>],
        normals: [SIMD3<Float>],
        cameraIntrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        deviceModel: String,
        timestamp: Date = Date()
    ) {
        self.rgbImageData = rgbImageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.depthMap = depthMap
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.confidenceMap = confidenceMap
        self.vertices = vertices
        self.faces = faces
        self.normals = normals
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraTransform = cameraTransform
        self.deviceModel = deviceModel
        self.timestamp = timestamp
    }
}

// MARK: - Tracking State

public enum TrackingState: Sendable {
    case notAvailable
    case limited(reason: TrackingLimitedReason)
    case normal
}

public enum TrackingLimitedReason: Sendable {
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
}
