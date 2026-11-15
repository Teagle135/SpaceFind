import XCTest
@testable import SpaceFind

@MainActor
final class InventoryTests: XCTestCase {
    func testOfflineCreateAndTwoMovesSurviveReopenInOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("inventory.json")
        let firstPhoto = Data([1, 2, 3])
        let secondPhoto = Data([4, 5, 6])
        let newestPhoto = Data([7, 8, 9])

        let inventory = try Inventory(file: file)
        try inventory.create(label: "Wrench", description: "Socket wrench", location: "Blue pouch", photo: firstPhoto)
        let itemID = try XCTUnwrap(inventory.items.first?.id)
        let createID = try XCTUnwrap(inventory.pendingChanges.first?.id)
        try inventory.move(itemID: itemID, parentID: createID, location: "Tool bag", photo: secondPhoto)
        let firstMoveID = try XCTUnwrap(inventory.pendingChanges.last?.id)
        try inventory.move(itemID: itemID, parentID: firstMoveID, location: "Locker 2", photo: newestPhoto)
        let pendingIDs = inventory.pendingChanges.map(\.id)

        let reopened = try Inventory(file: file)

        XCTAssertEqual(reopened.items.map(\.id), [itemID])
        XCTAssertEqual(reopened.items.first?.reports.map(\.location), ["Locker 2"])
        XCTAssertEqual(reopened.items.first?.reports.first?.photo, newestPhoto)
        XCTAssertEqual(reopened.pendingChanges.map(\.id), pendingIDs)
        XCTAssertEqual(reopened.pendingChanges.map(\.kind), [.create, .move, .move])
    }

    func testSearchFindsPartialTextAndSameLabelsRemainSeparate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        try inventory.create(label: "Wrench", description: "Calibrated socket set", location: "Upper locker", photo: Data([1]))
        let firstID = try XCTUnwrap(inventory.items.first?.id)
        try inventory.create(label: "Wrench", description: "Open end", location: "Red pouch", photo: Data([2]))
        let secondID = try XCTUnwrap(inventory.items.first(where: { $0.id != firstID })?.id)

        XCTAssertEqual(Set(inventory.search("wREN").map(\.id)), [firstID, secondID])
        XCTAssertEqual(inventory.search("ibrated").map(\.id), [firstID])
        XCTAssertEqual(inventory.search("upper lock").map(\.id), [firstID])
        XCTAssertEqual(inventory.search("ed pouch").map(\.id), [secondID])
        XCTAssertEqual(Set(inventory.search("").map(\.id)), [firstID, secondID])
    }

    func testInvalidLocalRecordIsNotQueued() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))

        XCTAssertThrowsError(try inventory.create(label: "Wrench",
                                                   description: String(repeating: "x", count: 3 * 1024 * 1024),
                                                   location: "Blue pouch", photo: Data([1])))
        XCTAssertThrowsError(try inventory.create(label: " ", description: "", location: "Locker", photo: Data([1])))
        XCTAssertThrowsError(try inventory.create(label: "Wrench", description: "", location: "Locker",
                                                    photo: Data(repeating: 0, count: 2 * 1024 * 1024 + 1)))
        XCTAssertTrue(inventory.items.isEmpty)
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
    }
}
