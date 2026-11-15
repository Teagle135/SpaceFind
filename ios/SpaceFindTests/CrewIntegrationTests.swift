import UIKit
import XCTest
@testable import SpaceFind

@MainActor
final class CrewIntegrationTests: XCTestCase {
    func testTwoCrewMembersCloseLostReportOffline() async throws {
        guard let text = ProcessInfo.processInfo.environment["SPACEFIND_TEST_PAIRING"] else {
            throw XCTSkip("Supply a pairing string for a disposable laptop database.")
        }
        let pairing = try Pairing(text)
        let first = try await CrewService.join(pairing)
        let second = try await CrewService.join(pairing)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("first.json")
        var a = try Inventory(file: file)
        let b = try Inventory(file: folder.appendingPathComponent("second.json"))
        try await a.sync(using: first)
        let originalItems = a.items
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { renderer in
            UIColor.systemBlue.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 3, height: 3))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let id = try a.reportMissing(name: "Torque wrench", lastSeen: "beside the workbench", photo: jpeg)
        try await a.sync(using: first)
        try await b.sync(using: second)
        XCTAssertEqual(b.lostReports.first { $0.id == id }?.photo, jpeg)

        try a.markFound(reportID: id, foundAt: "tool bag")
        let sibling = try a.reportMissing(name: "Torque wrench", lastSeen: "hatch", photo: nil)
        try a.markFound(reportID: sibling, foundAt: "locker 3")
        a = try Inventory(file: file)
        XCTAssertTrue(a.isPending(sibling))
        try b.markFound(reportID: id, foundAt: "locker 2")
        try await b.sync(using: second)
        try await a.sync(using: first)
        try await b.sync(using: second)

        for store in [a, b] {
            let found = try XCTUnwrap(store.lostReports.first { $0.id == id })
            XCTAssertEqual(found.lastSeen, "beside the workbench")
            XCTAssertEqual(found.foundAt, "locker 2")
            XCTAssertEqual(found.photo, jpeg)
            let other = try XCTUnwrap(store.lostReports.first { $0.id == sibling })
            XCTAssertEqual(other.foundAt, "locker 3")
            XCTAssertNil(other.photo)
            XCTAssertTrue(store.pendingChanges.isEmpty)
            XCTAssertEqual(store.items, originalItems)
        }
        XCTAssertEqual(a.closureNotices[id], "locker 2")
        XCTAssertNil(b.closureNotices[id])
    }

    func testTwoClientsReconnectAndConfirmTheSamePhoto() async throws {
        guard let text = ProcessInfo.processInfo.environment["SPACEFIND_TEST_PAIRING"] else {
            throw XCTSkip("Supply a pairing string for a disposable laptop database.")
        }
        let pairing = try Pairing(text)
        let serviceA = try await CrewService.join(pairing)
        let serviceB = try await CrewService.join(pairing)
        XCTAssertNotEqual(serviceA.credentials.token, serviceB.credentials.token)

        let invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
        for key in ["fingerprint", "invite"] {
            var fields = invalid
            fields[key] = key == "invite" ? "incorrect" : String(repeating: "00", count: 32)
            let bad = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
            do {
                _ = try await CrewService.join(Pairing(bad))
                XCTFail("Joined with invalid \(key)")
            } catch { /* Both credentials are checked before inventory access. */ }
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urlA = folder.appendingPathComponent("a.json")
        var a = try Inventory(file: urlA)
        let b = try Inventory(file: folder.appendingPathComponent("b.json"))
        func photo(_ color: UIColor) throws -> Data {
            let size = CGSize(width: 12, height: 12)
            let image = UIGraphicsImageRenderer(size: size).image { renderer in
                color.setFill()
                renderer.fill(CGRect(origin: .zero, size: size))
            }
            return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        }
        let blue = try photo(.systemBlue)
        let red = try photo(.systemRed)
        try a.create(label: "Wrench", description: "12 mm", location: "blue pouch", photo: blue)
        let id = try XCTUnwrap(a.items.first?.id)
        try await a.sync(using: serviceA)
        try await b.sync(using: serviceB)
        let root = try XCTUnwrap(b.items.first { $0.id == id }?.reports.first)
        XCTAssertEqual(root.photo, blue)
        try a.move(itemID: id, parentID: root.id, location: "locker 2", photo: red)
        try b.move(itemID: id, parentID: root.id, location: "tool bag", photo: blue)
        a = try Inventory(file: urlA)
        XCTAssertTrue(a.isPending(id))
        try await b.sync(using: serviceB)
        try await a.sync(using: serviceA)
        let reports = try XCTUnwrap(a.items.first { $0.id == id }?.reports)
        XCTAssertEqual(Set(reports.map(\.location)), ["tool bag", "locker 2"])
        let chosen = try XCTUnwrap(reports.first { $0.location == "locker 2" })
        try a.confirm(itemID: id, observedIDs: reports.map(\.id), chosenID: chosen.id)
        try await a.sync(using: serviceA)
        try await b.sync(using: serviceB)
        let result = try XCTUnwrap(b.items.first { $0.id == id }?.reports)
        XCTAssertEqual(result.map(\.photo), [red])
        XCTAssertEqual(result.map(\.location), ["locker 2"])
    }
}
