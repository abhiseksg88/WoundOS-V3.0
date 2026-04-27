import Foundation
import Combine
import WoundClinical

// MARK: - Patient Detail View Model

final class PatientDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published var patient: Patient
    @Published var wounds: [Wound] = []
    @Published var encounters: [Encounter] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Navigation

    var onEditPatient: ((Patient) -> Void)?
    var onWoundSelected: ((Wound) -> Void)?
    var onStartAssessment: ((Patient) -> Void)?

    // MARK: - Dependencies

    private let storage: ClinicalStorageProvider

    // MARK: - Init

    init(patient: Patient, storage: ClinicalStorageProvider) {
        self.patient = patient
        self.storage = storage
    }

    // MARK: - Data Loading

    func loadDetails() {
        isLoading = true

        Task { @MainActor in
            do {
                wounds = try await storage.fetchWounds(patientId: patient.id)
                encounters = try await storage.fetchEncounters(patientId: patient.id)

                if let refreshed = try await storage.fetchPatient(id: patient.id) {
                    patient = refreshed
                }

                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func editPatient() {
        onEditPatient?(patient)
    }

    func selectWound(_ wound: Wound) {
        onWoundSelected?(wound)
    }

    func startAssessment() {
        onStartAssessment?(patient)
    }
}
