import XCTest

final class CrewWalkthrough: XCTestCase {
    // The rehearsal uses a fresh simulator and disposable crew inventory.
    @MainActor func testJoinSearchAndInspectWrench() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let pairing = environment["SPACEFIND_TEST_PAIRING"],
              let item = environment["SPACEFIND_TEST_ITEM"],
              let chosen = environment["SPACEFIND_TEST_CHOSEN"] else {
            throw XCTSkip("Requires the disposable crew and item from the demo rehearsal.")
        }
        continueAfterFailure = false
        let app = openInventory(pairing)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        search.tap()
        search.typeText("Walkthrough")
        let row = app.buttons["item-" + item.uppercased()]
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.tap()
        if environment["SPACEFIND_TEST_SECOND_PHONE"] != "1" {
            let select = app.buttons["confirm-" + chosen.uppercased()]
            XCTAssertTrue(select.waitForExistence(timeout: 6), app.debugDescription)
            select.tap()
        }
        let edit = app.buttons["update-location"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "locker 2")).firstMatch.exists,
                      app.debugDescription)
        edit.tap()
        let cancel = app.buttons["cancel-edit"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
    }

    @MainActor func testRecordPhotoFromLibrary() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pairing = env["SPACEFIND_TEST_PAIRING"] else {
            throw XCTSkip("Requires a disposable crew and a simulator library photo.")
        }
        continueAfterFailure = false
        let app = openInventory(pairing)
        let add = app.buttons["Add item"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        app.buttons["Choose from Library"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 8), app.debugDescription)
        // PhotosPicker exposes an image frame for each tile inside its remote view.
        let frame = photo.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let name = "Photo check " + UUID().uuidString.prefix(6)
        let label = app.textFields["Item label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText(String(name))
        let location = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %d OR elementType == %d)",
            "Item location", XCUIElement.ElementType.textView.rawValue,
            XCUIElement.ElementType.textField.rawValue)).firstMatch
        location.tap()
        location.typeText("Blue pouch")
        app.buttons["Save"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", String(name))).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor func testSharedLostItemWalkthrough() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let pairing = environment["SPACEFIND_TEST_PAIRING"],
              let sharedItemID = environment["SPACEFIND_TEST_ITEM"] else {
            throw XCTSkip("Requires the disposable crew from the demo rehearsal.")
        }
        continueAfterFailure = false
        let app = openInventory(pairing)
        let lostItemsTab = app.tabBars.buttons["Lost items"]
        XCTAssertTrue(lostItemsTab.waitForExistence(timeout: 15), app.debugDescription)
        lostItemsTab.tap()

        // This name is shared by both phones and unique to this disposable rehearsal.
        let name = "Walkthrough missing " + String(sharedItemID.prefix(8))
        if environment["SPACEFIND_TEST_SECOND_PHONE"] == "1" {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
            row.tap()

            XCTAssertTrue(app.staticTexts["Missing"].waitForExistence(timeout: 10), app.debugDescription)
            let markFound = app.buttons["mark-found-save"]
            let openFoundForm = app.buttons["Mark as found"]
            XCTAssertTrue(openFoundForm.waitForExistence(timeout: 8), app.debugDescription)
            openFoundForm.tap()
            XCTAssertTrue(markFound.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertFalse(markFound.isEnabled, app.debugDescription)
            app.buttons["cancel-mark-found"].tap()
            XCTAssertTrue(app.staticTexts["Missing"].waitForExistence(timeout: 5), app.debugDescription)

            app.buttons["Mark as found"].tap()
            let foundLocation = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND (elementType == %d OR elementType == %d)",
                "Where did you find it?", XCUIElement.ElementType.textView.rawValue,
                XCUIElement.ElementType.textField.rawValue)).firstMatch
            XCTAssertTrue(foundLocation.waitForExistence(timeout: 8), app.debugDescription)
            let saveFound = app.buttons["mark-found-save"]
            XCTAssertFalse(saveFound.isEnabled, app.debugDescription)
            foundLocation.tap()
            foundLocation.typeText("locker 2")
            XCTAssertTrue(saveFound.isEnabled, app.debugDescription)
            saveFound.tap()

            XCTAssertTrue(app.staticTexts["Found"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.staticTexts["Last seen"].exists, app.debugDescription)
            XCTAssertTrue(app.staticTexts["beside the workbench"].exists, app.debugDescription)
            XCTAssertTrue(app.staticTexts["Found at"].exists, app.debugDescription)
            XCTAssertTrue(app.staticTexts["locker 2"].exists, app.debugDescription)
        } else {
            let add = app.buttons["Report a missing item"].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 8), app.debugDescription)
            add.tap()

            app.buttons["Choose from Library"].tap()
            let cancelPicker = app.buttons["Cancel"]
            XCTAssertTrue(cancelPicker.waitForExistence(timeout: 8), app.debugDescription)
            cancelPicker.tap()

            let nameField = app.textFields["Item name"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 8), app.debugDescription)
            nameField.tap()
            nameField.typeText(name)
            let lastSeenField = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@ AND (elementType == %d OR elementType == %d)",
                "Where was it last seen?", XCUIElement.ElementType.textView.rawValue,
                XCUIElement.ElementType.textField.rawValue)).firstMatch
            lastSeenField.tap()
            lastSeenField.typeText("beside the workbench")
            let saveReport = app.buttons["Report missing item"]
            XCTAssertTrue(saveReport.isEnabled, app.debugDescription)
            saveReport.tap()

            let reportRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            XCTAssertTrue(reportRow.waitForExistence(timeout: 8), app.debugDescription)
            let synced = XCTNSPredicateExpectation(predicate: NSPredicate(
                format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)", name, "Waiting to sync"
            ), object: reportRow)
            XCTAssertEqual(XCTWaiter.wait(for: [synced], timeout: 20), .completed, app.debugDescription)
        }
    }

    @MainActor private func openInventory(_ pairing: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let field = app.secureTextFields["pairing"]
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText(pairing)
            app.buttons["Join inventory"].tap()
        }
        return app
    }
}
