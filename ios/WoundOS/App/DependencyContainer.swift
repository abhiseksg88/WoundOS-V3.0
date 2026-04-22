import Foundation
import SwiftData
import WoundCore
import WoundCapture
import WoundMeasurement
import WoundNetworking
import WoundAutoSegmentation

// MARK: - Dependency Container

/// Centralized dependency injection container.
/// Created once at app launch, passed to coordinators.
final class DependencyContainer {

    // MARK: - Feature Flags

    lazy var featureFlagStore: FeatureFlagStore = UserDefaultsFlagStore()

    // MARK: - Capture (V4, always available)

    lazy var captureProvider: CaptureProviderProtocol = {
        CrashLogger.shared.log("Initializing ARSessionManager (V4)", category: .capture)
        return ARSessionManager()
    }()

    // MARK: - V5 Capture (only initialized when flag is ON)

    lazy var v5CaptureSession: LiDARCaptureSession? = {
        guard FeatureFlags.isEnabled(.v5LidarCapture) else { return nil }
        CrashLogger.shared.log("Initializing LiDARCaptureSession (V5)", category: .capture)
        return LiDARCaptureSession()
    }()

    // MARK: - V5 Persistence (only initialized when flag is ON)

    lazy var captureBundleStore: SwiftDataCaptureBundleStore? = {
        guard FeatureFlags.isEnabled(.v5LidarCapture) else { return nil }
        CrashLogger.shared.log("Initializing SwiftData CaptureBundle store (V5)", category: .storage)
        return try? SwiftDataCaptureBundleStore()
    }()

    // MARK: - Measurement

    lazy var measurementEngine: MeshMeasurementEngine = {
        CrashLogger.shared.log("Initializing MeshMeasurementEngine", category: .measurement)
        return MeshMeasurementEngine()
    }()

    // MARK: - Auto-Segmentation

    /// Primary segmenter: server-side SAM 2 via WoundOS backend.
    /// Fallback chain: ServerSegmenter → VisionForegroundSegmenter → nil (manual).
    lazy var autoSegmenter: WoundSegmenter? = {
        // 1. Server-side SAM 2 (primary — best accuracy, no app size cost)
        CrashLogger.shared.log("Initializing ServerSegmenter (SAM 2 backend)", category: .segmentation)
        let client = self.apiClient
        let onDeviceFallback = self.fallbackSegmenter
        let serverSegmenter = ServerSegmenter(
            segmentRequest: { jpegData, tapPoint, imageWidth, imageHeight in
                let response = try await client.segmentImage(
                    jpegData: jpegData,
                    tapPoint: tapPoint,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                )
                return (
                    polygon: response.polygon,
                    confidence: response.confidence,
                    modelVersion: response.modelVersion
                )
            },
            fallback: onDeviceFallback
        )
        return serverSegmenter
    }()

    /// On-device fallback segmenter used when the server is unreachable.
    lazy var fallbackSegmenter: WoundSegmenter? = {
        CrashLogger.shared.log("Attempting WoundAmbitSegmenter (CoreML)…", category: .segmentation)
        if let ambit = try? WoundAmbitSegmenter() {
            CrashLogger.shared.log("WoundAmbitSegmenter initialized successfully", category: .segmentation)
            return ambit
        }
        if #available(iOS 17.0, *) {
            CrashLogger.shared.log("VisionForegroundSegmenter initialized (fallback)", category: .segmentation)
            return VisionForegroundSegmenter()
        }
        CrashLogger.shared.log("No fallback segmenter available", category: .segmentation, level: .warning)
        return nil
    }()

    // MARK: - Networking

    lazy var authProvider: AuthProvider = {
        AuthProvider(
            tokenStore: KeychainTokenStore(),
            firebase: StubFirebaseAuth()
        )
    }()

    lazy var apiClient: WoundOSClient = {
        WoundOSClient(
            config: .staging,
            session: .shared,
            authProvider: authProvider
        )
    }()

    lazy var uploadManager: UploadManager = {
        UploadManager(client: apiClient, storage: localStorage)
    }()

    // MARK: - Storage

    lazy var localStorage: StorageProviderProtocol = {
        LocalScanStorage()
    }()
}

// MARK: - Local Scan Storage

/// On-device scan storage using the file system + UserDefaults index.
/// Scans are stored as JSON files in the app's documents directory.
final class LocalScanStorage: StorageProviderProtocol {

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder.woundOS
    private let decoder = JSONDecoder.woundOS

    private var scansDirectory: URL {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("WoundScans", isDirectory: true)
        }
        let dir = docs.appendingPathComponent("WoundScans", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveScan(_ scan: WoundScan) async throws {
        let url = scansDirectory.appendingPathComponent("\(scan.id.uuidString).json")
        let data = try encoder.encode(scan)
        try data.write(to: url, options: .atomic)
    }

    func fetchScan(id: UUID) async throws -> WoundScan? {
        let url = scansDirectory.appendingPathComponent("\(id.uuidString).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(WoundScan.self, from: data)
    }

    func fetchScans(patientId: String) async throws -> [WoundScan] {
        let allScans = try await fetchAllScans()
        return allScans
            .filter { $0.patientId == patientId }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    func fetchPendingUploads() async throws -> [WoundScan] {
        let allScans = try await fetchAllScans()
        return allScans.filter { $0.uploadStatus == .pending || $0.uploadStatus == .failed }
    }

    func updateScan(_ scan: WoundScan) async throws {
        try await saveScan(scan)
    }

    func deleteScan(id: UUID) async throws {
        let url = scansDirectory.appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func fetchAllScans() async throws -> [WoundScan] {
        let contents = try fileManager.contentsOfDirectory(
            at: scansDirectory,
            includingPropertiesForKeys: nil
        )
        return contents.compactMap { url -> WoundScan? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(WoundScan.self, from: data)
        }
    }
}

// MARK: - JSONCoder Extensions for woundOS

private extension JSONEncoder {
    static let woundOS: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let woundOS: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
