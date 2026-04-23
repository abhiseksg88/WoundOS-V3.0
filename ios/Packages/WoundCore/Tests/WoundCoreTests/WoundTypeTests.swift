import XCTest
@testable import WoundCore

final class WoundTypeTests: XCTestCase {

    func testAllCases_encodeDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for woundType in WoundType.allCases {
            let data = try encoder.encode(woundType)
            let decoded = try decoder.decode(WoundType.self, from: data)
            XCTAssertEqual(woundType, decoded, "Round-trip failed for \(woundType)")
        }
    }

    func testRawValues() {
        XCTAssertEqual(WoundType.footUlcer.rawValue, "foot_ulcer")
        XCTAssertEqual(WoundType.pressureInjury.rawValue, "pressure_injury")
        XCTAssertEqual(WoundType.surgicalWound.rawValue, "surgical_wound")
        XCTAssertEqual(WoundType.venousLegUlcer.rawValue, "venous_leg_ulcer")
        XCTAssertEqual(WoundType.unknown.rawValue, "unknown")
    }

    func testAllCasesCount() {
        XCTAssertEqual(WoundType.allCases.count, 5)
    }
}
