import XCTest

final class RadarTrialWalkthrough: XCTestCase {
    @MainActor func testOpenTrialWithoutCamera() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"] else {
            throw XCTSkip("Run against a disposable trial inventory.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let field = app.secureTextFields["pairing"]
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText(pairing)
            app.buttons["Join inventory"].tap()
        }
        XCTAssertTrue(app.buttons["radar-start"].waitForExistence(timeout: 20))
        if let target = env["SPACEFIND_TEST_RADAR_ITEM"] {
            app.buttons["Find a target"].tap()
            let row = app.buttons["radar-find-" + target.uppercased()]
            XCTAssertTrue(row.waitForExistence(timeout: 12))
            row.tap()
            let status = app.descendants(matching: .any).matching(identifier: "radar-finder-status").firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["radar-reveal-" + target.uppercased()].exists)

            let inventoryTab = app.tabBars.buttons["Inventory"]
            XCTAssertTrue(inventoryTab.waitForExistence(timeout: 5))
            inventoryTab.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Radar walk fixture")
            XCTAssertTrue(app.staticTexts["No matching items"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(identifier: "item-" + target.uppercased()).firstMatch.exists)
            let leakedFixture = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Radar walk fixture"))
            XCTAssertEqual(leakedFixture.count, 0, "Radar trial labels and thumbnails stay hidden in Inventory.")
        }
    }
}
