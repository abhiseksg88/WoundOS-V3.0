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
        guard cameraIntrinsics.count == 9 else { return matrix_identity_float3x3 }
        return simd_float3x3(
            SIMD3<Float>(cameraIntrinsics[0], cameraIntrinsics[1], cameraIntrinsics[2]),
            SIMD3<Float>(cameraIntrinsics[3], cameraIntrinsics[4], cameraIntrinsics[5]),
            SIMD3<Float>(cameraIntrinsics[6], cameraIntrinsics[7], cameraIntrinsics[8])
        )
    }

    /// Reconstruct the 4×4 camera transform from stored column-major floats.
    public var transformMatrix: simd_float4x4 {
        guard cameraTransform.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4<Float>(cameraTransform[0], cameraTransform[1], cameraTransform[2], cameraTransform[3]),
            SIMD4<Float>(cameraTransform[4], cameraTransform[5], cameraTransform[6], cameraTransform[7]),
            SIMD4<Float>(cameraTransform[8], cameraTransform[9], cameraTransform[10], cameraTransform[11]),
            SIMD4<Float>(cameraTransform[12], cameraTransform[13], cameraTransform[14], cameraTransform[15])
        )
    }

    /// Unpack mesh vertices from binary data into an array of 3D points.
    /// Returns empty array if data is inconsistent (prevents precondition crash).
    public func unpackVertices() -> [SIMD3<Float>] {
        guard meshVerticesData.count == vertexCount * 12 else { return [] }
        var vertices = [SIMD3<Float>]()
        vertices.reserveCapacity(vertexCount)
        meshVerticesData.withUnsafeBytes { raw in
            for i in 0..<vertexCount {
                let offset = i * 12
                let x = raw.load(fromByteOffset: offset, as: Float.self)
                let y = raw.load(fromByteOffset: offset + 4, as: Float.self)
                let z = raw.load(fromByteOffset: offset + 8, as: Float.self)
                vertices.append(SIMD3<Float>(x, y, z))
            }
        }
        return vertices
    }

    /// Unpack mesh faces from binary data into an array of index triples.
    /// Returns empty array if data is inconsistent (prevents precondition crash).
    public func unpackFaces() -> [SIMD3<UInt32>] {
        guard meshFacesData.count == faceCount * 12 else { return [] }
        var faces = [SIMD3<UInt32>]()
        faces.reserveCapacity(faceCount)
        meshFacesData.withUnsafeBytes { raw in
            for i in 0..<faceCount {
                let offset = i * 12
                let i0 = raw.load(fromByteOffset: offset, as: UInt32.self)
                let i1 = raw.load(fromByteOffset: offset + 4, as: UInt32.self)
                let i2 = raw.load(fromByteOffset: offset + 8, as: UInt32.self)
                faces.append(SIMD3<UInt32>(i0, i1, i2))
            }
        }
        return faces
    }

    /// Unpack mesh normals from binary data.
    /// Returns empty array if data is inconsistent (prevents precondition crash).
    public func unpackNormals() -> [SIMD3<Float>] {
        guard meshNormalsData.count == vertexCount * 12 else { return [] }
        var normals = [SIMD3<Float>]()
        normals.reserveCapacity(vertexCount)
        meshNormalsData.withUnsafeBytes { raw in
            for i in 0..<vertexCount {
                let offset = i * 12
                let x = raw.load(fromByteOffset: offset, as: Float.self)
                let y = raw.load(fromByteOffset: offset + 4, as: Float.self)
                let z = raw.load(fromByteOffset: offset + 8, as: Float.self)
                normals.append(SIMD3<Float>(x, y, z))
            }
        }
        return normals
    }

    /// Unpack depth map into a flat array of Float values (meters).
    public func unpackDepthMap() -> [Float] {
        guard depthMapData.count >= depthWidth * depthHeight * 4 else { return [] }
        return depthMapData.withUnsafeBytes { raw in
            var values = [Float]()
            values.reserveCapacity(depthWidth * depthHeight)
            for i in 0..<(depthWidth * depthHeight) {
                values.append(raw.load(fromByteOffset: i * 4, as: Float.self))
            }
            return values
        }
    }
}
