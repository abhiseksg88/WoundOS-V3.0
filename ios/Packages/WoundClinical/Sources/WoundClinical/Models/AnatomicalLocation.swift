import Foundation

public struct AnatomicalLocation: Codable, Sendable, Equatable {
    public let region: BodyRegion
    public let laterality: Laterality
    public let specificSite: String?

    public var displayName: String {
        var parts: [String] = []
        if laterality != .notApplicable && laterality != .midline {
            parts.append(laterality.displayName)
        }
        parts.append(region.displayName)
        if let site = specificSite, !site.isEmpty {
            parts.append("(\(site))")
        }
        return parts.joined(separator: " ")
    }

    public init(
        region: BodyRegion,
        laterality: Laterality = .notApplicable,
        specificSite: String? = nil
    ) {
        self.region = region
        self.laterality = laterality
        self.specificSite = specificSite
    }
}

public enum BodyRegion: String, Codable, Sendable, CaseIterable {
    case sacrum
    case coccyx
    case heel
    case ankle
    case lowerLeg
    case foot
    case hip
    case trochanter
    case ischium
    case abdomen
    case chest
    case back
    case upperExtremity
    case hand
    case head
    case neck
    case perineum
    case buttock
    case knee
    case thigh
    case shoulder
    case other

    public var displayName: String {
        switch self {
        case .sacrum: return "Sacrum"
        case .coccyx: return "Coccyx"
        case .heel: return "Heel"
        case .ankle: return "Ankle"
        case .lowerLeg: return "Lower Leg"
        case .foot: return "Foot"
        case .hip: return "Hip"
        case .trochanter: return "Trochanter"
        case .ischium: return "Ischium"
        case .abdomen: return "Abdomen"
        case .chest: return "Chest"
        case .back: return "Back"
        case .upperExtremity: return "Upper Extremity"
        case .hand: return "Hand"
        case .head: return "Head"
        case .neck: return "Neck"
        case .perineum: return "Perineum"
        case .buttock: return "Buttock"
        case .knee: return "Knee"
        case .thigh: return "Thigh"
        case .shoulder: return "Shoulder"
        case .other: return "Other"
        }
    }

    public var requiresLaterality: Bool {
        switch self {
        case .sacrum, .coccyx, .abdomen, .chest, .back, .head, .neck, .perineum:
            return false
        default:
            return true
        }
    }
}

public enum Laterality: String, Codable, Sendable, CaseIterable {
    case left, right, midline, bilateral, notApplicable

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .midline: return "Midline"
        case .bilateral: return "Bilateral"
        case .notApplicable: return ""
        }
    }
}
