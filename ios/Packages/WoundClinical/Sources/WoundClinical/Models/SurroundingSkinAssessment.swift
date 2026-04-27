import Foundation

public struct SurroundingSkinAssessment: Codable, Sendable {
    public var conditions: [PeriwoundCondition]
    public var notes: String?

    public static let intact = SurroundingSkinAssessment(conditions: [.intact])

    public init(conditions: [PeriwoundCondition], notes: String? = nil) {
        self.conditions = conditions
        self.notes = notes
    }
}

public enum PeriwoundCondition: String, Codable, Sendable, CaseIterable {
    case intact
    case macerated
    case erythematous
    case indurated
    case calloused
    case excoriated
    case denuded
    case edematous
    case discolored

    public var displayName: String {
        switch self {
        case .intact: return "Intact"
        case .macerated: return "Macerated"
        case .erythematous: return "Erythematous"
        case .indurated: return "Indurated"
        case .calloused: return "Calloused"
        case .excoriated: return "Excoriated"
        case .denuded: return "Denuded"
        case .edematous: return "Edematous"
        case .discolored: return "Discolored"
        }
    }
}
