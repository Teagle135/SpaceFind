import Combine
import CoreMotion
import Foundation
import UIKit

struct RadarPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct RadarPathIntegrator {
    private struct Heading {
        var time: TimeInterval
        var radians: Double
    }

    private var headings: [Heading] = []
    private var lastDistance = (total: 0.0, time: 0.0)
    private(set) var position = RadarPoint(x: 0, y: 0)
    private(set) var hasDistance = false

    init(startTime: TimeInterval = 0) {
        lastDistance.time = startTime
    }

    mutating func reset(startTime: TimeInterval) {
        headings.removeAll(keepingCapacity: true)
        lastDistance = (0, startTime)
        position = RadarPoint(x: 0, y: 0)
        hasDistance = false
    }

    mutating func addHeading(timestamp: TimeInterval, relativeHeading: Double) {
        guard timestamp.isFinite, relativeHeading.isFinite, timestamp > lastDistance.time else { return }
        let sample = Heading(time: timestamp, radians: Self.wrap(relativeHeading))
        if let last = headings.last, timestamp < last.time {
            return
        } else if headings.last?.time == timestamp {
            headings[headings.count - 1] = sample
        } else {
            headings.append(sample)
        }
    }

    mutating func addDistanceSample(total: Double, timestamp: TimeInterval) {
        guard total.isFinite, total >= 0, timestamp.isFinite, timestamp > lastDistance.time else { return }

        if total < lastDistance.total {
            lastDistance = (total, timestamp)
            return
        }

        let increment = total - lastDistance.total
        if increment > 0, !headings.isEmpty {
            integrate(increment, from: lastDistance.time, to: timestamp)
            hasDistance = true
        }
        lastDistance = (total, timestamp)
        retainHeadingBoundary(at: timestamp)
    }

    private mutating func integrate(_ distance: Double, from start: TimeInterval, to end: TimeInterval) {
        guard end > start else { return }
        let duration = end - start
        var heading = headings[0].radians
        var index = 0
        while index < headings.count, headings[index].time <= start {
            heading = headings[index].radians
            index += 1
        }

        var cursor = start
        while index < headings.count, headings[index].time <= end {
            let sample = headings[index]
            if sample.time > cursor {
                let meanHeading = heading + Self.shortestDelta(from: heading, to: sample.radians) / 2
                move(distance * (sample.time - cursor) / duration, heading: meanHeading)
                cursor = sample.time
            }
            heading = sample.radians
            index += 1
        }
        if cursor < end { move(distance * (end - cursor) / duration, heading: heading) }
    }

    private mutating func move(_ distance: Double, heading: Double) {
        position.x += distance * sin(heading)
        position.y += distance * cos(heading)
    }

    private mutating func retainHeadingBoundary(at timestamp: TimeInterval) {
        guard let first = headings.first else { return }
        var boundary = first.radians
        var index = 0
        while index < headings.count, headings[index].time <= timestamp {
            boundary = headings[index].radians
            index += 1
        }
        headings = [Heading(time: timestamp, radians: boundary)] + headings.dropFirst(index)
    }

    private static func wrap(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }

    private static func shortestDelta(from: Double, to: Double) -> Double {
        wrap(to - from)
    }
}

@MainActor
final class RadarTracker: ObservableObject {
    @Published private(set) var status = "Stopped"
    @Published private(set) var position: RadarPoint?

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "SpaceFind.RadarMotion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var authorizationTask: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    private var generation = 0
    private var active = false
    private var pedometerAuthorized = false
    private var referenceYaw: Double?
    private var dateToUptimeOffset = 0.0
    private var integrator = RadarPathIntegrator()

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.markUnavailable("Tracking was interrupted because the app left the foreground.")
            }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    func start() {
        stopSensors()
        generation += 1
        let run = generation
        active = true
        pedometerAuthorized = false
        referenceYaw = nil
        position = nil

        guard motionManager.isDeviceMotionAvailable, CMPedometer.isDistanceAvailable() else {
            markUnavailable("Motion tracking is unavailable on this iPhone.")
            return
        }

        let authorization = CMPedometer.authorizationStatus()
        guard authorization != .denied, authorization != .restricted else {
            markUnavailable("Motion & Fitness permission is unavailable. Enable it in Settings to track.")
            return
        }

        let wallStart = Date()
        let uptimeStart = ProcessInfo.processInfo.systemUptime
        dateToUptimeOffset = uptimeStart - wallStart.timeIntervalSince1970
        integrator.reset(startTime: uptimeStart)
        status = authorization == .notDetermined
            ? "Waiting for Motion & Fitness permission…"
            : "Waiting for a heading reference…"

        pedometer.startUpdates(from: wallStart) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                if let error {
                    self.markUnavailable("Motion tracking was interrupted: \(error.localizedDescription)")
                    return
                }
                guard let data else { return }
                guard self.refreshAuthorization() else { return }
                guard let distance = data.distance?.doubleValue else {
                    self.markUnavailable("Walking distance is unavailable from Motion & Fitness.")
                    return
                }
                let timestamp = data.endDate.timeIntervalSince1970 + self.dateToUptimeOffset
                self.integrator.addDistanceSample(total: distance, timestamp: timestamp)
                self.publishState()
            }
        }

        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xArbitraryCorrectedZVertical)
            ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: frame, to: motionQueue) { [weak self] motion, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run else { return }
                if let error {
                    self.markUnavailable("Motion tracking was interrupted: \(error.localizedDescription)")
                    return
                }
                guard let motion else { return }
                self.recordYaw(motion.attitude.yaw, timestamp: motion.timestamp)
            }
        }

        if authorization == .authorized {
            pedometerAuthorized = true
        } else {
            waitForAuthorization(generation: run)
        }
    }

    func stop() {
        generation += 1
        active = false
        stopSensors()
        integrator.reset(startTime: ProcessInfo.processInfo.systemUptime)
        referenceYaw = nil
        pedometerAuthorized = false
        position = nil
        status = "Stopped"
    }

    private func stopSensors() {
        authorizationTask?.cancel()
        authorizationTask = nil
        pedometer.stopUpdates()
        motionManager.stopDeviceMotionUpdates()
    }

    private func waitForAuthorization(generation run: Int) {
        authorizationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.generation == run, self.active else { return }
                switch CMPedometer.authorizationStatus() {
                case .authorized:
                    self.pedometerAuthorized = true
                    self.publishState()
                    return
                case .denied, .restricted:
                    self.markUnavailable("Motion & Fitness permission is unavailable. Enable it in Settings to track.")
                    return
                case .notDetermined:
                    break
                @unknown default:
                    self.markUnavailable("Motion & Fitness permission could not be checked.")
                    return
                }
            }
        }
    }

    @discardableResult
    private func refreshAuthorization() -> Bool {
        switch CMPedometer.authorizationStatus() {
        case .authorized:
            pedometerAuthorized = true
            return true
        case .denied, .restricted:
            markUnavailable("Motion & Fitness permission is unavailable. Enable it in Settings to track.")
            return false
        case .notDetermined:
            return false
        @unknown default:
            markUnavailable("Motion & Fitness permission could not be checked.")
            return false
        }
    }

    private func recordYaw(_ yaw: Double, timestamp: TimeInterval) {
        guard active, yaw.isFinite, timestamp.isFinite else { return }
        if referenceYaw == nil { referenceYaw = yaw }
        guard let referenceYaw else { return }
        // Core Motion yaw increases for a left turn with the screen up; invert it so right is +x.
        let relativeHeading = -atan2(sin(yaw - referenceYaw), cos(yaw - referenceYaw))
        integrator.addHeading(timestamp: timestamp, relativeHeading: relativeHeading)
        publishState()
    }

    private func publishState() {
        guard active else { return }
        guard pedometerAuthorized else {
            if status != "Waiting for Motion & Fitness permission…" {
                status = "Waiting for Motion & Fitness permission…"
            }
            return
        }
        guard referenceYaw != nil else {
            if status != "Waiting for a heading reference…" { status = "Waiting for a heading reference…" }
            return
        }
        if position != integrator.position { position = integrator.position }
        let nextStatus = integrator.hasDistance ? "Tracking" : "Ready — waiting for first steps"
        if status != nextStatus { status = nextStatus }
    }

    private func markUnavailable(_ reason: String) {
        generation += 1
        active = false
        stopSensors()
        integrator.reset(startTime: ProcessInfo.processInfo.systemUptime)
        referenceYaw = nil
        pedometerAuthorized = false
        position = nil
        status = reason
    }
}
