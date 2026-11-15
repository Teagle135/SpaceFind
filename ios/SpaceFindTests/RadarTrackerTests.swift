import XCTest
import UIKit
@testable import SpaceFind

@MainActor
final class RadarTrackerTests: XCTestCase {
    func testThreeMetresForwardThenFourMetresRight() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addHeading(timestamp: 3, relativeHeading: 0)
        path.addDistanceSample(total: 3, timestamp: 3)
        path.addHeading(timestamp: 3.001, relativeHeading: .pi / 2)
        path.addHeading(timestamp: 7, relativeHeading: .pi / 2)
        path.addDistanceSample(total: 7, timestamp: 7)

        XCTAssertEqual(path.position.x, 4, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 3, accuracy: 0.01)
    }

    func testDelayedDistanceSampleUsesHeadingHistoryAcrossTurn() {
        var inOrder = RadarPathIntegrator(startTime: 0)
        inOrder.addHeading(timestamp: 0.01, relativeHeading: 0)
        inOrder.addHeading(timestamp: 3, relativeHeading: 0)
        inOrder.addHeading(timestamp: 3.001, relativeHeading: .pi / 2)
        inOrder.addHeading(timestamp: 7, relativeHeading: .pi / 2)
        inOrder.addDistanceSample(total: 7, timestamp: 7)

        var delayed = RadarPathIntegrator(startTime: 0)
        delayed.addHeading(timestamp: 0.01, relativeHeading: 0)
        delayed.addHeading(timestamp: 3, relativeHeading: 0)
        delayed.addDistanceSample(total: 7, timestamp: 7)
        XCTAssertEqual(delayed.position, RadarPoint(x: 0, y: 0))

        delayed.addHeading(timestamp: 3.001, relativeHeading: .pi / 2)
        XCTAssertEqual(delayed.position, RadarPoint(x: 0, y: 0))
        delayed.addHeading(timestamp: 7, relativeHeading: .pi / 2)

        XCTAssertEqual(delayed.position, inOrder.position)
        XCTAssertEqual(delayed.position.x, 4, accuracy: 0.01)
        XCTAssertEqual(delayed.position.y, 3, accuracy: 0.01)
    }

    func testStationaryQuarterTurnChangesTheFollowingLegHeading() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 0, timestamp: 1)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 0))

        path.addHeading(timestamp: 1.01, relativeHeading: .pi / 2)
        path.addDistanceSample(total: 1, timestamp: 2)
        path.addHeading(timestamp: 2, relativeHeading: .pi / 2)

        XCTAssertEqual(path.position.x, 1, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 0, accuracy: 0.01)
    }

    func testDuplicateDistanceSampleDoesNotAddDistanceTwice() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 3, timestamp: 3)
        path.addDistanceSample(total: 3, timestamp: 3)
        path.addDistanceSample(total: 3, timestamp: 4)
        path.addHeading(timestamp: 4, relativeHeading: 0)

        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 3))
    }

    func testResetAfterInterruptedTrackingStartsAtNewOrigin() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 2, timestamp: 2)
        path.addHeading(timestamp: 2, relativeHeading: 0)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 2))
        path.addDistanceSample(total: 3, timestamp: 3)

        path.reset(startTime: 10)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 0))
        XCTAssertFalse(path.hasDistance)
        path.addHeading(timestamp: 10.01, relativeHeading: .pi / 2)
        path.addDistanceSample(total: 2, timestamp: 12)
        path.addHeading(timestamp: 12, relativeHeading: .pi / 2)

        XCTAssertEqual(path.position.x, 2, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 0, accuracy: 0.01)
    }

    func testRadarPointEncodesMetreCoordinatesAsCodableValues() throws {
        let point = RadarPoint(x: 4, y: 3)

        XCTAssertEqual(try JSONDecoder().decode(RadarPoint.self, from: JSONEncoder().encode(point)), point)
    }

    func testBackgroundNotificationWhileStoppedKeepsStoppedStatus() async throws {
        let tracker = RadarTracker()
        tracker.stop()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(tracker.status, "Stopped")
    }
}
