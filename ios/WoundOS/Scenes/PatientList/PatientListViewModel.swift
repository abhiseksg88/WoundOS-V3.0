import Foundation
import Combine
import WoundClinical

// MARK: - Patient List View Model

final class PatientListViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activePatients: [Patient] = []
    @Published var inactivePatients: [Patient] = []
    @Published var woundCounts: [UUID: Int] = [:]
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText: String = ""

    // MARK: - Navigation

    var onPatientSelected: ((Patient) -> Void)?
    var onAddPatientTapped: (() -> Void)?

    // MARK: - Dependencies

    private let storage: ClinicalStorageProvider

    // MARK: - Init

    init(storage: ClinicalStorageProvider) {
        self.storage = storage
    }

    // MARK: - Data Loading

    func loadPatients() {
        isLoading = true

        Task { @MainActor in
            do {
                let patients: [Patient]
                if searchText.isEmpty {
                    patients = try await storage.fetchAllPatients()
                } else {
                    patients = try await storage.searchPatients(query: searchText)
                }
                activePatients = patients.filter { $0.isActive }
                inactivePatients = patients.filter { !$0.isActive }

                var counts: [UUID: Int] = [:]
                for patient in patients {
                    let wounds = (try? await storage.fetchWounds(patientId: patient.id)) ?? []
                    let activeWounds = wounds.filter { !$0.isHealed }
                    counts[patient.id] = activeWounds.count
                }
                woundCounts = counts

                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func selectPatient(_ patient: Patient) {
        onPatientSelected?(patient)
    }

    func addPatient() {
        onAddPatientTapped?()
    }

    func deletePatient(at index: Int, isActive: Bool) {
        let patient = isActive ? activePatients[index] : inactivePatients[index]
        if isActive {
            activePatients.remove(at: index)
        } else {
            inactivePatients.remove(at: index)
        }

        Task {
            try? await storage.deletePatient(id: patient.id)
        }
    }
}
