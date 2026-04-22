import ARKit
import Combine
import os
import WoundCore

private let logger = Logger(subsystem: "com.woundos.app", category: "V5Capture")

// MARK: - V5 LiDAR Capture Session

/// V5-enhanced LiDAR capture session. Conforms to the same protocol as
/// ARSessionManager but provides richer quality data, confidence heatmap
/// generation, and publishers for SwiftUI-driven guided capture UI.
///
/// This is a separate class from ARSessionManager (not a subclass) to
/// ensure V4 code paths are completely untouched when the V5 feature
/// flag is OFF.
public final class LiDARCaptureSession: NSObject, CaptureProviderProtocol {

    // MARK: - Properties

    #if !targetEnvironment(simulator)
    public let session = ARSession()
    #endif
    private let configuration: CaptureSessionConfiguration
    private var currentFrame: ARFrame?
    private var meshAnchors: [ARMeshAnchor] = []
    private var sessionStartTime: Date?

    public var onTrackingStateChanged: ((TrackingState) -> Void)?

    /// V5 quality monitor (tighter distance range by default)
    public let qualityMonitor: CaptureQualityMonitor

    /// Publishes continuous readiness state for SwiftUI binding
    public let readinessPublisher = PassthroughSubject<CaptureReadiness, Never>()

    /// Publishes live distance for the distance ring view
    public let distancePublisher = PassthroughSubject<Float?, Never>()

    /// Publishes per-frame confidence summary for heatmap overlay
    public let confidencePublisher = PassthroughSubject<ConfidenceMapSummary, Never>()

    /// Current distance estimate to nearest surface (meters)
    public private(set) var estimatedDistance: Float?

    /// Number of mesh anchors accumulated in this session
    public var meshAnchorCount: Int { meshAnchors.count }

    /// How long the session has been running
    public var sessionDuration: TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - CaptureProviderProtocol

    public var isLiDARAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #endif
    }

    public var isSessionActive: Bool {
        currentFrame != nil
    }

    // MARK: - Init

    public init(
        configuration: CaptureSessionConfiguration = .v5Default,
        qualityMonitor: CaptureQualityMonitor? = nil
    ) {
        self.configuration = configuration
        self.qualityMonitor = qualityMonitor ?? CaptureQualityMonitor(
            configuration: .init(
                optimalDistance: configuration.optimalDistanceRange,
                stableThreshold: 1.5,
                minMeshVertices: 500,
                maxAngularVelocity: 0.05,
                motionWindowSeconds: 0.5
            )
        )
        super.init()
        #if !targetEnvironment(simulator)
        session.delegate = self
        #endif
    }

    // MARK: - Session Lifecycle

    public func startSession() throws {
        logger.info("V5 startSession() — LiDAR available: \(self.isLiDARAvailable)")
        guard isLiDARAvailable else {
            logger.error("LiDAR not available on this device")
            throw CaptureError.lidarNotAvailable
        }

        #if !targetEnvironment(simulator)
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.frameSemantics = [.smoothedSceneDepth]
        config.environmentTexturing = .automatic

        if configuration.preferredImageResolution == .high,
           let hiResFormat = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter({ $0.captureDevicePosition == .back })
            .max(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = hiResFormat
        }

        logger.info("V5 AR config: sceneReconstruction=mesh, frameSemantics=smoothedSceneDepth")
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        #endif

        sessionStartTime = Date()
        meshAnchors.removeAll()
        currentFrame = nil
        qualityMonitor.reset()
    }

    public func pauseSession() {
        #if !targetEnvironment(simulator)
        session.pause()
        #endif
        qualityMonitor.reset()
        sessionStartTime = nil
    }

    // MARK: - Capture (Freeze Frame)

    public func captureSnapshot() throws -> CaptureSnapshot {
        #if targetEnvironment(simulator)
        throw CaptureError.lidarNotAvailable
        #else
        logger.info("V5 captureSnapshot() — freezing frame")
        guard let frame = currentFrame else {
            throw CaptureError.noFrameAvailable
        }

        guard let sceneDepth = frame.smoothedSceneDepth else {
            throw CaptureError.noDepthData
        }

        let rgbData = extractRGBData(from: frame)
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)

        let (depthValues, depthW, depthH) = extractDepthMap(from: sceneDepth.depthMap)
        let confidenceValues = extractConfidenceMap(from: sceneDepth.confidenceMap)

        let (vertices, faces, normals) = reconstructMesh()
        guard !vertices.isEmpty else {
            throw CaptureError.noMeshData
        }

        logger.info("V5 capture: \(imageWidth)x\(imageHeight), \(vertices.count) verts, \(faces.count) faces")

        return CaptureSnapshot(
            rgbImageData: rgbData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            depthMap: depthValues,
            depthWidth: depthW,
            depthHeight: depthH,
            confidenceMap: confidenceValues,
            vertices: vertices,
            faces: faces,
            normals: normals,
            cameraIntrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            deviceModel: deviceModelString(),
            timestamp: Date()
        )
        #endif
    }

    // MARK: - V5: Confidence Map Summary

    /// Generates a confidence summary for the current frame.
    public func currentConfidenceSummary() -> ConfidenceMapSummary? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let frame = currentFrame,
              let depth = frame.smoothedSceneDepth else { return nil }
        return ConfidenceMapSummary(from: depth)
        #endif
    }

    // MARK: - RGB Extraction

    private func extractRGBData(from frame: ARFrame) -> Data {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return Data()
        }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.85) ?? Data()
    }

    // MARK: - Depth Extraction

    private func extractDepthMap(from depthBuffer: CVPixelBuffer) -> ([Float], Int, Int) {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return ([], width, height)
        }

        var depthValues = [Float]()
        depthValues.reserveCapacity(width * height)

        for row in 0..<height {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            for col in 0..<width {
                depthValues.append(rowPtr[col])
            }
        }

        return (depthValues, width, height)
    }

    // MARK: - Confidence Extraction

    private func extractConfidenceMap(from confidenceBuffer: CVPixelBuffer?) -> [UInt8] {
        guard let buffer = confidenceBuffer else { return [] }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return []
        }

        var values = [UInt8]()
        values.reserveCapacity(width * height)

        for row in 0..<height {
            let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                values.append(rowPtr[col])
            }
        }

        return values
    }

    // MARK: - Mesh Reconstruction

    private func reconstructMesh() -> ([SIMD3<Float>], [SIMD3<UInt32>], [SIMD3<Float>]) {
        var allVertices = [SIMD3<Float>]()
        var allFaces = [SIMD3<UInt32>]()
        var allNormals = [SIMD3<Float>]()
        var vertexOffset: UInt32 = 0

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform

            let vertexBuffer = geometry.vertices
            let vertexCount = vertexBuffer.count
            let vertexStride = vertexBuffer.stride

            for i in 0..<vertexCount {
                let vertexPointer = vertexBuffer.buffer.contents()
                    .advanced(by: vertexBuffer.offset + i * vertexStride)
                let localVertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldVertex = transform.transformPoint(localVertex)
                allVertices.append(worldVertex)
            }

            let normalBuffer = geometry.normals
            for i in 0..<normalBuffer.count {
                let normalPointer = normalBuffer.buffer.contents()
                    .advanced(by: normalBuffer.offset + i * normalBuffer.stride)
                let localNormal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldNormal = transform.transformDirection(localNormal).normalized
                allNormals.append(worldNormal)
            }

            let faceBuffer = geometry.faces
            let indexBuffer = faceBuffer.buffer
            let bytesPerIndex = faceBuffer.bytesPerIndex
            let faceCount = faceBuffer.count

            for i in 0..<faceCount {
                let faceOffset = faceBuffer.indexCountPerPrimitive * i
                var indices = SIMD3<UInt32>(0, 0, 0)

                for j in 0..<3 {
                    let indexOffset = (faceOffset + j) * bytesPerIndex
                    let ptr = indexBuffer.contents().advanced(by: indexOffset)
                    if bytesPerIndex == 4 {
                        indices[j] = ptr.assumingMemoryBound(to: UInt32.self).pointee + vertexOffset
                    } else {
                        indices[j] = UInt32(ptr.assumingMemoryBound(to: UInt16.self).pointee) + vertexOffset
                    }
                }

                allFaces.append(indices)
            }

            vertexOffset += UInt32(vertexCount)
        }

        return (allVertices, allFaces, allNormals)
    }

    // MARK: - Distance Estimation

    private func updateDistanceEstimate(from frame: ARFrame) {
        guard let depth = frame.smoothedSceneDepth?.depthMap else { return }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)

        guard let base = CVPixelBufferGetBaseAddress(depth) else { return }

        let centerRow = height / 2
        let centerCol = width / 2
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        let ptr = base.advanced(by: centerRow * bytesPerRow)
            .assumingMemoryBound(to: Float32.self)
        estimatedDistance = ptr[centerCol]
    }

    // MARK: - Helpers

    private func deviceModelString() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }
}

// MARK: - ARSessionDelegate

#if !targetEnvironment(simulator)
extension LiDARCaptureSession: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentFrame = frame
        updateDistanceEstimate(from: frame)

        let totalVerts = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
        qualityMonitor.update(frame: frame, meshAnchorVertexCount: totalVerts)

        if let d = qualityMonitor.lastDistance {
            estimatedDistance = d
        }

        // Publish for SwiftUI bindings
        distancePublisher.send(estimatedDistance)

        // Publish confidence summary (throttled by the subscriber)
        if let depth = frame.smoothedSceneDepth {
            let summary = ConfidenceMapSummary(from: depth)
            confidencePublisher.send(summary)
        }
    }

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let newMeshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        meshAnchors.append(contentsOf: newMeshAnchors)
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            if let index = meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                meshAnchors[index] = meshAnchor
            } else {
                meshAnchors.append(meshAnchor)
            }
        }
    }

    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removedIds = Set(anchors.map(\.identifier))
        meshAnchors.removeAll { removedIds.contains($0.identifier) }
    }

    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state: TrackingState
        switch camera.trackingState {
        case .notAvailable:
            state = .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing:
                state = .limited(reason: .initializing)
            case .excessiveMotion:
                state = .limited(reason: .excessiveMotion)
            case .insufficientFeatures:
                state = .limited(reason: .insufficientFeatures)
            case .relocalizing:
                state = .limited(reason: .relocalizing)
            @unknown default:
                state = .limited(reason: .initializing)
            }
        case .normal:
            state = .normal
        }
        onTrackingStateChanged?(state)
    }
}
#endif
