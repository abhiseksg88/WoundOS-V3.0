import Foundation

public struct PainAssessment: Codable, Sendable {
    public var level: Int
    public var timing: PainTiming
    public var notes: String?

    public init(level: Int, timing: PainTiming, notes: String? = nil) {
        self.level = min(max(level, 0), 10)
        self.timing = timing
        self.notes = notes
    }
}

public enum PainTiming: String, Codable, Sendable, CaseIterable {
    case atRest
    case withDressingChange
    case withActivity
    case constant
    case intermittent

    public var displayName: String {
        switch self {
        case .atRest: return "At Rest"
        case .withDressingChange: return "With Dressing Change"
        case .withActivity: return "With Activity"
        case .constant: return "Constant"
        case .intermittent: return "Intermittent"
        }
    }
}
