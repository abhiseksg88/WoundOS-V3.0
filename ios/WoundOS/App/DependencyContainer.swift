import Foundation
import WoundCore
import WoundCapture
import WoundMeasurement
import WoundNetworking

// MARK: - Dependency Container

/// Centralized dependency injection container.
/// Created once at app launch, passed to coordinators.
final class DependencyContainer {

    // MARK: - Capture

    lazy var captureProvider: CaptureProviderProtocol = {
        ARSessionManager()
    }()

    // MARK: - Measurement

    lazy var measurementEngine: MeshMeasurementEngine = {
        MeshMeasurementEngine()
    }()

    // MARK: - Networking

    lazy var apiClient: APIClient = {
        APIClient()
    }()

    lazy var uploadManager: UploadManager = {
        UploadManager(apiClient: apiClient, storage: localStorage)
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
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
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
