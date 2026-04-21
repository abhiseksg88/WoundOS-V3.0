import Foundation

// MARK: - API Configuration

public struct APIConfig: Sendable {
    public let baseURL: URL
    public let version: String

    public init(baseURL: URL, version: String = "v1") {
        self.baseURL = baseURL
        self.version = version
    }

    public static let staging = APIConfig(
        baseURL: URL(string: "https://woundos-api-333499614175.us-central1.run.app")!
    )

    /// Versioned base, e.g. https://host/v1
    public var versionedURL: URL {
        baseURL.appendingPathComponent(version)
    }
}

// MARK: - API Errors

public enum APIError: Error, Equatable, LocalizedError {
    case unauthorized
    case notFound
    case badRequest(String)
    case server(Int, String)
    case decoding(String)
    case transport(URLError)
    case pollingTimeout
    case processingFailed

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication required. Please sign in."
        case .notFound:
            return "Resource not found."
        case .badRequest(let msg):
            return "Bad request: \(msg)"
        case .server(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .decoding(let msg):
            return "Failed to decode response: \(msg)"
        case .transport(let error):
            return error.localizedDescription
        case .pollingTimeout:
            return "Processing unavailable — try again."
        case .processingFailed:
            return "Backend processing failed for this scan."
        }
    }

    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.notFound, .notFound): return true
        case (.badRequest(let a), .badRequest(let b)): return a == b
        case (.server(let c1, let m1), .server(let c2, let m2)): return c1 == c2 && m1 == m2
        case (.decoding(let a), .decoding(let b)): return a == b
        case (.transport(let a), .transport(let b)): return a.code == b.code
        case (.pollingTimeout, .pollingTimeout): return true
        case (.processingFailed, .processingFailed): return true
        default: return false
        }
    }
}

// MARK: - Auth Models

public struct TokenRequest: Codable, Sendable {
    public let firebaseToken: String

    public init(firebaseToken: String) {
        self.firebaseToken = firebaseToken
    }
}

public struct TokenResponse: Codable, Sendable {
    public let token: String
    public let expiresIn: Int

    public init(token: String, expiresIn: Int) {
        self.token = token
        self.expiresIn = expiresIn
    }
}

// MARK: - Upload Metadata

public struct ScanUploadMetadata: Codable, Sendable {
    public let scanId: String
    public let patientId: String
    public let nurseId: String
    public let facilityId: String
    public let capturedAt: Date
    public let cameraIntrinsics: [Double]
    public let cameraTransform: [Double]
    public let imageWidth: Int
    public let imageHeight: Int
    public let depthWidth: Int
    public let depthHeight: Int
    public let deviceModel: String
    public let lidarAvailable: Bool
    public let boundaryPoints2d: [[Double]]
    public let boundaryType: String
    public let boundarySource: String
    public let tapPoint: [Double]?
    public let primaryMeasurement: MeasurementData
    public let pushScore: PushScoreData
    public let qualityScore: QualityScoreData?

    public init(
        scanId: String,
        patientId: String,
        nurseId: String,
        facilityId: String,
        capturedAt: Date,
        cameraIntrinsics: [Double],
        cameraTransform: [Double],
        imageWidth: Int,
        imageHeight: Int,
        depthWidth: Int,
        depthHeight: Int,
        deviceModel: String,
        lidarAvailable: Bool,
        boundaryPoints2d: [[Double]],
        boundaryType: String,
        boundarySource: String,
        tapPoint: [Double]?,
        primaryMeasurement: MeasurementData,
        pushScore: PushScoreData,
        qualityScore: QualityScoreData?
    ) {
        self.scanId = scanId
        self.patientId = patientId
        self.nurseId = nurseId
        self.facilityId = facilityId
        self.capturedAt = capturedAt
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraTransform = cameraTransform
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.deviceModel = deviceModel
        self.lidarAvailable = lidarAvailable
        self.boundaryPoints2d = boundaryPoints2d
        self.boundaryType = boundaryType
        self.boundarySource = boundarySource
        self.tapPoint = tapPoint
        self.primaryMeasurement = primaryMeasurement
        self.pushScore = pushScore
        self.qualityScore = qualityScore
    }
}

public struct MeasurementData: Codable, Sendable {
    public var areaCm2: Double
    public var maxDepthMm: Double
    public var meanDepthMm: Double
    public var volumeMl: Double
    public var lengthMm: Double
    public var widthMm: Double
    public var perimeterMm: Double
    public var processingTimeMs: Int

    public init(
        areaCm2: Double = 0, maxDepthMm: Double = 0, meanDepthMm: Double = 0,
        volumeMl: Double = 0, lengthMm: Double = 0, widthMm: Double = 0,
        perimeterMm: Double = 0, processingTimeMs: Int = 0
    ) {
        self.areaCm2 = areaCm2
        self.maxDepthMm = maxDepthMm
        self.meanDepthMm = meanDepthMm
        self.volumeMl = volumeMl
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.perimeterMm = perimeterMm
        self.processingTimeMs = processingTimeMs
    }
}

public struct PushScoreData: Codable, Sendable {
    public var lengthTimesWidthCm2: Double
    public var exudateAmount: String
    public var tissueType: String
    public var totalScore: Int

    public init(
        lengthTimesWidthCm2: Double = 0, exudateAmount: String = "none",
        tissueType: String = "granulation", totalScore: Int = 0
    ) {
        self.lengthTimesWidthCm2 = lengthTimesWidthCm2
        self.exudateAmount = exudateAmount
        self.tissueType = tissueType
        self.totalScore = totalScore
    }
}

public struct QualityScoreData: Codable, Sendable {
    public var trackingStableSeconds: Double
    public var captureDistanceM: Double
    public var meshVertexCount: Int
    public var meanDepthConfidence: Double
    public var meshHitRate: Double
    public var angularVelocityRadPerSec: Double

    public init(
        trackingStableSeconds: Double = 0, captureDistanceM: Double = 0,
        meshVertexCount: Int = 0, meanDepthConfidence: Double = 0,
        meshHitRate: Double = 0, angularVelocityRadPerSec: Double = 0
    ) {
        self.trackingStableSeconds = trackingStableSeconds
        self.captureDistanceM = captureDistanceM
        self.meshVertexCount = meshVertexCount
        self.meanDepthConfidence = meanDepthConfidence
        self.meshHitRate = meshHitRate
        self.angularVelocityRadPerSec = angularVelocityRadPerSec
    }
}

// MARK: - Upload Response

public struct UploadResponse: Codable, Sendable {
    public let scanId: String
    public let uploadStatus: String
    public let gcsPaths: GCSPaths

    public init(scanId: String, uploadStatus: String, gcsPaths: GCSPaths) {
        self.scanId = scanId
        self.uploadStatus = uploadStatus
        self.gcsPaths = gcsPaths
    }
}

public struct GCSPaths: Codable, Sendable {
    public let rgbImage: String
    public let depthMap: String
    public let mesh: String
    public let metadata: String

    public init(rgbImage: String, depthMap: String, mesh: String, metadata: String) {
        self.rgbImage = rgbImage
        self.depthMap = depthMap
        self.mesh = mesh
        self.metadata = metadata
    }
}

// MARK: - Scan Response (GET /v1/scans/{id})

public struct ScanResponse: Codable, Sendable {
    public let id: String
    public let patientId: String
    public let nurseId: String
    public let facilityId: String
    public let capturedAt: Date
    public let uploadStatus: String

    public let areaCm2: Double?
    public let maxDepthMm: Double?
    public let meanDepthMm: Double?
    public let volumeMl: Double?
    public let lengthMm: Double?
    public let widthMm: Double?
    public let perimeterMm: Double?

    public let pushTotalScore: Int?
    public let exudateAmount: String?
    public let tissueType: String?

    public let agreementMetrics: AgreementMetricsResponse?
    public let clinicalSummary: ClinicalSummaryResponse?
    public let fwaSignals: FWASignalsResponse?
    public let reviewStatus: String?

    public let rgbImagePath: String?
    public let createdAt: Date
    public let updatedAt: Date
}

// MARK: - Scan Status Response (GET /v1/scans/{id}/status)

public struct ScanStatusResponse: Codable, Sendable {
    public let scanId: String
    /// "pending" | "processing" | "completed" | "failed"
    public let processingStatus: String
    public let shadowMeasurement: MeasurementData?
    public let agreementMetrics: AgreementMetricsResponse?
    public let clinicalSummary: ClinicalSummaryResponse?
}

// MARK: - Scan List Response (GET /v1/patients/{id}/scans)

public struct ScanListResponse: Codable, Sendable {
    public let scans: [ScanResponse]
    public let total: Int
}

// MARK: - Agreement Metrics Response

public struct AgreementMetricsResponse: Codable, Sendable {
    public let iou: Double
    public let diceCoefficient: Double
    public let areaDeltaPercent: Double
    public let depthDeltaMm: Double
    public let volumeDeltaMl: Double
    public let centroidDisplacementMm: Double
    public let samConfidence: Double
    public let samModelVersion: String
    public let isFlagged: Bool
}

// MARK: - Clinical Summary Response

public struct ClinicalSummaryResponse: Codable, Sendable {
    public let narrativeSummary: String
    /// "improving" | "stable" | "worsening" | "insufficient_data"
    public let trajectory: String
    public let keyFindings: [String]
    public let recommendations: [String]
    public let modelVersion: String
}

// MARK: - FWA Signals Response

public struct FWASignalsResponse: Codable, Sendable {
    public let nurseBaselineAgreement: Double
    public let woundSizeOutlier: Bool
    public let copyPasteRisk: Double
    public let longitudinalConsistency: Double
    public let overallRiskScore: Double
    public let triggeredFlags: [String]
}

// MARK: - Review Request (PATCH /v1/scans/{id}/review)

public struct ReviewRequest: Codable, Sendable {
    /// "approved" | "rejected" | "needs_correction"
    public let reviewStatus: String
    public let reviewerId: String
    public var notes: String

    public init(reviewStatus: String, reviewerId: String, notes: String = "") {
        self.reviewStatus = reviewStatus
        self.reviewerId = reviewerId
        self.notes = notes
    }
}

public struct ReviewResponse: Codable, Sendable {
    public let status: String
    public let data: ReviewResponseData?
    public let error: String?
}

public struct ReviewResponseData: Codable, Sendable {
    public let scanId: String
    public let reviewStatus: String
}

// MARK: - Backend Error Response

struct BackendErrorResponse: Decodable {
    let detail: String?
}
