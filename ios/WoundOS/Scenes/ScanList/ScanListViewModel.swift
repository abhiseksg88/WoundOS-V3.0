import Foundation
import Combine
import WoundCore

// MARK: - Scan List View Model

final class ScanListViewModel: ObservableObject {

    // MARK: - Published State

    @Published var scans: [WoundScan] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Navigation

    var onScanSelected: ((WoundScan) -> Void)?

    // MARK: - Dependencies

    private let storage: StorageProviderProtocol

    // MARK: - Init

    init(storage: StorageProviderProtocol) {
        self.storage = storage
    }

    // MARK: - Data Loading

    func loadScans(patientId: String = "") {
        isLoading = true

        Task { @MainActor in
            do {
                if patientId.isEmpty {
                    // Load all scans (for now)
                    scans = try await storage.fetchScans(patientId: "patient-001")
                } else {
                    scans = try await storage.fetchScans(patientId: patientId)
                }
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func selectScan(_ scan: WoundScan) {
        onScanSelected?(scan)
    }

    func deleteScan(at index: Int) {
        let scan = scans[index]
        scans.remove(at: index)

        Task {
            try? await storage.deleteScan(id: scan.id)
        }
    }
}
