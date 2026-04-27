import Foundation

public struct Encounter: Codable, Sendable, Identifiable {
    public let id: UUID
    public let patientId: UUID
    public let nurseId: String
    public let facilityId: String
    public let visitDate: Date
    public var woundAssessmentIds: [UUID]
    public var documentationId: UUID?
    public var documentationStatus: DocumentationStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        patientId: UUID,
        nurseId: String,
        facilityId: String,
        visitDate: Date = Date(),
        woundAssessmentIds: [UUID] = [],
        documentationId: UUID? = nil,
        documentationStatus: DocumentationStatus = .inProgress,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patientId = patientId
        self.nurseId = nurseId
        self.facilityId = facilityId
        self.visitDate = visitDate
        self.woundAssessmentIds = woundAssessmentIds
        self.documentationId = documentationId
        self.documentationStatus = documentationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DocumentationStatus: String, Codable, Sendable, CaseIterable {
    case inProgress
    case pendingReview
    case complete
    case submitted

    public var displayName: String {
        switch self {
        case .inProgress: return "In Progress"
        case .pendingReview: return "Pending Review"
        case .complete: return "Complete"
        case .submitted: return "Submitted"
        }
    }
}
