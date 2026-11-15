import XCTest

final class RadarWalkthrough: XCTestCase {
    @MainActor func testRadarHomeLinksToInventoryAndFinderHidesPhotoUntilStopped() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"],
              let target = env["SPACEFIND_TEST_RADAR_ITEM"] else {
            throw XCTSkip("Run against the disposable radar walkthrough fixture.")
        }
        continueAfterFailure = false
        let app = launchInventory(pairing)

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
        let appearance = env["SPACEFIND_TEST_APPEARANCE"] ?? "system"
        attachScreenshot(named: "Radar home — \(appearance)", from: app)

        let createInventory = app.buttons["Create inventory item"]
        XCTAssertTrue(createInventory.waitForExistence(timeout: 8), app.debugDescription)
        createInventory.tap()
        XCTAssertTrue(app.navigationBars["Create inventory item"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["radar-capture"].waitForExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let findInventory = app.buttons["Find inventory item"]
        XCTAssertTrue(findInventory.waitForExistence(timeout: 5), app.debugDescription)
        findInventory.tap()

        let pickerSearch = app.searchFields.firstMatch
        XCTAssertTrue(pickerSearch.waitForExistence(timeout: 5), app.debugDescription)
        pickerSearch.tap()
        pickerSearch.typeText("Radar walk fixture")
        let targetID = target.uppercased()
        let targetButton = app.buttons["radar-find-" + targetID]
        XCTAssertTrue(targetButton.waitForExistence(timeout: 8), app.debugDescription)
        targetButton.tap()

        XCTAssertTrue(app.navigationBars["Radar walk fixture"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "radar-finder-status").firstMatch
            .waitForExistence(timeout: 8), app.debugDescription)
        attachScreenshot(named: "Radar finder — \(appearance)", from: app)
        XCTAssertEqual(app.images.matching(NSPredicate(
            format: "label == %@", "Photo of Radar walk fixture")).count, 0, app.debugDescription)
        XCTAssertFalse(app.buttons["radar-reveal-" + targetID].exists, app.debugDescription)
    }

    @MainActor func testInventorySearchFindsRadarItemAndOffersFinderLink() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"],
              let target = env["SPACEFIND_TEST_RADAR_ITEM"] else {
            throw XCTSkip("Run against the disposable radar walkthrough fixture.")
        }
        continueAfterFailure = false
        let app = launchInventory(pairing)
        let targetID = target.uppercased()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), app.debugDescription)
        search.tap()
        search.typeText("Radar walk fixture")

        let row = app.buttons["item-" + targetID]
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["Radar walk fixture"].waitForExistence(timeout: 5), app.debugDescription)

        let findWithRadar = app.buttons["Find with Radar"]
        XCTAssertTrue(findWithRadar.waitForExistence(timeout: 5), app.debugDescription)
        findWithRadar.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "radar-finder-status").firstMatch
            .waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.images.matching(NSPredicate(
            format: "label == %@", "Photo of Radar walk fixture")).count, 0, app.debugDescription)
        XCTAssertFalse(app.buttons["radar-reveal-" + targetID].exists, app.debugDescription)
    }

    @MainActor func testUnpositionedInventoryItemOffersRadarPositionRecording() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"],
              let unpositioned = env["SPACEFIND_TEST_UNPOSITIONED_ITEM"] else {
            throw XCTSkip("Run against the disposable unpositioned inventory fixture.")
        }
        continueAfterFailure = false
        let app = launchInventory(pairing)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), app.debugDescription)
        search.tap()
        search.typeText("Radar ordinary fixture")

        let row = app.buttons["item-" + unpositioned.uppercased()]
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["Radar ordinary fixture"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Record radar position"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor private func launchInventory(_ pairing: String) -> XCUIApplication {
        let app = XCUIApplication()
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
