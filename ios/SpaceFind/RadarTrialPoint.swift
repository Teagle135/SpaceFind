import Foundation

extension RadarPoint {
    var trialLocation: String { "spacefind-radar-v1 \(x) \(y)" }

    init?(trialLocation: String) {
        let parts = trialLocation.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "spacefind-radar-v1",
              let x = Double(parts[1]), let y = Double(parts[2]), x.isFinite, y.isFinite else {
            return nil
        }
        self.init(x: x, y: y)
    }
}

extension Item {
    var isRadarTarget: Bool {
        reports.contains { RadarPoint(trialLocation: $0.location) != nil }
    }
}
