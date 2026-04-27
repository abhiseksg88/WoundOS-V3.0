import Foundation
import UIKit

// MARK: - Capture Upload Payload

public struct CaptureUploadPayload: Codable, Sendable {
    public let captureId: String
    public let capturedAt: String
    public let device: DevicePayload
    public let capturedBy: CapturedByPayload
    public let pushScore: Double?
    public let notes: String
    public let segmentation: SegmentationPayload
    public let measurements: MeasurementsPayload
    public let manualMeasurements: ManualMeasurementsPayload?
    public let lidarMetadata: LiDARMetadataPayload
    public let artifacts: ArtifactsPayload

    enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case capturedAt = "captured_at"
        case device
        case capturedBy = "captured_by"
        case pushScore = "push_score"
        case notes
        case segmentation
        case measurements
        case manualMeasurements = "manual_measurements"
        case lidarMetadata = "lidar_metadata"
        case artifacts
    }

    public init(
        captureId: UUID,
        capturedAt: Date,
        device: DevicePayload,
        capturedBy: CapturedByPayload,
        pushScore: Double? = nil,
        notes: String,
        segmentation: SegmentationPayload,
        measurements: MeasurementsPayload,
        manualMeasurements: ManualMeasurementsPayload? = nil,
        lidarMetadata: LiDARMetadataPayload,
        artifacts: ArtifactsPayload
    ) {
        self.captureId = captureId.uuidString.lowercased()
        self.capturedAt = Self.formatDate(capturedAt)
        self.device = device
        self.capturedBy = capturedBy
        self.pushScore = pushScore
        self.notes = String(notes.prefix(2000))
        self.segmentation = segmentation
        self.measurements = measurements
        self.manualMeasurements = manualMeasurements
        self.lidarMetadata = lidarMetadata
        self.artifacts = artifacts
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Device

public struct DevicePayload: Codable, Sendable {
    public let model: String
    public let osVersion: String
    public let appVersion: String

    enum CodingKeys: String, CodingKey {
        case model
        case osVersion = "os_version"
        case appVersion = "app_version"
    }

    public init(model: String, osVersion: String, appVersion: String) {
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
    }

    public static func current(buildNumber: String? = nil) -> DevicePayload {
        let device = UIDevice.current
        let build = buildNumber
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        return DevicePayload(
            model: device.modelName,
            osVersion: device.systemVersion,
            appVersion: "v5-build-\(build)"
        )
    }
}

// MARK: - Captured By

public struct CapturedByPayload: Codable, Sendable {
    public let userId: String
    public let userName: String
    public let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userName = "user_name"
        case role
    }

    public init(userId: String, userName: String, role: String = "nurse") {
        self.userId = userId
        self.userName = userName
        self.role = role
    }

    public init(from user: VerifiedUser) {
        self.userId = user.userId
        self.userName = user.name
        self.role = user.role
    }
}

// MARK: - Segmentation

public struct SegmentationPayload: Codable, Sendable {
    public let segmenter: String
    public let modelVersion: String
    public let modelSha256: String
    public let confidence: Double
    public let maskCoveragePct: Double
    public let fallbackTriggered: Bool
    public let fallbackReason: String?
    public let qualityGateResult: String

    enum CodingKeys: String, CodingKey {
        case segmenter
        case modelVersion = "model_version"
        case modelSha256 = "model_sha256"
        case confidence
        case maskCoveragePct = "mask_coverage_pct"
        case fallbackTriggered = "fallback_triggered"
        case fallbackReason = "fallback_reason"
        case qualityGateResult = "quality_gate_result"
    }

    public init(
        segmenter: String = "coreml.boundaryseg.v1.2",
        modelVersion: String = "1.2",
        modelSha256: String = "0a5b7bb951f5cb47dcc37b81e3fc352643dfe8f2df433d17f25bc4b2b5658a44",
        confidence: Double,
        maskCoveragePct: Double,
        fallbackTriggered: Bool = false,
        fallbackReason: String? = nil,
        qualityGateResult: String = "accept"
    ) {
        self.segmenter = segmenter
        self.modelVersion = modelVersion
        self.modelSha256 = modelSha256
        self.confidence = confidence
        self.maskCoveragePct = maskCoveragePct
        self.fallbackTriggered = fallbackTriggered
        self.fallbackReason = fallbackReason
        self.qualityGateResult = qualityGateResult
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segmenter, forKey: .segmenter)
        try container.encode(modelVersion, forKey: .modelVersion)
        try container.encode(modelSha256, forKey: .modelSha256)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(maskCoveragePct, forKey: .maskCoveragePct)
        try container.encode(fallbackTriggered, forKey: .fallbackTriggered)
        if let reason = fallbackReason {
            try container.encode(reason, forKey: .fallbackReason)
        } else {
            try container.encodeNil(forKey: .fallbackReason)
        }
        try container.encode(qualityGateResult, forKey: .qualityGateResult)
    }
}

// MARK: - Measurements

public struct MeasurementsPayload: Codable, Sendable {
    public let lengthCm: Double?
    public let widthCm: Double?
    public let areaCm2: Double?
    public let perimeterCm: Double?
    public let depthCm: Double?

    enum CodingKeys: String, CodingKey {
        case lengthCm = "length_cm"
        case widthCm = "width_cm"
        case areaCm2 = "area_cm2"
        case perimeterCm = "perimeter_cm"
        case depthCm = "depth_cm"
    }

    public init(
        lengthCm: Double?,
        widthCm: Double?,
        areaCm2: Double?,
        perimeterCm: Double?,
        depthCm: Double?
    ) {
        self.lengthCm = lengthCm
        self.widthCm = widthCm
        self.areaCm2 = areaCm2
        self.perimeterCm = perimeterCm
        self.depthCm = depthCm
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let v = lengthCm { try container.encode(v, forKey: .lengthCm) } else { try container.encodeNil(forKey: .lengthCm) }
        if let v = widthCm { try container.encode(v, forKey: .widthCm) } else { try container.encodeNil(forKey: .widthCm) }
        if let v = areaCm2 { try container.encode(v, forKey: .areaCm2) } else { try container.encodeNil(forKey: .areaCm2) }
        if let v = perimeterCm { try container.encode(v, forKey: .perimeterCm) } else { try container.encodeNil(forKey: .perimeterCm) }
        if let v = depthCm { try container.encode(v, forKey: .depthCm) } else { try container.encodeNil(forKey: .depthCm) }
    }
}

// MARK: - Manual Measurements

public struct ManualMeasurementsPayload: Codable, Sendable {
    public let lengthCm: Double?
    public let widthCm: Double?
    public let depthCm: Double?
    public let method: String

    enum CodingKeys: String, CodingKey {
        case lengthCm = "length_cm"
        case widthCm = "width_cm"
        case depthCm = "depth_cm"
        case method
    }

    public init(lengthCm: Double?, widthCm: Double?, depthCm: Double?, method: String) {
        self.lengthCm = lengthCm
        self.widthCm = widthCm
        self.depthCm = depthCm
        self.method = method
    }
}

// MARK: - LiDAR Metadata

public struct LiDARMetadataPayload: Codable, Sendable {
    public let captureDistanceCm: Double
    public let lidarConfidencePct: Int
    public let frameCount: Int

    enum CodingKeys: String, CodingKey {
        case captureDistanceCm = "capture_distance_cm"
        case lidarConfidencePct = "lidar_confidence_pct"
        case frameCount = "frame_count"
    }

    public init(captureDistanceCm: Double, lidarConfidencePct: Int, frameCount: Int) {
        self.captureDistanceCm = captureDistanceCm
        self.lidarConfidencePct = lidarConfidencePct
        self.frameCount = frameCount
    }
}

// MARK: - Artifacts

public struct ArtifactsPayload: Codable, Sendable {
    public let rgbImageBase64: String
    public let maskImageBase64: String
    public let overlayImageBase64: String

    enum CodingKeys: String, CodingKey {
        case rgbImageBase64 = "rgb_image_base64"
        case maskImageBase64 = "mask_image_base64"
        case overlayImageBase64 = "overlay_image_base64"
    }

    public init(rgbImageBase64: String, maskImageBase64: String, overlayImageBase64: String) {
        self.rgbImageBase64 = rgbImageBase64
        self.maskImageBase64 = maskImageBase64
        self.overlayImageBase64 = overlayImageBase64
    }

    public init(rgbImage: UIImage, maskImage: UIImage, overlayImage: UIImage) {
        self.rgbImageBase64 = rgbImage.pngData()?.base64EncodedString() ?? ""
        self.maskImageBase64 = maskImage.pngData()?.base64EncodedString() ?? ""
        self.overlayImageBase64 = overlayImage.pngData()?.base64EncodedString() ?? ""
    }
}

// MARK: - UIDevice Model Name

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return result }
            return result + String(UnicodeScalar(UInt8(value)))
        }
        return mapDeviceIdentifier(identifier)
    }

    private func mapDeviceIdentifier(_ identifier: String) -> String {
        switch identifier {
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        default: return identifier
        }
    }
}
