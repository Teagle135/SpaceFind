import UIKit
import XCTest
@testable import SpaceFind

final class RadarTrialTests: XCTestCase {
    func testLocationDecodesOnlyFiniteVersionedPairs() {
        let point = RadarPoint(x: -2.125, y: 3.5)
        XCTAssertEqual(RadarPoint(trialLocation: point.trialLocation), point)
        let note = "Upper shelf, behind the red bin"
        let report = Report(id: UUID(), location: point.trialLocation(keeping: note), photo: Data([1]))
        XCTAssertEqual(report.radarPosition, point)
        XCTAssertEqual(report.locationNote, note)
        XCTAssertEqual(report.displayLocation, note)

        let ordinary = Report(id: UUID(), location: "Locker 2", photo: Data([2]))
        XCTAssertNil(ordinary.radarPosition)
        XCTAssertEqual(ordinary.locationNote, "Locker 2")
        XCTAssertEqual(ordinary.displayLocation, "Locker 2")

        let legacy = Report(id: UUID(), location: point.trialLocation, photo: Data([3]))
        XCTAssertEqual(legacy.radarPosition, point)
        XCTAssertEqual(legacy.locationNote, "")
        XCTAssertEqual(legacy.displayLocation, "Saved radar position")

        for input in ["blue pouch", "spacefind-radar-v1 1", "spacefind-radar-v2 1 2",
                      "spacefind-radar-v1 nan 1", "spacefind-radar-v1 1 inf",
                      "spacefind-radar-v1 1 2 3"] {
            XCTAssertNil(RadarPoint(trialLocation: input), input)
        }
    }

    @MainActor func testSavingRadarPositionMovesTheExistingInventoryItem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inventory = try Inventory(file: folder.appendingPathComponent("inventory.json"))
        let originalPhoto = Data([1])
        let radarPhoto = Data([2])
        try inventory.create(label: "Wrench", description: "12 mm socket", location: "Tool cabinet",
                             photo: originalPhoto)
        let originalID = try XCTUnwrap(inventory.items.first?.id)
        let original = try XCTUnwrap(inventory.items.first)
        try inventory.create(label: "Wrench", description: "Spare wrench", location: "Red pouch",
                             photo: Data([3]))
        let otherID = try XCTUnwrap(inventory.items.first(where: { $0.id != originalID })?.id)
        let point = RadarPoint(x: -4.25, y: 1.5)
        let note = "Tool cabinet, lower drawer"

        let returnedID = try inventory.saveRadarPhoto(for: original, label: original.label,
                                                      locationNote: note, photo: radarPhoto, at: point)

        XCTAssertEqual(returnedID, originalID)
        XCTAssertEqual(inventory.items.count, 2)
        let moved = try XCTUnwrap(inventory.items.first(where: { $0.id == originalID }))
        XCTAssertEqual(moved.label, "Wrench")
        XCTAssertEqual(moved.description, "12 mm socket")
        XCTAssertEqual(moved.reports.map(\.photo), [radarPhoto])
        XCTAssertEqual(moved.reports.first?.radarPosition, point)
        XCTAssertEqual(moved.reports.first?.locationNote, note)
        XCTAssertEqual(moved.reports.first?.displayLocation, note)
        let untouched = try XCTUnwrap(inventory.items.first(where: { $0.id == otherID }))
        XCTAssertEqual(untouched.label, "Wrench")
        XCTAssertEqual(untouched.description, "Spare wrench")
        XCTAssertEqual(untouched.reports.first?.photo, Data([3]))

        let afterMove = inventory.items
        XCTAssertThrowsError(try inventory.saveRadarPhoto(for: original, label: original.label,
                                                           locationNote: note, photo: Data([4]),
                                                           at: RadarPoint(x: 8, y: 9)))
        XCTAssertEqual(inventory.items, afterMove)
    }

    func testShutterFreezesPositionUntilPhotoArrivesAndClearsOnCancel() {
        var shutter = TrialShutter()
        let first = RadarPoint(x: 1.5, y: -3)
        let second = RadarPoint(x: 3, y: 1)
        XCTAssertFalse(shutter.press(at: nil))
        XCTAssertTrue(shutter.press(at: first))
        XCTAssertFalse(shutter.press(at: second))
        XCTAssertEqual(shutter.finish(), first)
        XCTAssertTrue(shutter.press(at: first))
        _ = shutter.finish() // Cancel, then ignore a late camera callback.
        XCTAssertNil(shutter.finish())
        XCTAssertTrue(shutter.press(at: second))
        XCTAssertEqual(shutter.finish(), second)
    }

    @MainActor func testPhotoAndShutterCoordinatesReachSecondPhone() async throws {
        guard let input = ProcessInfo.processInfo.environment["SPACEFIND_TEST_PAIRING"] else {
            throw XCTSkip("Supply a disposable trial service.")
        }
        let pairing = try Pairing(input)
        let recorder = try await CrewService.join(pairing)
        let finder = try await CrewService.join(pairing)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try Inventory(file: folder.appendingPathComponent("a"))
        let b = try Inventory(file: folder.appendingPathComponent("b"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let photo = try XCTUnwrap(PhotoImage.normalizedJPEG(from: jpeg))
        let point = RadarPoint(x: -4.25, y: 1.5)
        let itemID = try a.saveRadarPhoto(for: nil, label: "Trial fixture", locationNote: "North shelf",
                                          photo: photo, at: point)
        try await a.sync(using: recorder)
        try await b.sync(using: finder)
        let report = try XCTUnwrap(b.items.first(where: { $0.id == itemID })?.reports.first)
        XCTAssertEqual(report.photo, photo)
        XCTAssertEqual(report.radarPosition, point)
        XCTAssertEqual(report.locationNote, "North shelf")
        XCTAssertEqual(report.displayLocation, "North shelf")

        let original = try XCTUnwrap(b.items.first { $0.id == itemID })
        let newPoint = RadarPoint(x: 2, y: 3)
        _ = try b.saveRadarPhoto(for: original, label: original.label, locationNote: "Locker 2",
                                 photo: photo, at: newPoint)
        try await b.sync(using: finder)
        try await a.sync(using: recorder)
        let updated = try XCTUnwrap(a.search("Locker 2").first { $0.id == itemID })
        XCTAssertEqual(updated.reports.count, 1)
        XCTAssertEqual(updated.reports.first?.radarPosition, newPoint)
        XCTAssertEqual(updated.reports.first?.photo, photo)
    }
}
