import Foundation
import UIKit

// MARK: - Upload Result

public struct UploadResult: Sendable {
    public let captureId: UUID
    public let serverCaptureId: String
    public let webURL: URL
    public let uploadedAt: Date
    public let status: String

    public init(
        captureId: UUID,
        serverCaptureId: String,
        webURL: URL,
        uploadedAt: Date,
        status: String
    ) {
        self.captureId = captureId
        self.serverCaptureId = serverCaptureId
        self.webURL = webURL
        self.uploadedAt = uploadedAt
        self.status = status
    }
}

// MARK: - Completed Capture

public struct CompletedCapture: Sendable {
    public let captureId: UUID
    public let capturedAt: Date
    public let notes: String
    public let segmentation: SegmentationPayload
    public let measurements: MeasurementsPayload
    public let lidarMetadata: LiDARMetadataPayload
    public let deviceInfo: DevicePayload
    public let capturedByUser: VerifiedUser
    public let rgbImage: UIImage
    public let maskImage: UIImage
    public let overlayImage: UIImage

    public init(
        captureId: UUID = UUID(),
        capturedAt: Date = Date(),
        notes: String = "",
        segmentation: SegmentationPayload,
        measurements: MeasurementsPayload,
        lidarMetadata: LiDARMetadataPayload,
        deviceInfo: DevicePayload = .current(),
        capturedByUser: VerifiedUser,
        rgbImage: UIImage,
        maskImage: UIImage,
        overlayImage: UIImage
    ) {
        self.captureId = captureId
        self.capturedAt = capturedAt
        self.notes = notes
        self.segmentation = segmentation
        self.measurements = measurements
        self.lidarMetadata = lidarMetadata
        self.deviceInfo = deviceInfo
        self.capturedByUser = capturedByUser
        self.rgbImage = rgbImage
        self.maskImage = maskImage
        self.overlayImage = overlayImage
    }

    public func toPayload() -> CaptureUploadPayload {
        CaptureUploadPayload(
            captureId: captureId,
            capturedAt: capturedAt,
            device: deviceInfo,
            capturedBy: CapturedByPayload(from: capturedByUser),
            notes: notes,
            segmentation: segmentation,
            measurements: measurements,
            lidarMetadata: lidarMetadata,
            artifacts: ArtifactsPayload(
                rgbImage: rgbImage,
                maskImage: maskImage,
                overlayImage: overlayImage
            )
        )
    }
}

// MARK: - CaptureUploader Protocol

public protocol CaptureUploaderProtocol: Sendable {
    func upload(_ capture: CompletedCapture) async throws -> UploadResult
    func verify(token: String, baseURL: URL) async throws -> VerifiedUser
}

// MARK: - Default Implementation

public final class DefaultCaptureUploader: CaptureUploaderProtocol, @unchecked Sendable {

    private let client: ClinicalPlatformClient
    private let tokenStore: ClinicalPlatformTokenStore

    public init(client: ClinicalPlatformClient, tokenStore: ClinicalPlatformTokenStore) {
        self.client = client
        self.tokenStore = tokenStore
    }

    public func verify(token: String, baseURL: URL) async throws -> VerifiedUser {
        try await client.verify(token: token, baseURL: baseURL)
    }

    public func upload(_ capture: CompletedCapture) async throws -> UploadResult {
        guard let token = tokenStore.loadToken() else {
            throw ClinicalPlatformError.noTokenConfigured
        }
        guard let baseURLString = tokenStore.loadBaseURL(),
              let baseURL = URL(string: baseURLString) else {
            throw ClinicalPlatformError.noBaseURLConfigured
        }

        let payload = capture.toPayload()
        return try await client.upload(payload: payload, token: token, baseURL: baseURL)
    }
}
