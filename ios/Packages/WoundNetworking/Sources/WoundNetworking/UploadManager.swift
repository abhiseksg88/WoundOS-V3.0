import Foundation
import Combine
import WoundCore

// MARK: - Upload Manager

/// Manages background uploading of wound scans.
/// Queues scans when offline, retries with exponential backoff,
/// and polls for backend processing completion.
public final class UploadManager: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var pendingUploads: [UUID] = []
    @Published public private(set) var activeUpload: UUID?
    @Published public private(set) var failedUploads: [UUID: Error] = [:]

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let storage: StorageProviderProtocol
    private let maxRetries = 4
    private let baseRetryDelay: TimeInterval = 2.0

    private var uploadQueue: [UUID] = []
    private var isProcessingQueue = false

    public init(apiClient: APIClient, storage: StorageProviderProtocol) {
        self.apiClient = apiClient
        self.storage = storage
    }

    // MARK: - Public API

    /// Enqueue a scan for upload. Will attempt immediately if online.
    public func enqueueUpload(scan: WoundScan) async {
        uploadQueue.append(scan.id)
        pendingUploads = uploadQueue

        // Update scan status
        var updatedScan = scan
        updatedScan.uploadStatus = .uploading
        try? await storage.updateScan(updatedScan)

        await processQueue()
    }

    /// Retry all failed uploads.
    public func retryFailedUploads() async {
        let failedIds = Array(failedUploads.keys)
        failedUploads.removeAll()
        uploadQueue.append(contentsOf: failedIds)
        pendingUploads = uploadQueue
        await processQueue()
    }

    // MARK: - Queue Processing

    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        while let scanId = uploadQueue.first {
            activeUpload = scanId

            do {
                guard let scan = try await storage.fetchScan(id: scanId) else {
                    uploadQueue.removeFirst()
                    continue
                }

                try await uploadWithRetry(scan: scan)

                // Success — update status
                var uploaded = scan
                uploaded.uploadStatus = .uploaded
                try await storage.updateScan(uploaded)

                uploadQueue.removeFirst()
                pendingUploads = uploadQueue

                // Start polling for backend processing
                Task { [weak self] in
                    await self?.pollForCompletion(scanId: scanId)
                }

            } catch {
                // Move to failed
                uploadQueue.removeFirst()
                failedUploads[scanId] = error
                pendingUploads = uploadQueue

                // Update scan status
                if var scan = try? await storage.fetchScan(id: scanId) {
                    scan.uploadStatus = .failed
                    try? await storage.updateScan(scan)
                }
            }
        }

        activeUpload = nil
        isProcessingQueue = false
    }

    // MARK: - Upload with Retry

    private func uploadWithRetry(scan: WoundScan, attempt: Int = 0) async throws {
        do {
            _ = try await apiClient.uploadScan(scan)
        } catch {
            if attempt < maxRetries {
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try await uploadWithRetry(scan: scan, attempt: attempt + 1)
            } else {
                throw error
            }
        }
    }

    // MARK: - Poll for Backend Completion

    /// Poll the backend until shadow validation is complete.
    /// Checks every 5 seconds, up to 60 seconds.
    private func pollForCompletion(scanId: UUID) async {
        let maxAttempts = 12
        let pollInterval: UInt64 = 5_000_000_000 // 5 seconds

        for _ in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: pollInterval)

            do {
                let status = try await apiClient.checkScanStatus(id: scanId.uuidString)

                if status.processingStatus == "completed" {
                    // Fetch the full updated scan from backend
                    let updatedScan = try await apiClient.fetchScan(id: scanId.uuidString)
                    try await storage.updateScan(updatedScan)
                    return
                }
            } catch {
                // Network error during polling — scan is safely on backend, skip
                continue
            }
        }
    }
}
