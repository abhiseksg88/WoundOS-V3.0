import Foundation
import WoundCore

public struct ExudateAssessment: Codable, Sendable {
    public var amount: ExudateAmount
    public var type: ExudateType
    public var color: ExudateColor

    public static let none = ExudateAssessment(
        amount: .none,
        type: .serous,
        color: .clear
    )

    public init(amount: ExudateAmount, type: ExudateType, color: ExudateColor) {
        self.amount = amount
        self.type = type
        self.color = color
    }
}

public enum ExudateType: String, Codable, Sendable, CaseIterable {
    case serous
    case sanguineous
    case serosanguineous
    case purulent

    public var displayName: String {
        switch self {
        case .serous: return "Serous"
        case .sanguineous: return "Sanguineous"
        case .serosanguineous: return "Serosanguineous"
        case .purulent: return "Purulent"
        }
    }
}

public enum ExudateColor: String, Codable, Sendable, CaseIterable {
    case clear, yellow, green, brown, red, pink

    public var displayName: String { rawValue.capitalized }
}
