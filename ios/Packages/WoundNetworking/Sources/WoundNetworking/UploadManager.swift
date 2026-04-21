import Foundation
import Combine
import os
import WoundCore

private let logger = Logger(subsystem: "com.woundos.app", category: "Upload")

// MARK: - Upload Manager

/// Manages background uploading of wound scans.
/// Queues scans when offline, retries with exponential backoff,
/// and polls for backend processing completion.
///
/// Queue access is serialized through a private actor to prevent
/// race conditions when multiple callers enqueue concurrently.
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

    /// Serializes all queue mutations to prevent race conditions.
    private let queueGuard = QueueGuard()

    public init(client: WoundOSClient, storage: StorageProviderProtocol) {
        self.client = client
        self.storage = storage
    }

    // MARK: - Public API

    /// Enqueue a scan for upload. Will attempt immediately if online.
    public func enqueueUpload(scan: WoundScan) async {
        let didEnqueue = await queueGuard.enqueue(scanId: scan.id)
        guard didEnqueue else {
            logger.info("Scan \(scan.id) already in upload queue — skipping duplicate")
            return
        }

        await MainActor.run {
            pendingUploads = pendingUploads + [scan.id]
        }

        var updatedScan = scan
        updatedScan.uploadStatus = .uploading
        try? await storage.updateScan(updatedScan)

        logger.info("Enqueued scan \(scan.id) for upload")
        await processQueue()
    }

    /// Retry all failed uploads.
    public func retryFailedUploads() async {
        let failedIds = Array(failedUploads.keys)
        await MainActor.run {
            failedUploads.removeAll()
        }
        for id in failedIds {
            _ = await queueGuard.enqueue(scanId: id)
        }
        await MainActor.run {
            pendingUploads = pendingUploads + failedIds
        }
        await processQueue()
    }

    // MARK: - Queue Processing

    private func processQueue() async {
        guard await queueGuard.tryStartProcessing() else { return }
        logger.info("Started processing upload queue")

        while let scanId = await queueGuard.peekFirst() {
            await MainActor.run { activeUpload = scanId }

            do {
                guard let scan = try await storage.fetchScan(id: scanId) else {
                    logger.warning("Scan \(scanId) not found in storage — removing from queue")
                    await queueGuard.removeFirst()
                    continue
                }

                try await uploadWithRetry(scan: scan)

                var uploaded = scan
                uploaded.uploadStatus = .uploaded
                try await storage.updateScan(uploaded)

                await queueGuard.removeFirst()
                await MainActor.run {
                    pendingUploads = pendingUploads.filter { $0 != scanId }
                }

                logger.info("Scan \(scanId) uploaded successfully — starting status polling")
                // Start polling for backend processing
                Task { [weak self] in
                    await self?.pollForCompletion(scanId: scanId)
                }

            } catch {
                logger.error("Upload failed for scan \(scanId): \(error.localizedDescription)")
                await queueGuard.removeFirst()
                await MainActor.run {
                    failedUploads[scanId] = error
                    pendingUploads = pendingUploads.filter { $0 != scanId }
                }

                if var scan = try? await storage.fetchScan(id: scanId) {
                    scan.uploadStatus = .failed
                    try? await storage.updateScan(scan)
                }
            }
        }

        await MainActor.run { activeUpload = nil }
        await queueGuard.stopProcessing()
        logger.info("Upload queue processing complete")
    }

    // MARK: - Upload with Retry

    private func uploadWithRetry(scan: WoundScan, attempt: Int = 0) async throws {
        do {
            _ = try await client.uploadScan(scan)
        } catch {
            if attempt < maxRetries {
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                logger.info("Upload attempt \(attempt + 1) failed, retrying in \(delay)s: \(error.localizedDescription)")
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
    /// A timeout does NOT mark the scan as failed — the upload succeeded;
    /// only backend processing is slow.
    private func pollForCompletion(scanId: UUID) async {
        let maxAttempts = 18  // 18 × 5s = 90s
        let pollInterval: UInt64 = 5_000_000_000

        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: pollInterval)

            do {
                let status = try await client.getScanStatus(id: scanId)

                switch status.processingStatus {
                case "completed":
                    logger.info("Scan \(scanId) processing completed on backend")
                    if var localScan = try? await storage.fetchScan(id: scanId) {
                        localScan.uploadStatus = .processed
                        try? await storage.updateScan(localScan)
                    }
                    return

                case "failed":
                    logger.error("Scan \(scanId) processing failed on backend")
                    if var localScan = try? await storage.fetchScan(id: scanId) {
                        localScan.uploadStatus = .failed
                        try? await storage.updateScan(localScan)
                    }
                    return

                default:
                    logger.debug("Scan \(scanId) still processing (attempt \(attempt + 1)/\(maxAttempts))")
                    continue
                }
            } catch {
                logger.warning("Polling error for scan \(scanId) (attempt \(attempt + 1)): \(error.localizedDescription)")
                continue // Network error during polling — scan is safely on backend
            }
        }

        // Timed out — scan was uploaded successfully but backend processing
        // is still running. Mark as processingTimeout (not failed) so the
        // user isn't prompted to re-upload a scan that's already on the server.
        logger.warning("Polling timed out for scan \(scanId) after 90s — marking as processingTimeout")
        if var localScan = try? await storage.fetchScan(id: scanId) {
            localScan.uploadStatus = .processingTimeout
            try? await storage.updateScan(localScan)
        }
    }
}

// MARK: - Queue Guard (Actor)

/// Serializes access to the upload queue so concurrent callers
/// cannot corrupt the queue or start duplicate processing loops.
private actor QueueGuard {
    private var queue: [UUID] = []
    private var isProcessing = false

    /// Add a scan ID to the queue. Returns false if already present (dedup).
    func enqueue(scanId: UUID) -> Bool {
        guard !queue.contains(scanId) else { return false }
        queue.append(scanId)
        return true
    }

    /// Peek at the first item without removing it.
    func peekFirst() -> UUID? {
        queue.first
    }

    /// Remove the first item from the queue.
    func removeFirst() {
        guard !queue.isEmpty else { return }
        queue.removeFirst()
    }

    /// Attempt to start processing. Returns false if already running.
    func tryStartProcessing() -> Bool {
        guard !isProcessing else { return false }
        isProcessing = true
        return true
    }

    /// Mark processing as finished.
    func stopProcessing() {
        isProcessing = false
    }
}
