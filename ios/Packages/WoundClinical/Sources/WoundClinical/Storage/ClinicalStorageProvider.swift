import Foundation

public protocol ClinicalStorageProvider: Sendable {

    // MARK: - Patient

    func savePatient(_ patient: Patient) async throws
    func fetchPatient(id: UUID) async throws -> Patient?
    func fetchAllPatients() async throws -> [Patient]
    func searchPatients(query: String) async throws -> [Patient]
    func deletePatient(id: UUID) async throws

    // MARK: - Wound

    func saveWound(_ wound: Wound) async throws
    func fetchWounds(patientId: UUID) async throws -> [Wound]
    func fetchWound(id: UUID) async throws -> Wound?
    func deleteWound(id: UUID) async throws

    // MARK: - Encounter

    func saveEncounter(_ encounter: Encounter) async throws
    func fetchEncounters(patientId: UUID) async throws -> [Encounter]
    func fetchEncounter(id: UUID) async throws -> Encounter?
    func fetchTodaysEncounters() async throws -> [Encounter]
    func fetchIncompleteEncounters() async throws -> [Encounter]
    func deleteEncounter(id: UUID) async throws

    // MARK: - Wound Assessment

    func saveAssessment(_ assessment: WoundAssessment) async throws
    func fetchAssessments(woundId: UUID) async throws -> [WoundAssessment]
    func fetchAssessment(id: UUID) async throws -> WoundAssessment?

    // MARK: - Clinical Documentation

    func saveDocumentation(_ doc: ClinicalDocumentation) async throws
    func fetchDocumentation(encounterId: UUID) async throws -> ClinicalDocumentation?
    func fetchDocumentation(id: UUID) async throws -> ClinicalDocumentation?
}
