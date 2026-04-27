import Foundation

public struct ComplianceCheckItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public let requirement: String
    public let cmsGuideline: String
    public var isMet: Bool
    public var notes: String?

    public init(
        id: UUID = UUID(),
        requirement: String,
        cmsGuideline: String,
        isMet: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.requirement = requirement
        self.cmsGuideline = cmsGuideline
        self.isMet = isMet
        self.notes = notes
    }
}
