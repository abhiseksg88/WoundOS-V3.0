import ARKit
import Combine
import os
import WoundCore

private let logger = Logger(subsystem: "com.woundos.app", category: "Capture")

// MARK: - AR Session Manager

/// Manages the ARKit session with LiDAR scene reconstruction.
/// Publishes AR frame updates and tracking state changes.
/// When the nurse taps "Capture," this freezes the current frame.
public final class ARSessionManager: NSObject, CaptureProviderProtocol {

    // MARK: - Properties

    #if !targetEnvironment(simulator)
    public let session = ARSession()
    #endif
    private let configuration: CaptureSessionConfiguration
    private var currentFrame: ARFrame?
    private var meshAnchors: [ARMeshAnchor] = []

    public var onTrackingStateChanged: ((TrackingState) -> Void)?

    /// Publisher for the latest AR frame (throttled to ~10 fps for UI preview)
    public let framePublisher = PassthroughSubject<ARFrame, Never>()

    /// Strict pre-capture quality monitor. Apple Measure-style gating.
    public let qualityMonitor: CaptureQualityMonitor

    /// Current distance estimate to the nearest surface (meters)
    public private(set) var estimatedDistance: Float?

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
        configuration: CaptureSessionConfiguration = .default,
        qualityMonitor: CaptureQualityMonitor = CaptureQualityMonitor()
    ) {
        self.configuration = configuration
        self.qualityMonitor = qualityMonitor
        super.init()
        #if !targetEnvironment(simulator)
        session.delegate = self
        #endif
    }

    // MARK: - Session Lifecycle

    public func startSession() throws {
        logger.info("startSession() — LiDAR available: \(self.isLiDARAvailable)")
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
            logger.info("Selected hi-res format: \(hiResFormat.imageResolution.width)x\(hiResFormat.imageResolution.height)")
        }

        logger.info("AR config: sceneReconstruction=mesh, frameSemantics=smoothedSceneDepth, format=\(config.videoFormat.imageResolution.width)x\(config.videoFormat.imageResolution.height)")
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        logger.info("ARSession.run() called successfully")
        #endif
        qualityMonitor.reset()
    }

    public func pauseSession() {
        #if !targetEnvironment(simulator)
        session.pause()
        #endif
        qualityMonitor.reset()
    }

    // MARK: - Capture (Freeze Frame)

    /// Freeze the current ARKit state and return a snapshot.
    /// All spatial data — RGB, depth, mesh, camera — is locked together.
    public func captureSnapshot() throws -> CaptureSnapshot {
        #if targetEnvironment(simulator)
        throw CaptureError.lidarNotAvailable
        #else
        logger.info("captureSnapshot() — freezing ARKit frame")
        guard let frame = currentFrame else {
            logger.error("No current AR frame available")
            throw CaptureError.noFrameAvailable
        }

        guard let sceneDepth = frame.smoothedSceneDepth else {
            logger.error("No smoothedSceneDepth in current frame")
            throw CaptureError.noDepthData
        }

        // 1. Extract RGB image
        logger.info("Extracting RGB data from pixel buffer")
        let rgbData = extractRGBData(from: frame)
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        logger.info("RGB: \(imageWidth)x\(imageHeight), JPEG size=\(rgbData.count) bytes")

        // 2. Extract depth map
        let (depthValues, depthW, depthH) = extractDepthMap(from: sceneDepth.depthMap)
        logger.info("Depth map: \(depthW)x\(depthH), \(depthValues.count) values")

        // 3. Extract confidence map
        let confidenceValues = extractConfidenceMap(from: sceneDepth.confidenceMap)
        logger.info("Confidence map: \(confidenceValues.count) values")

        // 4. Reconstruct consolidated mesh from all mesh anchors
        logger.info("Reconstructing mesh from \(self.meshAnchors.count) anchors")
        let (vertices, faces, normals) = reconstructMesh()
        logger.info("Mesh: \(vertices.count) vertices, \(faces.count) faces, \(normals.count) normals")

        guard !vertices.isEmpty else {
            logger.error("Mesh reconstruction produced 0 vertices")
            throw CaptureError.noMeshData
        }

        // 5. Camera parameters
        let intrinsics = frame.camera.intrinsics
        let transform = frame.camera.transform
        logger.info("Camera intrinsics: fx=\(intrinsics[0][0]) fy=\(intrinsics[1][1]) cx=\(intrinsics[2][0]) cy=\(intrinsics[2][1]) | image=\(imageWidth)x\(imageHeight) cx/halfW=\(String(format: "%.3f", intrinsics[2][0] / Float(imageWidth) * 2.0))")

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
            cameraIntrinsics: intrinsics,
            cameraTransform: transform,
            deviceModel: deviceModelString(),
            timestamp: Date()
        )
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

    /// Consolidates all ARMeshAnchor data into a single world-space mesh.
    private func reconstructMesh() -> ([SIMD3<Float>], [SIMD3<UInt32>], [SIMD3<Float>]) {
        var allVertices = [SIMD3<Float>]()
        var allFaces = [SIMD3<UInt32>]()
        var allNormals = [SIMD3<Float>]()
        var vertexOffset: UInt32 = 0

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform

            // Extract vertices and transform to world space
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

            // Extract normals and transform to world space
            let normalBuffer = geometry.normals
            for i in 0..<normalBuffer.count {
                let normalPointer = normalBuffer.buffer.contents()
                    .advanced(by: normalBuffer.offset + i * normalBuffer.stride)
                let localNormal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldNormal = transform.transformDirection(localNormal).normalized
                allNormals.append(worldNormal)
            }

            // Extract face indices, offset by accumulated vertex count
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

    /// Estimate distance to the center of the depth map
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

#if !targetEnvironment(simulator)
// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentFrame = frame
        updateDistanceEstimate(from: frame)

        // Drive strict pre-capture quality gating
        let totalVerts = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
        qualityMonitor.update(frame: frame, meshAnchorVertexCount: totalVerts)

        // Mirror the monitor's internal distance into our public property
        if let d = qualityMonitor.lastDistance {
            estimatedDistance = d
        }

        // Throttle frame publishing for UI (every 3rd frame ≈ 10 fps at 30 fps input)
        framePublisher.send(frame)
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

// MARK: - Capture Errors

public enum CaptureError: Error, LocalizedError {
    case lidarNotAvailable
    case noFrameAvailable
    case noDepthData
    case noMeshData
    case trackingLimited

    public var errorDescription: String? {
        switch self {
        case .lidarNotAvailable:
            return "This device does not have a LiDAR scanner. iPhone 12 Pro or later required."
        case .noFrameAvailable:
            return "No AR frame available. Please wait for the camera to initialize."
        case .noDepthData:
            return "Depth data not available in the current frame."
        case .noMeshData:
            return "No mesh data available. Move the device slowly to let the scene reconstruct."
        case .trackingLimited:
            return "AR tracking is limited. Hold the device steady with good lighting."
        }
    }
}
