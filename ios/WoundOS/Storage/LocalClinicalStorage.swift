import Foundation
import WoundClinical

final class LocalClinicalStorage: ClinicalStorageProvider, @unchecked Sendable {

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var baseDirectory: URL {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("WoundClinical", isDirectory: true)
        }
        return docs.appendingPathComponent("WoundClinical", isDirectory: true)
    }

    private func directory(for entity: String) -> URL {
        let dir = baseDirectory.appendingPathComponent(entity, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Generic Helpers

    private func save<T: Encodable>(_ entity: T, id: UUID, entityName: String) throws {
        let url = directory(for: entityName).appendingPathComponent("\(id.uuidString).json")
        let data = try encoder.encode(entity)
        try data.write(to: url, options: .atomic)
    }

    private func fetch<T: Decodable>(id: UUID, entityName: String) throws -> T? {
        let url = directory(for: entityName).appendingPathComponent("\(id.uuidString).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    private func fetchAll<T: Decodable>(entityName: String) throws -> [T] {
        let dir = directory(for: entityName)
        let contents = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return contents.compactMap { url -> T? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    private func delete(id: UUID, entityName: String) throws {
        let url = directory(for: entityName).appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Patient

    func savePatient(_ patient: Patient) async throws {
        try save(patient, id: patient.id, entityName: "patients")
    }

    func fetchPatient(id: UUID) async throws -> Patient? {
        try fetch(id: id, entityName: "patients")
    }

    func fetchAllPatients() async throws -> [Patient] {
        let patients: [Patient] = try fetchAll(entityName: "patients")
        return patients.sorted { $0.lastName < $1.lastName }
    }

    func searchPatients(query: String) async throws -> [Patient] {
        let all = try await fetchAllPatients()
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.firstName.lowercased().contains(q) ||
            $0.lastName.lowercased().contains(q) ||
            $0.medicalRecordNumber.lowercased().contains(q) ||
            ($0.roomNumber?.lowercased().contains(q) ?? false)
        }
    }

    func deletePatient(id: UUID) async throws {
        try delete(id: id, entityName: "patients")
    }

    // MARK: - Wound

    func saveWound(_ wound: Wound) async throws {
        try save(wound, id: wound.id, entityName: "wounds")
    }

    func fetchWounds(patientId: UUID) async throws -> [Wound] {
        let all: [Wound] = try fetchAll(entityName: "wounds")
        return all
            .filter { $0.patientId == patientId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchWound(id: UUID) async throws -> Wound? {
        try fetch(id: id, entityName: "wounds")
    }

    func deleteWound(id: UUID) async throws {
        try delete(id: id, entityName: "wounds")
    }

    // MARK: - Encounter

    func saveEncounter(_ encounter: Encounter) async throws {
        try save(encounter, id: encounter.id, entityName: "encounters")
    }

    func fetchEncounters(patientId: UUID) async throws -> [Encounter] {
        let all: [Encounter] = try fetchAll(entityName: "encounters")
        return all
            .filter { $0.patientId == patientId }
            .sorted { $0.visitDate > $1.visitDate }
    }

    func fetchEncounter(id: UUID) async throws -> Encounter? {
        try fetch(id: id, entityName: "encounters")
    }

    func fetchTodaysEncounters() async throws -> [Encounter] {
        let all: [Encounter] = try fetchAll(entityName: "encounters")
        let calendar = Calendar.current
        return all.filter { calendar.isDateInToday($0.visitDate) }
            .sorted { $0.visitDate > $1.visitDate }
    }

    func fetchIncompleteEncounters() async throws -> [Encounter] {
        let all: [Encounter] = try fetchAll(entityName: "encounters")
        return all.filter { $0.documentationStatus == .inProgress || $0.documentationStatus == .pendingReview }
            .sorted { $0.visitDate > $1.visitDate }
    }

    func deleteEncounter(id: UUID) async throws {
        try delete(id: id, entityName: "encounters")
    }

    // MARK: - Wound Assessment

    func saveAssessment(_ assessment: WoundAssessment) async throws {
        try save(assessment, id: assessment.id, entityName: "assessments")
    }

    func fetchAssessments(woundId: UUID) async throws -> [WoundAssessment] {
        let all: [WoundAssessment] = try fetchAll(entityName: "assessments")
        return all
            .filter { $0.woundId == woundId }
            .sorted { $0.assessedAt > $1.assessedAt }
    }

    func fetchAssessment(id: UUID) async throws -> WoundAssessment? {
        try fetch(id: id, entityName: "assessments")
    }

    // MARK: - Clinical Documentation

    func saveDocumentation(_ doc: ClinicalDocumentation) async throws {
        try save(doc, id: doc.id, entityName: "documentation")
    }

    func fetchDocumentation(encounterId: UUID) async throws -> ClinicalDocumentation? {
        let all: [ClinicalDocumentation] = try fetchAll(entityName: "documentation")
        return all.first { $0.encounterId == encounterId }
    }

    func fetchDocumentation(id: UUID) async throws -> ClinicalDocumentation? {
        try fetch(id: id, entityName: "documentation")
    }
}
