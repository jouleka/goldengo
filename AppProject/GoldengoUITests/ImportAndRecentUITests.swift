import XCTest

final class ImportAndRecentUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func test_sampleImport_showsGreenSalaryInRecent() throws {
        // Navigate to Import tab
        app.tabBars.buttons["Import"].tap()

        // Tap the sample statement button
        app.buttons["Try a sample statement"].tap()

        // Wait for import result to appear
        let resultPredicate = NSPredicate(format: "label CONTAINS 'Imported'")
        let resultText = app.staticTexts.matching(resultPredicate).firstMatch
        XCTAssertTrue(resultText.waitForExistence(timeout: 5))

        // Navigate to Recent tab
        app.tabBars.buttons["Recent"].tap()

        // Wait for rows to load
        let salaryLabel = app.staticTexts["SALARY"]
        XCTAssertTrue(salaryLabel.waitForExistence(timeout: 5))

        // Take a screenshot and save it
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "recent-after-fixes"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also save directly to .build directory via file write
        let png = screenshot.pngRepresentation
        let savePath = URL(fileURLWithPath: "/Users/jurgenleka/Public/WorkRepos/personal-work/goldengo/AppProject/.build/recent-after-fixes.png")
        try png.write(to: savePath)

        // Verify 4 rows visible
        XCTAssertTrue(app.staticTexts["SPAR TIRANA"].exists)
        XCTAssertTrue(app.staticTexts["COFFEE CORNER"].exists)
        XCTAssertTrue(app.staticTexts["CONAD MARKET"].exists)
        XCTAssertTrue(salaryLabel.exists)
    }
}
