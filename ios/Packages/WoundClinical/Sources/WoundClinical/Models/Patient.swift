import Foundation

public struct Patient: Codable, Sendable, Identifiable {
    public let id: UUID
    public var medicalRecordNumber: String
    public var firstName: String
    public var lastName: String
    public var dateOfBirth: Date
    public var gender: Gender
    public var roomNumber: String?
    public var riskFactors: [RiskFactor]
    public var allergies: [String]
    public var insuranceType: InsuranceType?
    public var isActive: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public var fullName: String { "\(firstName) \(lastName)" }

    public var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }

    public init(
        id: UUID = UUID(),
        medicalRecordNumber: String,
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        gender: Gender = .other,
        roomNumber: String? = nil,
        riskFactors: [RiskFactor] = [],
        allergies: [String] = [],
        insuranceType: InsuranceType? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.medicalRecordNumber = medicalRecordNumber
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.roomNumber = roomNumber
        self.riskFactors = riskFactors
        self.allergies = allergies
        self.insuranceType = insuranceType
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum Gender: String, Codable, Sendable, CaseIterable {
    case male, female, nonBinary, other, preferNotToSay
}

public enum RiskFactor: String, Codable, Sendable, CaseIterable {
    case diabetes
    case peripheralVascularDisease
    case immobility
    case malnutrition
    case incontinence
    case cognitiveImpairment
    case obesity
    case smoking
    case immunosuppressed
    case advancedAge
    case renalDisease

    public var displayName: String {
        switch self {
        case .diabetes: return "Diabetes"
        case .peripheralVascularDisease: return "PVD"
        case .immobility: return "Immobility"
        case .malnutrition: return "Malnutrition"
        case .incontinence: return "Incontinence"
        case .cognitiveImpairment: return "Cognitive Impairment"
        case .obesity: return "Obesity"
        case .smoking: return "Smoking"
        case .immunosuppressed: return "Immunosuppressed"
        case .advancedAge: return "Advanced Age"
        case .renalDisease: return "Renal Disease"
        }
    }
}

public enum InsuranceType: String, Codable, Sendable, CaseIterable {
    case medicare, medicaid, privatePayer, workersComp, va, tricare, other

    public var displayName: String {
        switch self {
        case .medicare: return "Medicare"
        case .medicaid: return "Medicaid"
        case .privatePayer: return "Private"
        case .workersComp: return "Workers' Comp"
        case .va: return "VA"
        case .tricare: return "TRICARE"
        case .other: return "Other"
        }
    }
}
