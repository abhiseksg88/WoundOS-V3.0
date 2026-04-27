import Foundation
import Combine
import WoundClinical

// MARK: - Patient Form View Model

final class PatientFormViewModel: ObservableObject {

    // MARK: - Form Fields

    @Published var firstName: String
    @Published var lastName: String
    @Published var medicalRecordNumber: String
    @Published var dateOfBirth: Date
    @Published var gender: Gender
    @Published var roomNumber: String
    @Published var insuranceType: InsuranceType?
    @Published var selectedRiskFactors: Set<RiskFactor>
    @Published var isSaving = false
    @Published var error: String?

    // MARK: - Navigation

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State

    let isEditing: Bool
    private let existingId: UUID?
    private let createdAt: Date
    private let storage: ClinicalStorageProvider

    // MARK: - Init

    init(patient: Patient?, storage: ClinicalStorageProvider) {
        self.storage = storage
        self.isEditing = patient != nil
        self.existingId = patient?.id
        self.createdAt = patient?.createdAt ?? Date()
        self.firstName = patient?.firstName ?? ""
        self.lastName = patient?.lastName ?? ""
        self.medicalRecordNumber = patient?.medicalRecordNumber ?? ""
        self.dateOfBirth = patient?.dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -65, to: Date())!
        self.gender = patient?.gender ?? .other
        self.roomNumber = patient?.roomNumber ?? ""
        self.insuranceType = patient?.insuranceType
        self.selectedRiskFactors = Set(patient?.riskFactors ?? [])
    }

    // MARK: - Validation

    var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !medicalRecordNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    func save() {
        guard isValid else {
            error = "Please fill in all required fields."
            return
        }
        isSaving = true

        let patient = Patient(
            id: existingId ?? UUID(),
            medicalRecordNumber: medicalRecordNumber.trimmingCharacters(in: .whitespaces),
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dateOfBirth,
            gender: gender,
            roomNumber: roomNumber.isEmpty ? nil : roomNumber.trimmingCharacters(in: .whitespaces),
            riskFactors: Array(selectedRiskFactors),
            insuranceType: insuranceType,
            isActive: true,
            createdAt: createdAt,
            updatedAt: Date()
        )

        Task { @MainActor in
            do {
                try await storage.savePatient(patient)
                isSaving = false
                onSave?()
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }

    func cancel() {
        onCancel?()
    }

    func toggleRiskFactor(_ factor: RiskFactor) {
        if selectedRiskFactors.contains(factor) {
            selectedRiskFactors.remove(factor)
        } else {
            selectedRiskFactors.insert(factor)
        }
    }
}
