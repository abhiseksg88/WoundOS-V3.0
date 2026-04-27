import Foundation

public protocol ClinicalNotesGenerating: Sendable {
    func generate(
        assessments: [WoundAssessment],
        patient: Patient,
        wound: Wound,
        priorAssessments: [WoundAssessment]
    ) async throws -> ClinicalDocumentation
}
