import Foundation
import WoundCore
import WoundCapture
import WoundMeasurement
import WoundNetworking
import WoundAutoSegmentation

// MARK: - Dependency Container

/// Centralized dependency injection container.
/// Created once at app launch, passed to coordinators.
final class DependencyContainer {

    // MARK: - Capture

    lazy var captureProvider: CaptureProviderProtocol = {
        CrashLogger.shared.log("Initializing ARSessionManager", category: .capture)
        return ARSessionManager()
    }()

    // MARK: - Measurement

    lazy var measurementEngine: MeshMeasurementEngine = {
        CrashLogger.shared.log("Initializing MeshMeasurementEngine", category: .measurement)
        return MeshMeasurementEngine()
    }()

    // MARK: - Auto-Segmentation

    /// The on-device wound segmenter. Prefers the wound-specific WoundAmbit
    /// FUSegNet CoreML model; falls back to Apple Vision's generic foreground
    /// instance mask (iOS 17+). Returns `nil` on older OSes — the drawing
    /// scene falls back to manual polygon / freeform drawing and hides the
    /// Auto segment.
    lazy var autoSegmenter: WoundSegmenter? = {
        // 1. Try wound-specific CoreML model first
        CrashLogger.shared.log("Attempting WoundAmbitSegmenter (CoreML)…", category: .segmentation)
        if let ambit = try? WoundAmbitSegmenter() {
            CrashLogger.shared.log("WoundAmbitSegmenter initialized successfully", category: .segmentation)
            return ambit
        }
        CrashLogger.shared.log("WoundAmbitSegmenter not available — trying VisionForegroundSegmenter", category: .segmentation, level: .warning)
        // 2. Fall back to Apple Vision generic foreground (iOS 17+)
        if #available(iOS 17.0, *) {
            CrashLogger.shared.log("VisionForegroundSegmenter initialized (iOS 17+ fallback)", category: .segmentation)
            return VisionForegroundSegmenter()
        }
        CrashLogger.shared.log("No segmenter available — manual drawing only", category: .segmentation, level: .warning)
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
