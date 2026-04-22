import XCTest

final class CaptureFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureTab_existsAndTappable() throws {
        let app = XCUIApplication()
        app.launch()

        let captureTab = app.tabBars.buttons["Capture"]
        XCTAssertTrue(captureTab.waitForExistence(timeout: 5), "Capture tab should exist")
        captureTab.tap()
    }

    func testV5CaptureScreen_appearsWithFeatureFlag() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--enable-v5-lidar-capture")
        app.launch()

        let captureTab = app.tabBars.buttons["Capture"]
        XCTAssertTrue(captureTab.waitForExistence(timeout: 5))
        captureTab.tap()

        // On simulator the V5 capture screen should appear with identifiable elements
        let v5Screen = app.otherElements["v5_capture_screen"]
        XCTAssertTrue(
            v5Screen.waitForExistence(timeout: 5),
            "V5 capture screen should appear when feature flag is enabled"
        )
    }

    func testV4CaptureScreen_appearsWithoutFeatureFlag() throws {
        let app = XCUIApplication()
        // No --enable-v5-lidar-capture flag
        app.launch()

        let captureTab = app.tabBars.buttons["Capture"]
        XCTAssertTrue(captureTab.waitForExistence(timeout: 5))
        captureTab.tap()

        // V4 screen should be present, V5 should not
        let v5Screen = app.otherElements["v5_capture_screen"]
        XCTAssertFalse(
            v5Screen.waitForExistence(timeout: 3),
            "V5 capture screen should NOT appear when feature flag is disabled"
        )
    }
}
