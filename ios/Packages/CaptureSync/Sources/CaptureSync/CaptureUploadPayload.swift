import Foundation
import UIKit

// MARK: - Capture Upload Payload

public struct CaptureUploadPayload: Codable, Sendable {
    public let captureId: String
    public let capturedAt: String
    public let device: DevicePayload
    public let capturedBy: CapturedByPayload
    public let patient: PatientContextPayload?
    public let encounter: EncounterContextPayload?
    public let pushScore: Double?
    public let pushScoreDetail: PUSHScoreDetailPayload?
    public let clinicalAssessment: ClinicalAssessmentPayload?
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
        case patient
        case encounter
        case pushScore = "push_score"
        case pushScoreDetail = "push_score_detail"
        case clinicalAssessment = "clinical_assessment"
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
        patient: PatientContextPayload? = nil,
        encounter: EncounterContextPayload? = nil,
        pushScore: Double? = nil,
        pushScoreDetail: PUSHScoreDetailPayload? = nil,
        clinicalAssessment: ClinicalAssessmentPayload? = nil,
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
        self.patient = patient
        self.encounter = encounter
        self.pushScore = pushScore
        self.pushScoreDetail = pushScoreDetail
        self.clinicalAssessment = clinicalAssessment
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
    public let meanDepthCm: Double?
    public let volumeMl: Double?

    enum CodingKeys: String, CodingKey {
        case lengthCm = "length_cm"
        case widthCm = "width_cm"
        case areaCm2 = "area_cm2"
        case perimeterCm = "perimeter_cm"
        case depthCm = "depth_cm"
        case meanDepthCm = "mean_depth_cm"
        case volumeMl = "volume_ml"
    }

    public init(
        lengthCm: Double?,
        widthCm: Double?,
        areaCm2: Double?,
        perimeterCm: Double?,
        depthCm: Double?,
        meanDepthCm: Double? = nil,
        volumeMl: Double? = nil
    ) {
        self.lengthCm = lengthCm
        self.widthCm = widthCm
        self.areaCm2 = areaCm2
        self.perimeterCm = perimeterCm
        self.depthCm = depthCm
        self.meanDepthCm = meanDepthCm
        self.volumeMl = volumeMl
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let v = lengthCm { try container.encode(v, forKey: .lengthCm) } else { try container.encodeNil(forKey: .lengthCm) }
        if let v = widthCm { try container.encode(v, forKey: .widthCm) } else { try container.encodeNil(forKey: .widthCm) }
        if let v = areaCm2 { try container.encode(v, forKey: .areaCm2) } else { try container.encodeNil(forKey: .areaCm2) }
        if let v = perimeterCm { try container.encode(v, forKey: .perimeterCm) } else { try container.encodeNil(forKey: .perimeterCm) }
        if let v = depthCm { try container.encode(v, forKey: .depthCm) } else { try container.encodeNil(forKey: .depthCm) }
        if let v = meanDepthCm { try container.encode(v, forKey: .meanDepthCm) } else { try container.encodeNil(forKey: .meanDepthCm) }
        if let v = volumeMl { try container.encode(v, forKey: .volumeMl) } else { try container.encodeNil(forKey: .volumeMl) }
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

// MARK: - Patient Context

public struct PatientContextPayload: Codable, Sendable {
    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let medicalRecordNumber: String
    public let dateOfBirth: String?
    public let woundId: String?
    public let woundLabel: String?
    public let woundType: String?
    public let anatomicalLocation: String?

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case medicalRecordNumber = "medical_record_number"
        case dateOfBirth = "date_of_birth"
        case woundId = "wound_id"
        case woundLabel = "wound_label"
        case woundType = "wound_type"
        case anatomicalLocation = "anatomical_location"
    }

    public init(
        patientId: String,
        firstName: String,
        lastName: String,
        medicalRecordNumber: String,
        dateOfBirth: String? = nil,
        woundId: String? = nil,
        woundLabel: String? = nil,
        woundType: String? = nil,
        anatomicalLocation: String? = nil
    ) {
        self.patientId = patientId
        self.firstName = firstName
        self.lastName = lastName
        self.medicalRecordNumber = medicalRecordNumber
        self.dateOfBirth = dateOfBirth
        self.woundId = woundId
        self.woundLabel = woundLabel
        self.woundType = woundType
        self.anatomicalLocation = anatomicalLocation
    }
}

// MARK: - Encounter Context

public struct EncounterContextPayload: Codable, Sendable {
    public let encounterId: String
    public let assessmentId: String
    public let nurseId: String
    public let facilityId: String
    public let visitDate: String
    public let assessedAt: String

    enum CodingKeys: String, CodingKey {
        case encounterId = "encounter_id"
        case assessmentId = "assessment_id"
        case nurseId = "nurse_id"
        case facilityId = "facility_id"
        case visitDate = "visit_date"
        case assessedAt = "assessed_at"
    }

    public init(
        encounterId: String,
        assessmentId: String,
        nurseId: String,
        facilityId: String,
        visitDate: String,
        assessedAt: String
    ) {
        self.encounterId = encounterId
        self.assessmentId = assessmentId
        self.nurseId = nurseId
        self.facilityId = facilityId
        self.visitDate = visitDate
        self.assessedAt = assessedAt
    }
}

// MARK: - PUSH Score Detail

public struct PUSHScoreDetailPayload: Codable, Sendable {
    public let totalScore: Int
    public let lengthTimesWidthCm2: Double
    public let lengthTimesWidthSubScore: Int
    public let exudateAmount: String
    public let exudateSubScore: Int
    public let tissueType: String
    public let tissueSubScore: Int

    enum CodingKeys: String, CodingKey {
        case totalScore = "total_score"
        case lengthTimesWidthCm2 = "length_times_width_cm2"
        case lengthTimesWidthSubScore = "length_times_width_sub_score"
        case exudateAmount = "exudate_amount"
        case exudateSubScore = "exudate_sub_score"
        case tissueType = "tissue_type"
        case tissueSubScore = "tissue_sub_score"
    }

    public init(
        totalScore: Int,
        lengthTimesWidthCm2: Double,
        lengthTimesWidthSubScore: Int,
        exudateAmount: String,
        exudateSubScore: Int,
        tissueType: String,
        tissueSubScore: Int
    ) {
        self.totalScore = totalScore
        self.lengthTimesWidthCm2 = lengthTimesWidthCm2
        self.lengthTimesWidthSubScore = lengthTimesWidthSubScore
        self.exudateAmount = exudateAmount
        self.exudateSubScore = exudateSubScore
        self.tissueType = tissueType
        self.tissueSubScore = tissueSubScore
    }
}

// MARK: - Clinical Assessment

public struct ClinicalAssessmentPayload: Codable, Sendable {
    public let woundBed: WoundBedPayload
    public let exudate: ExudatePayload
    public let surroundingSkin: [String]
    public let painLevel: Int?
    public let painTiming: String?
    public let odor: String
    public let clinicalNotes: String

    enum CodingKeys: String, CodingKey {
        case woundBed = "wound_bed"
        case exudate
        case surroundingSkin = "surrounding_skin"
        case painLevel = "pain_level"
        case painTiming = "pain_timing"
        case odor
        case clinicalNotes = "clinical_notes"
    }

    public init(
        woundBed: WoundBedPayload,
        exudate: ExudatePayload,
        surroundingSkin: [String],
        painLevel: Int?,
        painTiming: String?,
        odor: String,
        clinicalNotes: String
    ) {
        self.woundBed = woundBed
        self.exudate = exudate
        self.surroundingSkin = surroundingSkin
        self.painLevel = painLevel
        self.painTiming = painTiming
        self.odor = odor
        self.clinicalNotes = clinicalNotes
    }
}

public struct WoundBedPayload: Codable, Sendable {
    public let granulationPercent: Int
    public let sloughPercent: Int
    public let necroticPercent: Int
    public let epithelialPercent: Int
    public let otherPercent: Int

    enum CodingKeys: String, CodingKey {
        case granulationPercent = "granulation_pct"
        case sloughPercent = "slough_pct"
        case necroticPercent = "necrotic_pct"
        case epithelialPercent = "epithelial_pct"
        case otherPercent = "other_pct"
    }

    public init(
        granulationPercent: Int,
        sloughPercent: Int,
        necroticPercent: Int,
        epithelialPercent: Int,
        otherPercent: Int
    ) {
        self.granulationPercent = granulationPercent
        self.sloughPercent = sloughPercent
        self.necroticPercent = necroticPercent
        self.epithelialPercent = epithelialPercent
        self.otherPercent = otherPercent
    }
}

public struct ExudatePayload: Codable, Sendable {
    public let amount: String
    public let type: String
    public let color: String

    public init(amount: String, type: String, color: String) {
        self.amount = amount
        self.type = type
        self.color = color
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
