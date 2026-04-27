import Foundation

public struct CPTCodeSuggestion: Codable, Sendable, Identifiable {
    public let id: UUID
    public let code: String
    public let description: String
    public let category: CPTCategory
    public var isSelected: Bool
    public let confidenceReason: String

    public var displayText: String { "\(code) — \(description)" }

    public init(
        id: UUID = UUID(),
        code: String,
        description: String,
        category: CPTCategory,
        isSelected: Bool = false,
        confidenceReason: String = ""
    ) {
        self.id = id
        self.code = code
        self.description = description
        self.category = category
        self.isSelected = isSelected
        self.confidenceReason = confidenceReason
    }
}

public enum CPTCategory: String, Codable, Sendable, CaseIterable {
    case evaluation
    case debridement
    case negativePressure
    case dressingChange
    case skinSubstitute
    case other

    public var displayName: String {
        switch self {
        case .evaluation: return "Evaluation & Management"
        case .debridement: return "Debridement"
        case .negativePressure: return "Negative Pressure"
        case .dressingChange: return "Dressing Change"
        case .skinSubstitute: return "Skin Substitute"
        case .other: return "Other"
        }
    }
}

public enum WoundProcedure: String, Codable, Sendable, CaseIterable {
    case debridementSharp
    case debridementEnzymatic
    case debridementAutolytic
    case negativePressure
    case dressingSimple
    case dressingComplex
    case skinSubstitute
    case compression
    case offloading

    public var displayName: String {
        switch self {
        case .debridementSharp: return "Sharp Debridement"
        case .debridementEnzymatic: return "Enzymatic Debridement"
        case .debridementAutolytic: return "Autolytic Debridement"
        case .negativePressure: return "Negative Pressure Therapy"
        case .dressingSimple: return "Simple Dressing"
        case .dressingComplex: return "Complex Dressing"
        case .skinSubstitute: return "Skin Substitute"
        case .compression: return "Compression Therapy"
        case .offloading: return "Offloading"
        }
    }
}
