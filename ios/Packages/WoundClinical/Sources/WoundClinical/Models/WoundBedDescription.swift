import Foundation

public struct WoundBedDescription: Codable, Sendable {
    public var granulationPercent: Int
    public var sloughPercent: Int
    public var necroticPercent: Int
    public var epithelialPercent: Int
    public var otherPercent: Int

    public var totalPercent: Int {
        granulationPercent + sloughPercent + necroticPercent + epithelialPercent + otherPercent
    }

    public var isValid: Bool { totalPercent == 100 }

    public static let empty = WoundBedDescription(
        granulationPercent: 0,
        sloughPercent: 0,
        necroticPercent: 0,
        epithelialPercent: 0,
        otherPercent: 0
    )

    public init(
        granulationPercent: Int,
        sloughPercent: Int,
        necroticPercent: Int,
        epithelialPercent: Int,
        otherPercent: Int
    ) {
        self.granulationPercent = granulationPercent
        self.sloughPercent = sloughPercent
        self.necroticPercent = necroticPercent
        self.epithelialPercent = epithelialPercent
        self.otherPercent = otherPercent
    }
}
