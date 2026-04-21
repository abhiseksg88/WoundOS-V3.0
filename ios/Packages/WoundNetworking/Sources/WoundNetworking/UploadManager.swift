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

    private let client: WoundOSClient
    private let storage: StorageProviderProtocol
    private let maxRetries = 4
    private let baseRetryDelay: TimeInterval = 2.0

    private var uploadQueue: [UUID] = []
    private var isProcessingQueue = false

    public init(client: WoundOSClient, storage: StorageProviderProtocol) {
        self.client = client
        self.storage = storage
    }

    // MARK: - Public API

    /// Enqueue a scan for upload. Will attempt immediately if online.
    public func enqueueUpload(scan: WoundScan) async {
        uploadQueue.append(scan.id)
        pendingUploads = uploadQueue

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
                uploadQueue.removeFirst()
                failedUploads[scanId] = error
                pendingUploads = uploadQueue

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
            _ = try await client.uploadScan(scan)
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
    /// Checks every 5 seconds, up to 90 seconds (18 attempts).
    /// Handles "failed" status and surfaces timeout.
    private func pollForCompletion(scanId: UUID) async {
        let maxAttempts = 18  // 18 × 5s = 90s
        let pollInterval: UInt64 = 5_000_000_000

        for _ in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: pollInterval)

            do {
                let status = try await client.getScanStatus(id: scanId)

                switch status.processingStatus {
                case "completed":
                    if var localScan = try? await storage.fetchScan(id: scanId) {
                        localScan.uploadStatus = .processed
                        try? await storage.updateScan(localScan)
                    }
                    return

                case "failed":
                    if var localScan = try? await storage.fetchScan(id: scanId) {
                        localScan.uploadStatus = .failed
                        try? await storage.updateScan(localScan)
                    }
                    return

                default:
                    continue
                }
            } catch {
                continue // Network error during polling — scan is safely on backend
            }
        }

        // Timed out — surface as failed
        if var localScan = try? await storage.fetchScan(id: scanId) {
            localScan.uploadStatus = .failed
            try? await storage.updateScan(localScan)
        }
    }
}
