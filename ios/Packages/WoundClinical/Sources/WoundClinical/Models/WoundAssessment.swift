import Foundation
import WoundCore

public struct WoundAssessment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let woundId: UUID
    public let encounterId: UUID
    public var scanId: UUID?

    public var woundBed: WoundBedDescription
    public var exudate: ExudateAssessment
    public var surroundingSkin: SurroundingSkinAssessment
    public var pain: PainAssessment?
    public var odor: OdorLevel
    public var tunneling: TunnelingAssessment?
    public var undermining: UnderminingAssessment?

    public var manualMeasurements: ManualMeasurements?

    public var clinicalNotes: String

    public let assessedAt: Date

    public init(
        id: UUID = UUID(),
        woundId: UUID,
        encounterId: UUID,
        scanId: UUID? = nil,
        woundBed: WoundBedDescription = .empty,
        exudate: ExudateAssessment = .none,
        surroundingSkin: SurroundingSkinAssessment = .intact,
        pain: PainAssessment? = nil,
        odor: OdorLevel = .none,
        tunneling: TunnelingAssessment? = nil,
        undermining: UnderminingAssessment? = nil,
        manualMeasurements: ManualMeasurements? = nil,
        clinicalNotes: String = "",
        assessedAt: Date = Date()
    ) {
        self.id = id
        self.woundId = woundId
        self.encounterId = encounterId
        self.scanId = scanId
        self.woundBed = woundBed
        self.exudate = exudate
        self.surroundingSkin = surroundingSkin
        self.pain = pain
        self.odor = odor
        self.tunneling = tunneling
        self.undermining = undermining
        self.manualMeasurements = manualMeasurements
        self.clinicalNotes = clinicalNotes
        self.assessedAt = assessedAt
    }
}

public struct TunnelingAssessment: Codable, Sendable {
    public var clockPosition: Int
    public var depthCm: Double

    public init(clockPosition: Int, depthCm: Double) {
        self.clockPosition = clockPosition
        self.depthCm = depthCm
    }
}

public struct UnderminingAssessment: Codable, Sendable {
    public var fromClockPosition: Int
    public var toClockPosition: Int
    public var depthCm: Double

    public init(fromClockPosition: Int, toClockPosition: Int, depthCm: Double) {
        self.fromClockPosition = fromClockPosition
        self.toClockPosition = toClockPosition
        self.depthCm = depthCm
    }
}
