import Foundation

// MARK: - Local Storage Provider

/// Contract for persisting wound scans on-device.
/// Scans are stored locally immediately after measurement,
/// then uploaded to the backend asynchronously.
public protocol StorageProviderProtocol {

    /// Save a scan to local storage
    func saveScan(_ scan: WoundScan) async throws

    /// Retrieve a scan by ID
    func fetchScan(id: UUID) async throws -> WoundScan?

    /// Retrieve all scans for a patient, ordered by capture date descending
    func fetchScans(patientId: String) async throws -> [WoundScan]

    /// Retrieve all scans pending upload
    func fetchPendingUploads() async throws -> [WoundScan]

    /// Update a scan (e.g., after backend processing returns shadow data)
    func updateScan(_ scan: WoundScan) async throws

    /// Delete a scan from local storage
    func deleteScan(id: UUID) async throws
}

// MARK: - Upload Provider

/// Contract for uploading scans to the backend.
public protocol UploadProviderProtocol {

    /// Upload a scan to the backend. Returns the backend-assigned scan ID.
    func uploadScan(_ scan: WoundScan) async throws -> String

    /// Check the processing status of a previously uploaded scan.
    func checkStatus(scanId: UUID) async throws -> WoundScan

    /// Fetch updated scan data from the backend (shadow measurements, agreement, summary).
    func fetchUpdatedScan(scanId: UUID) async throws -> WoundScan
}
