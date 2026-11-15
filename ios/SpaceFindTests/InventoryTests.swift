import XCTest
@testable import SpaceFind

private actor LostReportClosureConflict: CrewAPI {
    private let snapshot: CrewSnapshot

    init(_ snapshot: CrewSnapshot) { self.snapshot = snapshot }

    func fetch() async throws -> CrewSnapshot { snapshot }

    func send(_ change: Change) async throws {
        if change.kind == .markFound { throw CrewError.alreadyFound(foundAt: "locker 2") }
    }
}

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

    func testOfflineLostReportSurvivesRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("inventory.json")
        let photo = Data([0xff, 0xd8, 0xff, 0xd9])
        let inventory = try Inventory(file: file)

        let reportID = try inventory.reportMissing(name: " Torque wrench ", lastSeen: " beside the workbench ", photo: photo)
        let createID = try XCTUnwrap(inventory.pendingChanges.first?.id)
        try inventory.markFound(reportID: reportID, foundAt: " locker 2 ")
        let foundID = try XCTUnwrap(inventory.pendingChanges.last?.id)
        let reopened = try Inventory(file: file)

        XCTAssertEqual(reopened.pendingChanges.map(\.kind), [.reportMissing, .markFound])
        XCTAssertEqual(reopened.pendingChanges.map(\.id), [createID, foundID])
        XCTAssertEqual(reopened.lostReports, [LostItemReport(id: reportID, name: "Torque wrench",
                                                             lastSeen: "beside the workbench", photo: photo,
                                                             foundAt: "locker 2")])
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertTrue(reopened.isPending(reportID))

        let noPhotoID = try reopened.reportMissing(name: "Tape measure", lastSeen: "north shelf", photo: nil)
        let noPhotoOperationID = try XCTUnwrap(reopened.pendingChanges.last?.id)
        let reopenedAgain = try Inventory(file: file)
        XCTAssertEqual(reopenedAgain.lostReports.first(where: { $0.id == noPhotoID })?.photo, nil)
        XCTAssertTrue(reopenedAgain.isPending(noPhotoID))
        XCTAssertEqual(reopenedAgain.pendingChanges.last?.id, noPhotoOperationID)
        XCTAssertTrue(reopenedAgain.items.isEmpty)
    }

    func testInvalidLostReportsDoNotQueue() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        let badPhoto = Data([1, 2, 3, 4])
        let oversizedText = String(repeating: "x", count: 3 * 1024 * 1024)

        XCTAssertThrowsError(try inventory.reportMissing(name: " \n ", lastSeen: "Locker", photo: nil))
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
        XCTAssertThrowsError(try inventory.reportMissing(name: "Wrench", lastSeen: " \t", photo: nil))
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
        XCTAssertThrowsError(try inventory.reportMissing(name: "Wrench", lastSeen: "Locker", photo: badPhoto))
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
        XCTAssertThrowsError(try inventory.reportMissing(name: oversizedText, lastSeen: "Locker", photo: nil))
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
        XCTAssertTrue(inventory.lostReports.isEmpty)
    }

    func testMarkFoundRejectsMissingAndAlreadyFoundReports() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        let reportID = try inventory.reportMissing(name: "Wrench", lastSeen: "Blue pouch", photo: nil)

        XCTAssertThrowsError(try inventory.markFound(reportID: UUID(), foundAt: "Locker"))
        XCTAssertThrowsError(try inventory.markFound(reportID: reportID, foundAt: " \n "))
        try inventory.markFound(reportID: reportID, foundAt: "Locker")
        XCTAssertThrowsError(try inventory.markFound(reportID: reportID, foundAt: "Tool bag"))
        XCTAssertEqual(inventory.pendingChanges.map(\.kind), [.reportMissing, .markFound])
    }

    func testClosureNoticeSurvivesRelaunchUntilDismissed() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("inventory.json")
        let inventory = try Inventory(file: file)
        let reportID = try inventory.reportMissing(name: "Wrench", lastSeen: "Blue pouch", photo: nil)
        try inventory.markFound(reportID: reportID, foundAt: "Tool bag")
        let snapshot = CrewSnapshot(items: [], lostReports: [LostItemReport(
            id: reportID, name: "Wrench", lastSeen: "Blue pouch", photo: nil, foundAt: "locker 2"
        )])

        try await inventory.sync(using: LostReportClosureConflict(snapshot))
        let reopened = try Inventory(file: file)

        XCTAssertEqual(reopened.closureNotices, [reportID: "locker 2"])
        XCTAssertEqual(reopened.lostReports.first?.foundAt, "locker 2")
        XCTAssertTrue(reopened.pendingChanges.isEmpty)
        reopened.dismissClosureNotice(reportID: reportID)
        XCTAssertNil(try Inventory(file: file).closureNotices[reportID])
    }

    func testLegacyCachePreservesPendingMove() throws {
        struct LegacyStore: Encodable {
            let items: [Item]
            let pending: [Change]
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("inventory.json")
        let itemID = UUID()
        let rootID = UUID()
        let originalMoveID = UUID()
        let oldPhoto = Data([8, 7, 6])
        let movePhoto = Data([5, 4, 3])
        let legacy = LegacyStore(
            items: [Item(id: itemID, label: "Wrench", description: "Socket", reports: [
                Report(id: rootID, location: "Blue pouch", photo: oldPhoto)
            ])],
            pending: [Change(id: originalMoveID, itemID: itemID, kind: .move, label: nil,
                             description: nil, parentID: rootID, location: "Locker 2", photo: movePhoto,
                             observedIDs: nil, chosenID: nil)]
        )
        try JSONEncoder().encode(legacy).write(to: file, options: .atomic)

        let reopened = try Inventory(file: file)

        XCTAssertEqual(reopened.pendingChanges.first?.id, originalMoveID)
        XCTAssertEqual(reopened.items.first?.reports.map(\.location), ["Locker 2"])
        XCTAssertEqual(reopened.items.first?.reports.map(\.photo), [movePhoto])
        XCTAssertTrue(reopened.lostReports.isEmpty)
    }

    func testAtomicWriteFailureDoesNotPublishLostReport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        try FileManager.default.removeItem(at: folder)

        XCTAssertThrowsError(try inventory.reportMissing(name: "Wrench", lastSeen: "Locker", photo: nil))
        XCTAssertTrue(inventory.lostReports.isEmpty)
        XCTAssertTrue(inventory.pendingChanges.isEmpty)
        XCTAssertTrue(inventory.items.isEmpty)
        XCTAssertTrue(inventory.closureNotices.isEmpty)
    }
}
