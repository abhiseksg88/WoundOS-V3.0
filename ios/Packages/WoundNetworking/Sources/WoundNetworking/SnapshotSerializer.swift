import Foundation
import ImageIO
import CoreGraphics
import WoundCore

// MARK: - Snapshot Serializer

/// Serializes a WoundScan into a multipart/form-data upload payload.
/// Compresses depth map to float16, binary-encodes mesh data,
/// and JSON-encodes metadata.
public enum SnapshotSerializer {

    /// Serialize a scan into multipart parts for upload.
    public static func serialize(_ scan: WoundScan) throws -> [MultipartPart] {
        var parts = [MultipartPart]()

        // 1. RGB image (JPEG, resized to 1920px max for upload)
        let optimizedRGB = optimizeImageForUpload(scan.captureData.rgbImageData)
        parts.append(MultipartPart(
            name: "rgb_image",
            filename: "rgb.jpg",
            mimeType: "image/jpeg",
            data: optimizedRGB
        ))

        // 2. Depth map (compressed float16)
        let depthFloat16 = compressDepthToFloat16(scan.captureData.depthMapData)
        parts.append(MultipartPart(
            name: "depth_map",
            filename: "depth.bin",
            mimeType: "application/octet-stream",
            data: depthFloat16
        ))

        // 3. Mesh data (binary: vertex count, vertices, face count, faces)
        let meshData = packMeshBinary(
            verticesData: scan.captureData.meshVerticesData,
            facesData: scan.captureData.meshFacesData,
            vertexCount: scan.captureData.vertexCount,
            faceCount: scan.captureData.faceCount
        )
        parts.append(MultipartPart(
            name: "mesh",
            filename: "mesh.bin",
            mimeType: "application/octet-stream",
            data: meshData
        ))

        // 4. Metadata JSON
        let qualityScore: QualityScoreData? = scan.primaryMeasurement.qualityScore.map { q in
            QualityScoreData(
                trackingStableSeconds: q.trackingStableSeconds,
                captureDistanceM: q.captureDistanceM,
                meshVertexCount: q.meshVertexCount,
                meanDepthConfidence: q.meanDepthConfidence,
                meshHitRate: q.meshHitRate,
                angularVelocityRadPerSec: q.angularVelocityRadPerSec
            )
        }

        let metadata = ScanUploadMetadata(
            scanId: scan.id.uuidString,
            patientId: scan.patientId,
            nurseId: scan.nurseId,
            facilityId: scan.facilityId,
            capturedAt: scan.capturedAt,
            cameraIntrinsics: scan.captureData.cameraIntrinsics.map { Double($0) },
            cameraTransform: scan.captureData.cameraTransform.map { Double($0) },
            imageWidth: scan.captureData.imageWidth,
            imageHeight: scan.captureData.imageHeight,
            depthWidth: scan.captureData.depthWidth,
            depthHeight: scan.captureData.depthHeight,
            deviceModel: scan.captureData.deviceModel,
            lidarAvailable: scan.captureData.lidarAvailable,
            boundaryPoints2d: scan.nurseBoundary.points2D.map { [Double($0.x), Double($0.y)] },
            boundaryType: scan.nurseBoundary.boundaryType.rawValue,
            boundarySource: scan.nurseBoundary.source.rawValue,
            tapPoint: scan.nurseBoundary.tapPoint.map { [Double($0.x), Double($0.y)] },
            primaryMeasurement: MeasurementData(
                areaCm2: scan.primaryMeasurement.areaCm2,
                maxDepthMm: scan.primaryMeasurement.maxDepthMm,
                meanDepthMm: scan.primaryMeasurement.meanDepthMm,
                volumeMl: scan.primaryMeasurement.volumeMl,
                lengthMm: scan.primaryMeasurement.lengthMm,
                widthMm: scan.primaryMeasurement.widthMm,
                perimeterMm: scan.primaryMeasurement.perimeterMm,
                processingTimeMs: scan.primaryMeasurement.processingTimeMs
            ),
            pushScore: PushScoreData(
                lengthTimesWidthCm2: scan.pushScore.lengthTimesWidthCm2,
                exudateAmount: scan.pushScore.exudateAmount.rawValue,
                tissueType: scan.pushScore.tissueType.rawValue,
                totalScore: scan.pushScore.totalScore
            ),
            qualityScore: qualityScore
        )

        let metadataJSON = try JSONEncoder.woundOS.encode(metadata)
        parts.append(MultipartPart(
            name: "metadata",
            filename: "metadata.json",
            mimeType: "application/json",
            data: metadataJSON
        ))

        return parts
    }

    // MARK: - Image Optimization

    /// Resize JPEG image to max 1920px on longest side and recompress at 0.75 quality.
    /// Uses ImageIO for efficient decode-resize-encode without UIKit.
    /// Falls back to original data if processing fails.
    public static func optimizeImageForUpload(
        _ imageData: Data,
        maxDimension: Int = 1920,
        quality: Double = 0.75
    ) -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return imageData
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return imageData
        }

        let destData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            destData,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return imageData
        }

        CGImageDestinationAddImage(
            dest,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )

        guard CGImageDestinationFinalize(dest) else {
            return imageData
        }

        return destData as Data
    }

    // MARK: - Float32 → Float16 Compression

    /// Compress float32 depth data to float16 to halve upload size.
    private static func compressDepthToFloat16(_ float32Data: Data) -> Data {
        let float32Array = float32Data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float32.self))
        }

        var float16Data = Data(capacity: float32Array.count * 2)

        for value in float32Array {
            var f16 = floatToFloat16(value)
            withUnsafeBytes(of: &f16) { float16Data.append(contentsOf: $0) }
        }

        return float16Data
    }

    /// IEEE 754 float32 → float16 conversion.
    private static func floatToFloat16(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 31) & 1)
        let exponent = Int((bits >> 23) & 0xFF) - 127
        let mantissa = bits & 0x7FFFFF

        if exponent > 15 {
            return (sign << 15) | 0x7C00 // Overflow → Infinity
        } else if exponent < -14 {
            return sign << 15 // Underflow → 0
        } else {
            let f16Exp = UInt16(exponent + 15)
            let f16Man = UInt16(mantissa >> 13)
            return (sign << 15) | (f16Exp << 10) | f16Man
        }
    }

    // MARK: - Mesh Binary Packing

    /// Pack mesh data into a binary format:
    /// [vertexCount: UInt32][vertices: Float×3×N][faceCount: UInt32][faces: UInt32×3×M]
    private static func packMeshBinary(
        verticesData: Data,
        facesData: Data,
        vertexCount: Int,
        faceCount: Int
    ) -> Data {
        var data = Data()

        var vc = UInt32(vertexCount)
        withUnsafeBytes(of: &vc) { data.append(contentsOf: $0) }
        data.append(verticesData)

        var fc = UInt32(faceCount)
        withUnsafeBytes(of: &fc) { data.append(contentsOf: $0) }
        data.append(facesData)

        return data
    }
}

// MARK: - Multipart Part

public struct MultipartPart: Sendable {
    public let name: String
    public let filename: String
    public let mimeType: String
    public let data: Data

    public init(name: String, filename: String, mimeType: String, data: Data) {
        self.name = name
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

// MARK: - JSON Coders

extension JSONEncoder {
    public static let woundOS: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

extension JSONDecoder {
    public static let woundOS: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
