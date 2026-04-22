import Foundation
import SwiftData
import WoundCore

// MARK: - SwiftData Capture Bundle Store

/// Persists V5 CaptureBundle objects via SwiftData.
/// Completely independent from the existing LocalScanStorage
/// (file-based JSON for WoundScan).
final class SwiftDataCaptureBundleStore {

    private let modelContainer: ModelContainer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let schema = Schema([CaptureBundleEntity.self])
        let config = ModelConfiguration(
            "WoundOSCaptureBundles",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [config]
        )
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// For testing: in-memory store
    init(inMemory: Bool) throws {
        let schema = Schema([CaptureBundleEntity.self])
        let config = ModelConfiguration(
            "WoundOSCaptureBundlesTest",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [config]
        )
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @MainActor
    func save(_ bundle: CaptureBundle) throws {
        let context = modelContainer.mainContext
        let data = try encoder.encode(bundle)
        let entity = CaptureBundleEntity(
            captureId: bundle.id,
            capturedAt: bundle.capturedAt,
            captureMode: bundle.captureMode.rawValue,
            qualityTier: bundle.qualityScore.tier.rawValue,
            captureBundleData: data,
            deviceModel: bundle.sessionMetadata.deviceModel,
            lidarAvailable: bundle.sessionMetadata.lidarAvailable,
            confidenceScore: bundle.confidenceSummary.overallScore,
            scanId: nil
        )
        context.insert(entity)
        try context.save()
    }

    @MainActor
    func fetch(captureId: UUID) throws -> CaptureBundle? {
        let context = modelContainer.mainContext
        let predicate = #Predicate<CaptureBundleEntity> { $0.captureId == captureId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entity = try context.fetch(descriptor).first else { return nil }
        return try decoder.decode(CaptureBundle.self, from: entity.captureBundleData)
    }

    @MainActor
    func linkToScan(captureId: UUID, scanId: UUID) throws {
        let context = modelContainer.mainContext
        let predicate = #Predicate<CaptureBundleEntity> { $0.captureId == captureId }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let entity = try context.fetch(descriptor).first else { return }
        entity.scanId = scanId
        try context.save()
    }

    @MainActor
    func deleteOrphans(olderThan date: Date) throws {
        let context = modelContainer.mainContext
        let predicate = #Predicate<CaptureBundleEntity> {
            $0.scanId == nil && $0.capturedAt < date
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let orphans = try context.fetch(descriptor)
        for orphan in orphans {
            context.delete(orphan)
        }
        try context.save()
    }
}
