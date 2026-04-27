import Foundation

public struct ClinicalDocumentation: Codable, Sendable, Identifiable {
    public let id: UUID
    public let encounterId: UUID

    // AI-generated content
    public var aiNarrative: String
    public var aiTreatmentPlan: String
    public var aiHealingTrajectory: HealingTrajectory
    public var aiKeyFindings: [String]
    public var aiRecommendations: [String]

    // Nurse-edited final content
    public var finalNarrative: String
    public var finalTreatmentPlan: String
    public var nurseEdits: [NurseEdit]

    // Billing
    public var suggestedCPTCodes: [CPTCodeSuggestion]
    public var cmsComplianceChecklist: [ComplianceCheckItem]
    public var documentationCompletenessScore: Double

    // Status
    public var status: DocumentationStatus
    public var generatedAt: Date
    public var submittedAt: Date?
    public var submittedBy: String?

    public let modelVersion: String

    public init(
        id: UUID = UUID(),
        encounterId: UUID,
        aiNarrative: String = "",
        aiTreatmentPlan: String = "",
        aiHealingTrajectory: HealingTrajectory = .insufficientData,
        aiKeyFindings: [String] = [],
        aiRecommendations: [String] = [],
        finalNarrative: String = "",
        finalTreatmentPlan: String = "",
        nurseEdits: [NurseEdit] = [],
        suggestedCPTCodes: [CPTCodeSuggestion] = [],
        cmsComplianceChecklist: [ComplianceCheckItem] = [],
        documentationCompletenessScore: Double = 0,
        status: DocumentationStatus = .inProgress,
        generatedAt: Date = Date(),
        submittedAt: Date? = nil,
        submittedBy: String? = nil,
        modelVersion: String = ""
    ) {
        self.id = id
        self.encounterId = encounterId
        self.aiNarrative = aiNarrative
        self.aiTreatmentPlan = aiTreatmentPlan
        self.aiHealingTrajectory = aiHealingTrajectory
        self.aiKeyFindings = aiKeyFindings
        self.aiRecommendations = aiRecommendations
        self.finalNarrative = finalNarrative
        self.finalTreatmentPlan = finalTreatmentPlan
        self.nurseEdits = nurseEdits
        self.suggestedCPTCodes = suggestedCPTCodes
        self.cmsComplianceChecklist = cmsComplianceChecklist
        self.documentationCompletenessScore = documentationCompletenessScore
        self.status = status
        self.generatedAt = generatedAt
        self.submittedAt = submittedAt
        self.submittedBy = submittedBy
        self.modelVersion = modelVersion
    }
}

public enum HealingTrajectory: String, Codable, Sendable, CaseIterable {
    case improving
    case stable
    case deteriorating
    case insufficientData

    public var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .deteriorating: return "Deteriorating"
        case .insufficientData: return "Insufficient Data"
        }
    }
}

public struct NurseEdit: Codable, Sendable {
    public let field: String
    public let editedAt: Date

    public init(field: String, editedAt: Date = Date()) {
        self.field = field
        self.editedAt = editedAt
    }
}
