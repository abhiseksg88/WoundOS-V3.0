import Foundation

public enum OdorLevel: String, Codable, Sendable, CaseIterable {
    case none, mild, moderate, strong

    public var displayName: String { rawValue.capitalized }
}
