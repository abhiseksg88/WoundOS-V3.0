import Foundation

public struct Wound: Codable, Sendable, Identifiable {
    public let id: UUID
    public let patientId: UUID
    public var label: String
    public var woundType: WoundClassification
    public var anatomicalLocation: AnatomicalLocation
    public var etiology: WoundEtiology?
    public var onsetDate: Date?
    public var isHealed: Bool
    public var healedDate: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        patientId: UUID,
        label: String,
        woundType: WoundClassification,
        anatomicalLocation: AnatomicalLocation,
        etiology: WoundEtiology? = nil,
        onsetDate: Date? = nil,
        isHealed: Bool = false,
        healedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patientId = patientId
        self.label = label
        self.woundType = woundType
        self.anatomicalLocation = anatomicalLocation
        self.etiology = etiology
        self.onsetDate = onsetDate
        self.isHealed = isHealed
        self.healedDate = healedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum WoundClassification: String, Codable, Sendable, CaseIterable {
    case pressureInjury
    case diabeticFootUlcer
    case venousLegUlcer
    case arterialUlcer
    case surgicalWound
    case traumatic
    case skinTear
    case other

    public var displayName: String {
        switch self {
        case .pressureInjury: return "Pressure Injury"
        case .diabeticFootUlcer: return "Diabetic Foot Ulcer"
        case .venousLegUlcer: return "Venous Leg Ulcer"
        case .arterialUlcer: return "Arterial Ulcer"
        case .surgicalWound: return "Surgical Wound"
        case .traumatic: return "Traumatic"
        case .skinTear: return "Skin Tear"
        case .other: return "Other"
        }
    }
}

public enum WoundEtiology: String, Codable, Sendable, CaseIterable {
    case pressure
    case diabeticNeuropathy
    case venousInsufficiency
    case arterialInsufficiency
    case surgical
    case traumatic
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .pressure: return "Pressure"
        case .diabeticNeuropathy: return "Diabetic Neuropathy"
        case .venousInsufficiency: return "Venous Insufficiency"
        case .arterialInsufficiency: return "Arterial Insufficiency"
        case .surgical: return "Surgical"
        case .traumatic: return "Traumatic"
        case .mixed: return "Mixed Etiology"
        case .unknown: return "Unknown"
        }
    }
}
