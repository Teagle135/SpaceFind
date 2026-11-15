import XCTest
@testable import SpaceFind

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
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addHeading(timestamp: 3, relativeHeading: 0)
        path.addHeading(timestamp: 3.001, relativeHeading: .pi / 2)
        path.addHeading(timestamp: 7, relativeHeading: .pi / 2)

        path.addDistanceSample(total: 7, timestamp: 7)

        XCTAssertEqual(path.position.x, 4, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 3, accuracy: 0.01)
    }

    func testStationaryQuarterTurnChangesTheFollowingLegHeading() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 0, timestamp: 1)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 0))

        path.addHeading(timestamp: 1.01, relativeHeading: .pi / 2)
        path.addDistanceSample(total: 1, timestamp: 2)

        XCTAssertEqual(path.position.x, 1, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 0, accuracy: 0.01)
    }

    func testDuplicateDistanceSampleDoesNotAddDistanceTwice() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 3, timestamp: 3)
        path.addDistanceSample(total: 3, timestamp: 3)
        path.addDistanceSample(total: 3, timestamp: 4)

        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 3))
    }

    func testResetAfterInterruptedTrackingStartsAtNewOrigin() {
        var path = RadarPathIntegrator(startTime: 0)
        path.addHeading(timestamp: 0.01, relativeHeading: 0)
        path.addDistanceSample(total: 2, timestamp: 2)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 2))

        path.reset(startTime: 10)
        XCTAssertEqual(path.position, RadarPoint(x: 0, y: 0))
        XCTAssertFalse(path.hasDistance)
        path.addHeading(timestamp: 10.01, relativeHeading: .pi / 2)
        path.addDistanceSample(total: 2, timestamp: 12)

        XCTAssertEqual(path.position.x, 2, accuracy: 0.01)
        XCTAssertEqual(path.position.y, 0, accuracy: 0.01)
    }

    func testRadarPointEncodesMetreCoordinatesAsCodableValues() throws {
        let point = RadarPoint(x: 4, y: 3)

        XCTAssertEqual(try JSONDecoder().decode(RadarPoint.self, from: JSONEncoder().encode(point)), point)
    }
}
