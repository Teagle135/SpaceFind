import XCTest
@testable import SpaceFind

private enum FakeCrewFailure: Error {
    case droppedAcknowledgment
}

private actor UnreliableCrew: CrewAPI {
    private var serverItems: [Item] = []
    private var acceptedIDs = Set<UUID>()
    private var sentIDs: [UUID] = []
    private var dropNextAcknowledgment = true
    private var beforeNextFetch: (@MainActor () throws -> Void)?

    func send(_ change: Change) async throws {
        sentIDs.append(change.id)
        guard acceptedIDs.insert(change.id).inserted else { return }
        guard change.kind == .create,
              let label = change.label,
              let location = change.location,
              let photo = change.photo else { return }
        serverItems.append(Item(id: change.itemID, label: label, description: change.description ?? "",
                                reports: [Report(id: change.id, location: location, photo: photo)]))
        if dropNextAcknowledgment {
            dropNextAcknowledgment = false
            throw FakeCrewFailure.droppedAcknowledgment
        }
    }

    func fetch() async throws -> [Item] {
        if let action = beforeNextFetch {
            beforeNextFetch = nil
            try await action()
        }
        return serverItems
    }

    func onNextFetch(_ action: @escaping @MainActor () throws -> Void) {
        beforeNextFetch = action
    }

    func sentChangeIDs() -> [UUID] { sentIDs }
}

private actor StaleConfirmationCrew: CrewAPI {
    private let initialItems: [Item]
    private let currentItems: [Item]
    private var fetchCount = 0

    init(initialItems: [Item], currentItems: [Item]) {
        self.initialItems = initialItems
        self.currentItems = currentItems
    }

    func send(_ change: Change) async throws {
        if change.kind == .confirm { throw CrewError.staleConfirmation }
    }

    func fetch() async throws -> [Item] {
        fetchCount += 1
        return fetchCount == 1 ? initialItems : currentItems
    }
}

@MainActor
final class SyncTests: XCTestCase {
    func testRetryReusesChangeIDAndSnapshotPreservesLaterPendingWork() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        try inventory.create(label: "Wrench", description: "Socket wrench", location: "Blue pouch", photo: Data([1]))
        let originalItemID = try XCTUnwrap(inventory.items.first?.id)
        let originalChangeID = try XCTUnwrap(inventory.pendingChanges.first?.id)
        let crew = UnreliableCrew()

        do {
            try await inventory.sync(using: crew)
            XCTFail("The dropped acknowledgment should leave the edit pending")
        } catch is FakeCrewFailure {
            XCTAssertTrue(inventory.isPending(originalItemID))
        }

        var laterItemID: UUID?
        await crew.onNextFetch {
            try inventory.create(label: "Tape", description: "", location: "Red pouch", photo: Data([2]))
            laterItemID = inventory.items.first(where: { $0.id != originalItemID })?.id
        }
        try await inventory.sync(using: crew)

        let sentIDs = await crew.sentChangeIDs()
        XCTAssertEqual(sentIDs, [originalChangeID, originalChangeID])
        let laterID = try XCTUnwrap(laterItemID)
        XCTAssertEqual(inventory.pendingChanges.map(\.itemID), [laterID])
        XCTAssertTrue(inventory.isPending(laterID))
        XCTAssertEqual(Set(inventory.items.map(\.id)), [originalItemID, laterID])
    }

    func testStaleConfirmationRefreshesCandidatesAndBlocksDependentMove() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        let itemID = UUID()
        let first = Report(id: UUID(), location: "Blue pouch", photo: Data([1]))
        let second = Report(id: UUID(), location: "Tool bag", photo: Data([2]))
        let third = Report(id: UUID(), location: "Locker 2", photo: Data([3]))
        let initial = Item(id: itemID, label: "Wrench", description: "", reports: [first, second])
        let current = Item(id: itemID, label: "Wrench", description: "", reports: [first, second, third])
        let crew = StaleConfirmationCrew(initialItems: [initial], currentItems: [current])
        try await inventory.sync(using: crew)
        try inventory.confirm(itemID: itemID, observedIDs: [first.id, second.id], chosenID: first.id)

        XCTAssertThrowsError(try inventory.move(itemID: itemID, parentID: first.id,
                                                location: "Hatch", photo: first.photo))
        do {
            try await inventory.sync(using: crew)
            XCTFail("The stale selection should be shown to the crew member")
        } catch CrewError.staleConfirmation {
            XCTAssertEqual(inventory.items.first?.reports.map(\.id), [first.id, second.id, third.id])
            XCTAssertFalse(inventory.isPending(itemID))
        }
    }
}
