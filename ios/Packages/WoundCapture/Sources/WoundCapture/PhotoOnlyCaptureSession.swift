import AVFoundation
import os
import WoundCore

private let logger = Logger(subsystem: "com.woundos.app", category: "PhotoOnlyCapture")

// MARK: - Photo-Only Capture Session

/// Fallback capture session for devices without LiDAR.
/// Provides a still photo capture (no depth, no mesh, no AR).
/// Measurements are limited to 2D area estimation.
public final class PhotoOnlyCaptureSession: NSObject, CaptureProviderProtocol {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var lastCapturedPhoto: Data?
    private var capturedImageWidth: Int = 0
    private var capturedImageHeight: Int = 0
    private var photoContinuation: CheckedContinuation<Data, Error>?

    public var isLiDARAvailable: Bool { false }
    public var isSessionActive: Bool { captureSession.isRunning }
    public var onTrackingStateChanged: ((TrackingState) -> Void)?

    // MARK: - Init

    public override init() {
        super.init()
        configureCameraSession()
    }

    // MARK: - CaptureProviderProtocol

    public func startSession() throws {
        logger.info("PhotoOnly startSession()")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
        // Report normal tracking immediately (no AR tracking to wait for)
        onTrackingStateChanged?(.normal)
    }

    public func pauseSession() {
        logger.info("PhotoOnly pauseSession()")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    public func captureSnapshot() throws -> CaptureSnapshot {
        logger.info("PhotoOnly captureSnapshot()")

        // For photo-only mode, we return a snapshot with empty depth/mesh data.
        // The downstream pipeline detects vertexCount == 0 and skips 3D measurements.
        guard let photoData = lastCapturedPhoto, !photoData.isEmpty else {
            throw CaptureError.noFrameAvailable
        }

        return CaptureSnapshot(
            rgbImageData: photoData,
            imageWidth: capturedImageWidth,
            imageHeight: capturedImageHeight,
            depthMap: [],
            depthWidth: 0,
            depthHeight: 0,
            confidenceMap: [],
            vertices: [],
            faces: [],
            normals: [],
            cameraIntrinsics: simd_float3x3(1),
            cameraTransform: simd_float4x4(1),
            deviceModel: deviceModelString(),
            timestamp: Date()
        )
    }

    /// Take a photo asynchronously. Call this before captureSnapshot().
    public func takePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Camera Configuration

    private func configureCameraSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: backCamera) else {
            logger.error("Failed to configure back camera")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
    }

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

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoOnlyCaptureSession: AVCapturePhotoCaptureDelegate {

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            logger.error("Photo capture failed: \(error.localizedDescription)")
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            photoContinuation?.resume(throwing: CaptureError.noFrameAvailable)
            photoContinuation = nil
            return
        }

        lastCapturedPhoto = data
        if let cgImage = photo.cgImageRepresentation() {
            capturedImageWidth = cgImage.width
            capturedImageHeight = cgImage.height
        }

        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}
