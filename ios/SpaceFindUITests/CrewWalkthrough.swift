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
