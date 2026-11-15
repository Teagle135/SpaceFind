import XCTest

final class RadarWalkthrough: XCTestCase {
    @MainActor func testRadarIsReachableAlongsideInventoryAndLostItems() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"],
              let target = env["SPACEFIND_TEST_RADAR_ITEM"] else {
            throw XCTSkip("Run against the disposable radar walkthrough fixture.")
        }
        continueAfterFailure = false
        let app = launchInventory(pairing, appearance: "Light")

        let inventoryTab = app.tabBars.buttons["Inventory"]
        XCTAssertTrue(inventoryTab.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(inventoryTab.isSelected, app.debugDescription)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        let lostItemsTab = app.tabBars.buttons["Lost items"]
        XCTAssertTrue(lostItemsTab.waitForExistence(timeout: 5), app.debugDescription)
        lostItemsTab.tap()
        XCTAssertTrue(app.navigationBars["Lost items"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Report a missing item"].waitForExistence(timeout: 5), app.debugDescription)

        let radarTab = app.tabBars.buttons["Radar"]
        XCTAssertTrue(radarTab.waitForExistence(timeout: 5), app.debugDescription)
        radarTab.tap()
        XCTAssertTrue(app.buttons["radar-start"].waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(named: "Radar home — light", from: app)

        let findTarget = app.buttons["Find a target"]
        XCTAssertTrue(findTarget.waitForExistence(timeout: 5), app.debugDescription)
        findTarget.tap()
        let targetID = target.uppercased()
        let targetButton = app.buttons["radar-find-" + targetID]
        XCTAssertTrue(targetButton.waitForExistence(timeout: 12), app.debugDescription)
        if !targetButton.isHittable { app.swipeUp() }
        XCTAssertTrue(targetButton.isHittable, app.debugDescription)
        targetButton.tap()

        let status = app.descendants(matching: .any)
            .matching(identifier: "radar-finder-status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["radar-reveal-" + targetID].exists, app.debugDescription)
        XCTAssertEqual(app.images.matching(NSPredicate(
            format: "label == %@", "Photo of Radar walk fixture")).count, 0, app.debugDescription)
        attachScreenshot(named: "Radar finder — light", from: app)

        inventoryTab.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("Radar walk fixture")
        XCTAssertTrue(app.staticTexts["No matching items"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["item-" + targetID].exists, app.debugDescription)
        XCTAssertEqual(app.images.matching(NSPredicate(
            format: "label == %@", "Photo of Radar walk fixture")).count, 0, app.debugDescription)

        app.terminate()
        app.launchArguments = ["-uiUserInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 15), app.debugDescription)
        app.tabBars.buttons["Radar"].tap()
        XCTAssertTrue(app.buttons["radar-start"].waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(named: "Radar home — dark", from: app)
    }

    @MainActor private func launchInventory(_ pairing: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiUserInterfaceStyle", appearance]
        app.launch()
        let field = app.secureTextFields["pairing"]
        let inventory = app.searchFields.firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists || inventory.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, app.debugDescription)
        if field.exists {
            field.tap()
            field.typeText(pairing)
            app.buttons["Join inventory"].tap()
        }
        return app
    }

    @MainActor private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
