import XCTest
@testable import WoundCore

final class PUSHScoreTests: XCTestCase {

    // MARK: - Length × Width Sub-Score Lookup Table

    func testLengthWidthSubScore_zero() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0), 0)
    }

    func testLengthWidthSubScore_lessThan0_3() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.1), 1)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.29), 1)
    }

    func testLengthWidthSubScore_0_3_to_0_6() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.3), 2)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.5), 2)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.69), 2)
    }

    func testLengthWidthSubScore_0_7_to_1_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(0.7), 3)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(1.0), 3)
    }

    func testLengthWidthSubScore_1_1_to_2_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(1.1), 4)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(2.0), 4)
    }

    func testLengthWidthSubScore_2_1_to_3_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(2.1), 5)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(3.0), 5)
    }

    func testLengthWidthSubScore_3_1_to_4_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(3.1), 6)
    }

    func testLengthWidthSubScore_4_1_to_8_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(4.1), 7)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(8.0), 7)
    }

    func testLengthWidthSubScore_8_1_to_12_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(8.1), 8)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(12.0), 8)
    }

    func testLengthWidthSubScore_12_1_to_24_0() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(12.1), 9)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(24.0), 9)
    }

    func testLengthWidthSubScore_greaterThan24() {
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(24.1), 10)
        XCTAssertEqual(PUSHScore.lookupLengthWidthSubScore(100.0), 10)
    }

    // MARK: - Total Score Computation

    func testTotalScore_healed() {
        let score = PUSHScore(
            lengthTimesWidthCm2: 0,
            exudateAmount: .none,
            tissueType: .closed
        )
        XCTAssertEqual(score.totalScore, 0)
    }

    func testTotalScore_moderate() {
        // L×W = 5.0 cm² → sub-score 7
        // Exudate = moderate → sub-score 2
        // Tissue = granulation → sub-score 2
        // Total = 11
        let score = PUSHScore(
            lengthTimesWidthCm2: 5.0,
            exudateAmount: .moderate,
            tissueType: .granulation
        )
        XCTAssertEqual(score.lengthTimesWidthSubScore, 7)
        XCTAssertEqual(score.totalScore, 11)
    }

    func testTotalScore_worst() {
        // L×W = 30 cm² → sub-score 10
        // Exudate = heavy → sub-score 3
        // Tissue = necrotic → sub-score 4
        // Total = 17
        let score = PUSHScore(
            lengthTimesWidthCm2: 30.0,
            exudateAmount: .heavy,
            tissueType: .necroticTissue
        )
        XCTAssertEqual(score.totalScore, 17)
    }

    // MARK: - Exudate Sub-Scores

    func testExudateSubScores() {
        XCTAssertEqual(ExudateAmount.none.subScore, 0)
        XCTAssertEqual(ExudateAmount.light.subScore, 1)
        XCTAssertEqual(ExudateAmount.moderate.subScore, 2)
        XCTAssertEqual(ExudateAmount.heavy.subScore, 3)
    }

    // MARK: - Tissue Type Sub-Scores

    func testTissueTypeSubScores() {
        XCTAssertEqual(TissueType.closed.subScore, 0)
        XCTAssertEqual(TissueType.epithelial.subScore, 1)
        XCTAssertEqual(TissueType.granulation.subScore, 2)
        XCTAssertEqual(TissueType.slough.subScore, 3)
        XCTAssertEqual(TissueType.necroticTissue.subScore, 4)
    }

    // MARK: - Codable

    func testPUSHScore_roundTrip() throws {
        let original = PUSHScore(
            lengthTimesWidthCm2: 5.5,
            exudateAmount: .light,
            tissueType: .slough
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PUSHScore.self, from: data)

        XCTAssertEqual(decoded.totalScore, original.totalScore)
        XCTAssertEqual(decoded.exudateAmount, original.exudateAmount)
        XCTAssertEqual(decoded.tissueType, original.tissueType)
    }
}
