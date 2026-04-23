import Foundation

// MARK: - Segmentation Telemetry Record

/// Structured per-capture observability record for segmentation attempts.
/// Stored locally for debugging and future analytics pipeline (Phase 8).
///
/// Does NOT contain PHI — no image bytes, no user identifiers, no facility info.
public struct SegmentationTelemetryRecord: Codable, Sendable {
    public let captureUUID: String
    public let timestamp: Date
    public let segmenterIdentifier: String
    public let inferenceLatencyMs: Double
    public let rawConfidence: Float
    public let rawCoveragePct: Double
    public let rawAspectRatio: Double
    public let rawComponentCount: Int
    public let qualityResult: String
    public let qualityDetail: String?
    public let userAction: String?
    public let onDeviceFlagState: Bool

    // Phase 3a.2 — ChainedSegmenter observability
    public let canaryIoU: Float?
    public let canaryPassed: Bool?
    public let fallbackReason: String?
    public let chainedSegmenterUsed: Bool

    // Phase 3a.3 — Canary telemetry persistence
    /// True if this record represents a canary validation run (not a real capture).
    /// Used to separate canary records from capture records in the debug screen.
    public let isCanaryRecord: Bool

    public init(
        captureUUID: String = UUID().uuidString,
        timestamp: Date = Date(),
        segmenterIdentifier: String,
        inferenceLatencyMs: Double,
        rawConfidence: Float,
        rawCoveragePct: Double,
        rawAspectRatio: Double,
        rawComponentCount: Int,
        qualityResult: String,
        qualityDetail: String? = nil,
        userAction: String? = nil,
        onDeviceFlagState: Bool,
        canaryIoU: Float? = nil,
        canaryPassed: Bool? = nil,
        fallbackReason: String? = nil,
        chainedSegmenterUsed: Bool = false,
        isCanaryRecord: Bool = false
    ) {
        self.captureUUID = captureUUID
        self.timestamp = timestamp
        self.segmenterIdentifier = segmenterIdentifier
        self.inferenceLatencyMs = inferenceLatencyMs
        self.rawConfidence = rawConfidence
        self.rawCoveragePct = rawCoveragePct
        self.rawAspectRatio = rawAspectRatio
        self.rawComponentCount = rawComponentCount
        self.qualityResult = qualityResult
        self.qualityDetail = qualityDetail
        self.userAction = userAction
        self.onDeviceFlagState = onDeviceFlagState
        self.canaryIoU = canaryIoU
        self.canaryPassed = canaryPassed
        self.fallbackReason = fallbackReason
        self.chainedSegmenterUsed = chainedSegmenterUsed
        self.isCanaryRecord = isCanaryRecord
    }

    /// Build a telemetry record from a SegmentationResult.
    public static func from(
        result: SegmentationResult,
        onDeviceFlagState: Bool,
        canaryIoU: Float? = nil,
        canaryPassed: Bool? = nil,
        fallbackReason: String? = nil,
        chainedSegmenterUsed: Bool = false,
        isCanaryRecord: Bool = false,
        captureUUID: String = UUID().uuidString
    ) -> SegmentationTelemetryRecord {
        let polyArea = abs(shoelaceArea(result.polygonImageSpace))
        let frameArea = Double(result.imageSize.width) * Double(result.imageSize.height)
        let coverage = frameArea > 0 ? (polyArea / frameArea) * 100 : 0

        let bbox = boundingBox(result.polygonImageSpace)
        let shortSide = min(bbox.width, bbox.height)
        let longSide = max(bbox.width, bbox.height)
        let aspect = longSide > 0 ? Double(shortSide) / Double(longSide) : 0

        let qualityStr: String
        let detailStr: String?
        switch result.qualityResult {
        case .accept:
            qualityStr = "accept"
            detailStr = nil
        case .reject(let reason, let detail):
            qualityStr = reason.rawValue
            detailStr = detail
        }

        return SegmentationTelemetryRecord(
            captureUUID: captureUUID,
            segmenterIdentifier: result.modelIdentifier,
            inferenceLatencyMs: result.inferenceLatencyMs,
            rawConfidence: result.confidence,
            rawCoveragePct: coverage,
            rawAspectRatio: aspect,
            rawComponentCount: result.connectedComponents,
            qualityResult: qualityStr,
            qualityDetail: detailStr,
            onDeviceFlagState: onDeviceFlagState,
            canaryIoU: canaryIoU,
            canaryPassed: canaryPassed,
            fallbackReason: fallbackReason,
            chainedSegmenterUsed: chainedSegmenterUsed,
            isCanaryRecord: isCanaryRecord
        )
    }

    // MARK: - Geometry Helpers

    private static func shoelaceArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var area: Double = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += Double(points[i].x) * Double(points[j].y)
            area -= Double(points[j].x) * Double(points[i].y)
        }
        return area / 2.0
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Telemetry Store

/// File-based telemetry store for segmentation records.
/// Stores as JSON array in Documents/SegmentationTelemetry/.
/// Not uploaded anywhere in Phase 3a.1 — local inspection only.
public final class SegmentationTelemetryStore: @unchecked Sendable {

    public static let shared = SegmentationTelemetryStore()

    private let queue = DispatchQueue(label: "com.woundos.segmentation-telemetry", qos: .utility)
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = docs.appendingPathComponent("SegmentationTelemetry", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var recordsURL: URL {
        directory.appendingPathComponent("records.json")
    }

    /// Append a telemetry record to the local store.
    public func record(_ entry: SegmentationTelemetryRecord) {
        queue.async { [self] in
            var records = loadRecordsSync()
            records.append(entry)
            // Keep last 500 records to avoid unbounded growth
            if records.count > 500 {
                records = Array(records.suffix(500))
            }
            saveRecordsSync(records)
        }
    }

    /// Read all stored records. Called from debug UI.
    public func fetchRecords() -> [SegmentationTelemetryRecord] {
        queue.sync { loadRecordsSync() }
    }

    /// Clear all stored records.
    public func clearAll() {
        queue.async { [self] in
            try? fileManager.removeItem(at: recordsURL)
        }
    }

    private func loadRecordsSync() -> [SegmentationTelemetryRecord] {
        guard let data = try? Data(contentsOf: recordsURL) else { return [] }
        return (try? decoder.decode([SegmentationTelemetryRecord].self, from: data)) ?? []
    }

    private func saveRecordsSync(_ records: [SegmentationTelemetryRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }
}
