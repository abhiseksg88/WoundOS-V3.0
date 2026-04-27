import Foundation
import Combine
import WoundCore
import WoundClinical

// MARK: - Dashboard View Model

final class DashboardViewModel: ObservableObject {

    // MARK: - Summary Data

    struct TodaySummary {
        var scansToday: Int = 0
        var pendingDocumentation: Int = 0
        var pendingUploads: Int = 0
        var patientsSeenToday: Int = 0
    }

    // MARK: - Published State

    @Published var summary = TodaySummary()
    @Published var recentPatients: [Patient] = []
    @Published var woundCounts: [UUID: Int] = [:]
    @Published var incompleteEncounters: [Encounter] = []
    @Published var isLoading = false

    // MARK: - Navigation

    var onPatientSelected: ((Patient) -> Void)?

    // MARK: - Dependencies

    private let clinicalStorage: ClinicalStorageProvider
    private let scanStorage: StorageProviderProtocol

    // MARK: - Init

    init(clinicalStorage: ClinicalStorageProvider, scanStorage: StorageProviderProtocol) {
        self.clinicalStorage = clinicalStorage
        self.scanStorage = scanStorage
    }

    // MARK: - Data Loading

    func loadDashboard() {
        isLoading = true

        Task { @MainActor in
            do {
                let patients = try await clinicalStorage.fetchAllPatients()
                recentPatients = Array(patients.prefix(10))

                var counts: [UUID: Int] = [:]
                for patient in recentPatients {
                    let wounds = (try? await clinicalStorage.fetchWounds(patientId: patient.id)) ?? []
                    counts[patient.id] = wounds.filter { !$0.isHealed }.count
                }
                woundCounts = counts

                let todayEncounters = try await clinicalStorage.fetchTodaysEncounters()
                let incomplete = try await clinicalStorage.fetchIncompleteEncounters()
                incompleteEncounters = incomplete

                let pendingScans = try await scanStorage.fetchPendingUploads()

                summary = TodaySummary(
                    scansToday: todayEncounters.count,
                    pendingDocumentation: incomplete.count,
                    pendingUploads: pendingScans.count,
                    patientsSeenToday: Set(todayEncounters.map { $0.patientId }).count
                )

                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    func selectPatient(_ patient: Patient) {
        onPatientSelected?(patient)
    }
}
