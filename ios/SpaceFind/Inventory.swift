import Combine
import Foundation

struct Report: Codable, Equatable, Identifiable {
    let id: UUID
    let location: String
    let photo: Data
}

struct Item: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    let description: String
    var reports: [Report]
}

struct LostItemReport: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let lastSeen: String
    let photo: Data?
    var foundAt: String?
}

struct CrewSnapshot: Decodable, Equatable {
    let items: [Item]
    let lostReports: [LostItemReport]
}

enum ChangeKind: String, Codable, Equatable {
    case create, move, confirm, rename, reportMissing, markFound
}

struct Change: Codable, Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    let kind: ChangeKind
    var label: String?
    var description: String?
    var parentID: UUID?
    var location: String?
    var photo: Data?
    var observedIDs: [UUID]?
    var chosenID: UUID?

    func requestBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try encoder.encode(self)
    }
}

protocol CrewAPI {
    func fetch() async throws -> CrewSnapshot
    func send(_ change: Change) async throws
}

enum CrewError: Error, LocalizedError {
    case staleConfirmation
    case alreadyFound(foundAt: String)

    var errorDescription: String? {
        switch self {
        case .staleConfirmation: return "The inventory changed. Sync, then choose from the current reports."
        case .alreadyFound(let foundAt): return "This report was already closed. Found at \(foundAt)."
        }
    }
}

private enum InventoryError: LocalizedError {
    case invalidRecord, invalidLabel, unknownItem, invalidLostReport, invalidFoundLocation, missingLostReport, oversizedChange

    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "Add a label and location, then choose a photo no larger than 2 MiB."
        case .invalidLostReport: return "Add an item name and last-seen location; a JPEG photo is optional (up to 2 MiB)."
        case .invalidFoundLocation: return "Add a found-at location."
        case .missingLostReport: return "This lost-item report is no longer available."
        case .oversizedChange: return "The change is too large to sync. Shorten the text or choose a smaller photo."
        case .invalidLabel: return "Add a label."
        case .unknownItem: return "This item is no longer in the inventory."
        }
    }
}

@MainActor
final class Inventory: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var lostReports: [LostItemReport] = []
    @Published private(set) var closureNotices: [UUID: String] = [:]
    private let file: URL
    private var state: Store
    private var syncTask: Task<Void, Error>?

    var pendingChanges: [Change] { state.pending }

    init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            state = try JSONDecoder().decode(Store.self, from: Data(contentsOf: file))
        } else {
            state = Store(items: [], pending: [], lostReports: [], closureNotices: [:])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
        }
        items = Self.display(state)
        lostReports = Self.displayLostReports(state)
        closureNotices = state.closureNotices
    }

    @discardableResult
    func create(label: String, description: String, location: String, photo: Data) throws -> UUID {
        guard Self.isPresent(label), Self.isPresent(location), (1...2 * 1024 * 1024).contains(photo.count) else {
            throw InventoryError.invalidRecord
        }
        let change = Change(id: UUID(), itemID: UUID(), kind: .create, label: label,
                            description: description, parentID: nil, location: location, photo: photo,
                            observedIDs: nil, chosenID: nil)
        try enqueue(change)
        return change.itemID
    }

    func move(itemID: UUID, parentID: UUID, location: String, photo: Data) throws {
        guard Self.isPresent(location), (1...2 * 1024 * 1024).contains(photo.count) else {
            throw InventoryError.invalidRecord
        }
        guard let item = items.first(where: { $0.id == itemID }),
              item.reports.contains(where: { $0.id == parentID }),
              !state.pending.contains(where: { $0.itemID == itemID && $0.kind == .confirm }) else {
            throw CrewError.staleConfirmation
        }
        let change = Change(id: UUID(), itemID: itemID, kind: .move, label: nil,
                            description: nil, parentID: parentID, location: location, photo: photo,
                            observedIDs: nil, chosenID: nil)
        try enqueue(change)
    }

    func rename(itemID: UUID, label: String) throws {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw InventoryError.invalidLabel }
        guard let item = items.first(where: { $0.id == itemID }) else { throw InventoryError.unknownItem }
        guard item.label.trimmingCharacters(in: .whitespacesAndNewlines) != label else { return }
        try enqueue(Change(id: UUID(), itemID: itemID, kind: .rename, label: label))
    }

    func confirm(itemID: UUID, observedIDs: [UUID], chosenID: UUID) throws {
        guard let item = items.first(where: { $0.id == itemID }),
              Set(item.reports.map(\.id)) == Set(observedIDs),
              observedIDs.contains(chosenID),
              !state.pending.contains(where: { $0.itemID == itemID && $0.kind != .rename }) else {
            throw CrewError.staleConfirmation
        }
        let change = Change(id: UUID(), itemID: itemID, kind: .confirm, label: nil,
                            description: nil, parentID: nil, location: nil, photo: nil,
                            observedIDs: observedIDs, chosenID: chosenID)
        try enqueue(change)
    }

    @discardableResult
    func reportMissing(name: String, lastSeen: String, photo: Data?) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSeen = lastSeen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !lastSeen.isEmpty,
              photo.map(Self.isValidJPEG) ?? true else { throw InventoryError.invalidLostReport }
        let reportID = UUID()
        let change = Change(id: UUID(), itemID: reportID, kind: .reportMissing, label: name,
                            description: nil, parentID: nil, location: lastSeen, photo: photo,
                            observedIDs: nil, chosenID: nil)
        try enqueue(change)
        return reportID
    }

    func markFound(reportID: UUID, foundAt: String) throws {
        let foundAt = foundAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foundAt.isEmpty else { throw InventoryError.invalidFoundLocation }
        guard let report = lostReports.first(where: { $0.id == reportID }) else {
            throw InventoryError.missingLostReport
        }
        if let acceptedLocation = report.foundAt {
            throw CrewError.alreadyFound(foundAt: acceptedLocation)
        }
        let change = Change(id: UUID(), itemID: reportID, kind: .markFound, label: nil,
                            description: nil, parentID: nil, location: foundAt, photo: nil,
                            observedIDs: nil, chosenID: nil)
        try enqueue(change)
    }

    func dismissClosureNotice(reportID: UUID) {
        guard state.closureNotices[reportID] != nil else { return }
        var next = state
        next.closureNotices.removeValue(forKey: reportID)
        try? commit(next)
    }

    func search(_ query: String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.label.localizedCaseInsensitiveContains(query)
                || item.description.localizedCaseInsensitiveContains(query)
                || item.reports.contains(where: { $0.location.localizedCaseInsensitiveContains(query) })
        }
    }

    func isPending(_ id: UUID) -> Bool {
        state.pending.contains(where: { $0.itemID == id })
    }

    func sync(using service: any CrewAPI) async throws {
        if let syncTask {
            try await syncTask.value
            return
        }
        let task = Task { @MainActor in try await self.performSync(using: service) }
        syncTask = task
        defer { syncTask = nil }
        try await task.value
    }

    private func performSync(using service: any CrewAPI) async throws {
        while let change = state.pending.first {
            try Task.checkCancellation()
            do {
                try await service.send(change)
            } catch CrewError.staleConfirmation where change.kind == .confirm {
                let snapshot = try await service.fetch()
                var next = state
                next.pending.removeAll(where: { $0.id == change.id })
                next.items = snapshot.items
                next.lostReports = snapshot.lostReports
                try commit(next)
                throw CrewError.staleConfirmation
            } catch CrewError.alreadyFound(let foundAt) where change.kind == .markFound {
                var next = state
                guard let index = next.lostReports.firstIndex(where: { $0.id == change.itemID }) else {
                    throw InventoryError.missingLostReport
                }
                next.lostReports[index].foundAt = foundAt
                next.pending.removeAll(where: { $0.id == change.id })
                next.closureNotices[change.itemID] = foundAt
                try commit(next)
                continue
            }
            var next = state
            next.items = Self.apply(change, to: next.items)
            next.lostReports = Self.apply(change, to: next.lostReports)
            next.pending.removeAll(where: { $0.id == change.id })
            try commit(next)
        }
        try Task.checkCancellation()
        let snapshot = try await service.fetch()
        guard snapshot.items != state.items || snapshot.lostReports != state.lostReports else { return }
        var next = state
        next.items = snapshot.items
        next.lostReports = snapshot.lostReports
        try commit(next)
    }

    private func enqueue(_ change: Change) throws {
        guard try change.requestBody().count <= 3 * 1024 * 1024 else {
            throw InventoryError.oversizedChange
        }
        var next = state
        next.pending.append(change)
        try commit(next)
    }

    private func commit(_ next: Store) throws {
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        state = next
        items = Self.display(next)
        lostReports = Self.displayLostReports(next)
        closureNotices = next.closureNotices
    }

    private static func isPresent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidJPEG(_ photo: Data) -> Bool {
        (1...2 * 1024 * 1024).contains(photo.count)
            && photo.starts(with: [0xff, 0xd8])
            && photo.suffix(2) == Data([0xff, 0xd9])
    }

    private static func display(_ store: Store) -> [Item] {
        store.pending.reduce(store.items) { apply($1, to: $0) }
    }

    private static func displayLostReports(_ store: Store) -> [LostItemReport] {
        store.pending.reduce(store.lostReports) { apply($1, to: $0) }
    }

    private static func apply(_ change: Change, to source: [Item]) -> [Item] {
        var items = source
        switch change.kind {
        case .create:
            guard let label = change.label, let location = change.location, let photo = change.photo else { return items }
            let item = Item(id: change.itemID, label: label, description: change.description ?? "",
                            reports: [Report(id: change.id, location: location, photo: photo)])
            if let index = items.firstIndex(where: { $0.id == change.itemID }) { items[index] = item }
            else { items.append(item) }
        case .move:
            guard let index = items.firstIndex(where: { $0.id == change.itemID }),
                  let location = change.location, let photo = change.photo else { return items }
            items[index].reports.removeAll(where: { $0.id == change.parentID || $0.id == change.id })
            items[index].reports.append(Report(id: change.id, location: location, photo: photo))
        case .confirm:
            guard let index = items.firstIndex(where: { $0.id == change.itemID }),
                  let observedIDs = change.observedIDs, let chosenID = change.chosenID,
                  Set(items[index].reports.map(\.id)) == Set(observedIDs),
                  let chosen = items[index].reports.first(where: { $0.id == chosenID }) else { return items }
            items[index].reports = [chosen]
        case .reportMissing, .markFound:
            break
        case .rename:
            guard let index = items.firstIndex(where: { $0.id == change.itemID }),
                  let label = change.label else { return items }
            items[index].label = label
        }
        return items
    }

    private static func apply(_ change: Change, to source: [LostItemReport]) -> [LostItemReport] {
        var reports = source
        switch change.kind {
        case .reportMissing:
            guard let name = change.label, let lastSeen = change.location else { return reports }
            let foundAt = reports.first(where: { $0.id == change.itemID })?.foundAt
            let report = LostItemReport(id: change.itemID, name: name, lastSeen: lastSeen,
                                        photo: change.photo, foundAt: foundAt)
            if let index = reports.firstIndex(where: { $0.id == change.itemID }) { reports[index] = report }
            else { reports.append(report) }
        case .markFound:
            guard let index = reports.firstIndex(where: { $0.id == change.itemID }),
                  let foundAt = change.location else { return reports }
            reports[index].foundAt = foundAt
        case .create, .move, .confirm, .rename:
            break
        }
        return reports
    }

    private struct Store: Codable {
        var items: [Item]
        var pending: [Change]
        var lostReports: [LostItemReport]
        var closureNotices: [UUID: String]

        private enum CodingKeys: String, CodingKey {
            case items, pending, lostReports, closureNotices
        }

        init(items: [Item], pending: [Change], lostReports: [LostItemReport], closureNotices: [UUID: String]) {
            self.items = items
            self.pending = pending
            self.lostReports = lostReports
            self.closureNotices = closureNotices
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([Item].self, forKey: .items)
            pending = try container.decode([Change].self, forKey: .pending)
            lostReports = try container.contains(.lostReports)
                ? container.decode([LostItemReport].self, forKey: .lostReports) : []
            closureNotices = try container.contains(.closureNotices)
                ? container.decode([UUID: String].self, forKey: .closureNotices) : [:]
        }
    }
}
