import Foundation
import simd

// MARK: - Capture Data

/// All data frozen at the moment the nurse taps "Capture."
/// ARKit frame, LiDAR depth, reconstructed mesh, and camera parameters
/// are locked together so every downstream computation uses the same
/// spatial reference.
public struct CaptureData: Codable, Sendable {
    /// JPEG-compressed RGB image bytes from the ARFrame
    public let rgbImageData: Data

    /// Width of the captured RGB image in pixels
    public let imageWidth: Int

    /// Height of the captured RGB image in pixels
    public let imageHeight: Int

    /// Float32 depth values, row-major, meters from camera.
    /// Dimensions match `depthWidth × depthHeight`.
    public let depthMapData: Data

    /// Width of the depth map (typically 256)
    public let depthWidth: Int

    /// Height of the depth map (typically 192)
    public let depthHeight: Int

    /// Per-pixel confidence (0 = low, 1 = medium, 2 = high).
    /// Same dimensions as depth map.
    public let confidenceMapData: Data

    /// Packed mesh vertices as [Float] (x,y,z triples in world space).
    public let meshVerticesData: Data

    /// Packed mesh face indices as [UInt32] (i0, i1, i2 triples).
    public let meshFacesData: Data

    /// Packed mesh vertex normals as [Float] (nx, ny, nz triples).
    public let meshNormalsData: Data

    /// Number of vertices in the mesh
    public let vertexCount: Int

    /// Number of triangular faces in the mesh
    public let faceCount: Int

    /// 3×3 camera intrinsics matrix (column-major floats).
    public let cameraIntrinsics: [Float]

    /// 4×4 camera-to-world transform (column-major floats).
    public let cameraTransform: [Float]

    /// Device model string, e.g. "iPhone14,3"
    public let deviceModel: String

    /// Whether LiDAR was available and used for this capture
    public let lidarAvailable: Bool

    public init(
        rgbImageData: Data,
        imageWidth: Int,
        imageHeight: Int,
        depthMapData: Data,
        depthWidth: Int,
        depthHeight: Int,
        confidenceMapData: Data,
        meshVerticesData: Data,
        meshFacesData: Data,
        meshNormalsData: Data,
        vertexCount: Int,
        faceCount: Int,
        cameraIntrinsics: [Float],
        cameraTransform: [Float],
        deviceModel: String,
        lidarAvailable: Bool
    ) {
        self.rgbImageData = rgbImageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.depthMapData = depthMapData
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.confidenceMapData = confidenceMapData
        self.meshVerticesData = meshVerticesData
        self.meshFacesData = meshFacesData
        self.meshNormalsData = meshNormalsData
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraTransform = cameraTransform
        self.deviceModel = deviceModel
        self.lidarAvailable = lidarAvailable
    }
}

// MARK: - Convenience Accessors

extension CaptureData {

    /// Reconstruct the 3×3 intrinsics matrix from stored column-major floats.
    public var intrinsicsMatrix: simd_float3x3 {
        precondition(cameraIntrinsics.count == 9)
        return simd_float3x3(
            SIMD3<Float>(cameraIntrinsics[0], cameraIntrinsics[1], cameraIntrinsics[2]),
            SIMD3<Float>(cameraIntrinsics[3], cameraIntrinsics[4], cameraIntrinsics[5]),
            SIMD3<Float>(cameraIntrinsics[6], cameraIntrinsics[7], cameraIntrinsics[8])
        )
    }

    /// Reconstruct the 4×4 camera transform from stored column-major floats.
    public var transformMatrix: simd_float4x4 {
        precondition(cameraTransform.count == 16)
        return simd_float4x4(
            SIMD4<Float>(cameraTransform[0], cameraTransform[1], cameraTransform[2], cameraTransform[3]),
            SIMD4<Float>(cameraTransform[4], cameraTransform[5], cameraTransform[6], cameraTransform[7]),
            SIMD4<Float>(cameraTransform[8], cameraTransform[9], cameraTransform[10], cameraTransform[11]),
            SIMD4<Float>(cameraTransform[12], cameraTransform[13], cameraTransform[14], cameraTransform[15])
        )
    }

    /// Unpack mesh vertices from binary data into an array of 3D points.
    public func unpackVertices() -> [SIMD3<Float>] {
        let floats = meshVerticesData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        precondition(floats.count == vertexCount * 3)
        var vertices = [SIMD3<Float>]()
        vertices.reserveCapacity(vertexCount)
        for i in stride(from: 0, to: floats.count, by: 3) {
            vertices.append(SIMD3<Float>(floats[i], floats[i + 1], floats[i + 2]))
        }
        return vertices
    }

    /// Unpack mesh faces from binary data into an array of index triples.
    public func unpackFaces() -> [SIMD3<UInt32>] {
        let indices = meshFacesData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: UInt32.self))
        }
        precondition(indices.count == faceCount * 3)
        var faces = [SIMD3<UInt32>]()
        faces.reserveCapacity(faceCount)
        for i in stride(from: 0, to: indices.count, by: 3) {
            faces.append(SIMD3<UInt32>(indices[i], indices[i + 1], indices[i + 2]))
        }
        return faces
    }

    /// Unpack mesh normals from binary data.
    public func unpackNormals() -> [SIMD3<Float>] {
        let floats = meshNormalsData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        precondition(floats.count == vertexCount * 3)
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(vertexCount)
        for i in stride(from: 0, to: floats.count, by: 3) {
            normals.append(SIMD3<Float>(floats[i], floats[i + 1], floats[i + 2]))
        }
        return normals
    }

    /// Unpack depth map into a 2D array of Float values (meters).
    public func unpackDepthMap() -> [Float] {
        meshVerticesData.withUnsafeBytes { _ in () } // no-op, just for symmetry
        return depthMapData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
