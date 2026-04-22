import Foundation
import simd

// MARK: - CaptureData ↔ CaptureSnapshot Bridge

extension CaptureData {

    /// Convert Codable CaptureData back to in-memory CaptureSnapshot.
    /// Used by the V5 coordinator to bridge CaptureBundle into the
    /// existing V4 boundary/measurement pipeline.
    public func toCaptureSnapshot(timestamp: Date = Date()) -> CaptureSnapshot {
        CaptureSnapshot(
            rgbImageData: rgbImageData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            depthMap: unpackDepthMap(),
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            confidenceMap: Array(confidenceMapData),
            vertices: unpackVertices(),
            faces: unpackFaces(),
            normals: unpackNormals(),
            cameraIntrinsics: intrinsicsMatrix,
            cameraTransform: transformMatrix,
            deviceModel: deviceModel,
            timestamp: timestamp
        )
    }
}

extension CaptureSnapshot {

    /// Pack a CaptureSnapshot into a Codable CaptureData for storage.
    public func toCaptureData(lidarAvailable: Bool = true) -> CaptureData {
        // Pack vertices: 12 bytes each (x, y, z as Float)
        var verticesData = Data(capacity: vertices.count * 12)
        for v in vertices {
            var x = v.x; var y = v.y; var z = v.z
            verticesData.append(Data(bytes: &x, count: 4))
            verticesData.append(Data(bytes: &y, count: 4))
            verticesData.append(Data(bytes: &z, count: 4))
        }

        // Pack faces: 12 bytes each (i0, i1, i2 as UInt32)
        var facesData = Data(capacity: faces.count * 12)
        for f in faces {
            var i0 = f.x; var i1 = f.y; var i2 = f.z
            facesData.append(Data(bytes: &i0, count: 4))
            facesData.append(Data(bytes: &i1, count: 4))
            facesData.append(Data(bytes: &i2, count: 4))
        }

        // Pack normals: 12 bytes each
        var normalsData = Data(capacity: normals.count * 12)
        for n in normals {
            var x = n.x; var y = n.y; var z = n.z
            normalsData.append(Data(bytes: &x, count: 4))
            normalsData.append(Data(bytes: &y, count: 4))
            normalsData.append(Data(bytes: &z, count: 4))
        }

        // Pack depth map
        var depthData = Data(capacity: depthMap.count * 4)
        for d in depthMap {
            var value = d
            depthData.append(Data(bytes: &value, count: 4))
        }

        // Pack intrinsics (column-major)
        let m = cameraIntrinsics
        let intrinsics: [Float] = [
            m[0][0], m[0][1], m[0][2],
            m[1][0], m[1][1], m[1][2],
            m[2][0], m[2][1], m[2][2],
        ]

        // Pack transform (column-major)
        let t = cameraTransform
        let transform: [Float] = [
            t[0][0], t[0][1], t[0][2], t[0][3],
            t[1][0], t[1][1], t[1][2], t[1][3],
            t[2][0], t[2][1], t[2][2], t[2][3],
            t[3][0], t[3][1], t[3][2], t[3][3],
        ]

        return CaptureData(
            rgbImageData: rgbImageData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            depthMapData: depthData,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            confidenceMapData: Data(confidenceMap),
            meshVerticesData: verticesData,
            meshFacesData: facesData,
            meshNormalsData: normalsData,
            vertexCount: vertices.count,
            faceCount: faces.count,
            cameraIntrinsics: intrinsics,
            cameraTransform: transform,
            deviceModel: deviceModel,
            lidarAvailable: lidarAvailable
        )
    }
}
