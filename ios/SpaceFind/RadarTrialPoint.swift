import Foundation

extension RadarPoint {
    var trialLocation: String { "spacefind-radar-v1 \(x) \(y)" }

    func trialLocation(keeping note: String) -> String {
        note.isEmpty ? trialLocation : trialLocation + "\n" + note
    }

    init?(trialLocation: String) {
        let header = trialLocation.prefix { $0 != "\n" }
        let parts = header.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "spacefind-radar-v1",
              let x = Double(parts[1]), let y = Double(parts[2]), x.isFinite, y.isFinite else {
            return nil
        }
        self.init(x: x, y: y)
    }
}

extension Report {
    var radarPosition: RadarPoint? { RadarPoint(trialLocation: location) }

    var locationNote: String {
        guard radarPosition != nil else { return location }
        guard let separator = location.firstIndex(of: "\n") else { return "" }
        return String(location[location.index(after: separator)...])
    }

    var displayLocation: String {
        let note = locationNote
        return note.isEmpty && radarPosition != nil ? "Saved radar position" : note
    }
}

extension Inventory {
    func saveRadarPhoto(for original: Item?, label: String, locationNote: String,
                        photo: Data, at point: RadarPoint) throws -> UUID {
        let location = point.trialLocation(keeping: locationNote.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let original else {
            return try create(label: label, description: "", location: location, photo: photo)
        }
        guard original.reports.count == 1, let parent = original.reports.first,
              let current = items.first(where: { $0.id == original.id }),
              current.reports.count == 1, current.reports.first?.id == parent.id else {
            throw CrewError.staleConfirmation
        }
        try move(itemID: original.id, parentID: parent.id, location: location, photo: photo)
        return original.id
    }
}
