import UIKit
import XCTest
@testable import SpaceFind

final class RadarTrialTests: XCTestCase {
    func testLocationDecodesOnlyFiniteVersionedPairs() {
        let point = RadarPoint(x: -2.125, y: 3.5)
        XCTAssertEqual(RadarPoint(trialLocation: point.trialLocation), point)
        for input in ["blue pouch", "spacefind-radar-v1 1", "spacefind-radar-v2 1 2",
                      "spacefind-radar-v1 nan 1", "spacefind-radar-v1 1 inf",
                      "spacefind-radar-v1 1 2 3"] {
            XCTAssertNil(RadarPoint(trialLocation: input), input)
        }
    }

    func testAnyRadarReportKeepsItsPhotoOutOfInventoryEvenDuringConflict() {
        let ordinary = Report(id: UUID(), location: "Locker 2", photo: Data([1]))
        let radar = Report(id: UUID(), location: RadarPoint(x: 2, y: -3).trialLocation, photo: Data([2]))
        var item = Item(id: UUID(), label: "Wrench", description: "", reports: [ordinary])
        XCTAssertFalse(item.isRadarTarget)
        item.reports.append(radar)
        XCTAssertTrue(item.isRadarTarget)
        item.reports = [radar]
        XCTAssertTrue(item.isRadarTarget)
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
        let itemID = try a.create(label: "Trial fixture", description: "", location: point.trialLocation, photo: photo)
        try await a.sync(using: recorder)
        try await b.sync(using: finder)
        let report = try XCTUnwrap(b.items.first(where: { $0.id == itemID })?.reports.first)
        XCTAssertEqual(report.photo, photo)
        XCTAssertEqual(RadarPoint(trialLocation: report.location), point)
    }
}
