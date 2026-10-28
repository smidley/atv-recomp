import XCTest

final class RecompTVUITests: XCTestCase {
    @MainActor
    func testNativeBridgeAndMetalFrame() throws {
        let app = XCUIApplication()
        app.launch()

        let nativeResult = app.staticTexts["nativeProbeResult"]
        XCTAssertTrue(nativeResult.waitForExistence(timeout: 10))
        XCTAssertEqual(nativeResult.label, "C++ returned 42")

        let metalStatus = app.staticTexts["metalStatus"]
        let firstFrame = NSPredicate(format: "label == %@", "Metal frame 1 completed")
        expectation(for: firstFrame, evaluatedWith: metalStatus)
        waitForExpectations(timeout: 15)

        // The only button receives default tvOS focus. Select using the remote.
        XCUIRemote.shared.press(.select)
        let secondFrame = NSPredicate(format: "label == %@", "Metal frame 2 completed")
        expectation(for: secondFrame, evaluatedWith: metalStatus)
        waitForExpectations(timeout: 10)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "C++ bridge and Metal frame"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
