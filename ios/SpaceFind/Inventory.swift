import Combine
import Foundation

struct Report: Codable, Equatable, Identifiable {
    let id: UUID
    let location: String
    let photo: Data
}

struct Item: Codable, Equatable, Identifiable {
    let id: UUID
    let label: String
    let description: String
    var reports: [Report]
}

enum ChangeKind: String, Codable, Equatable {
    case create, move, confirm
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
    func fetch() async throws -> [Item]
    func send(_ change: Change) async throws
}

enum CrewError: Error, LocalizedError {
    case staleConfirmation

    var errorDescription: String? {
        "The inventory changed. Sync, then choose from the current reports."
    }
}

private enum InventoryError: LocalizedError {
    case invalidRecord, oversizedChange

    var errorDescription: String? {
        switch self {
        case .invalidRecord: return "Add a label and location, then choose a photo no larger than 2 MiB."
        case .oversizedChange: return "The entry is too large to sync. Shorten the text or choose a smaller photo."
        }
    }
}

@MainActor
final class Inventory: ObservableObject {
    @Published private(set) var items: [Item] = []
    private let file: URL
    private var state: Store
    private var syncTask: Task<Void, Error>?

    var pendingChanges: [Change] { state.pending }

    init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            state = try JSONDecoder().decode(Store.self, from: Data(contentsOf: file))
        } else {
            state = Store(items: [], pending: [])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
        }
        items = Self.display(state)
    }

    func create(label: String, description: String, location: String, photo: Data) throws {
        guard Self.isPresent(label), Self.isPresent(location), (1...2 * 1024 * 1024).contains(photo.count) else {
            throw InventoryError.invalidRecord
        }
        let change = Change(id: UUID(), itemID: UUID(), kind: .create, label: label,
                            description: description, parentID: nil, location: location, photo: photo,
                            observedIDs: nil, chosenID: nil)
        try enqueue(change)
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

    func confirm(itemID: UUID, observedIDs: [UUID], chosenID: UUID) throws {
        guard let item = items.first(where: { $0.id == itemID }),
              Set(item.reports.map(\.id)) == Set(observedIDs),
              observedIDs.contains(chosenID),
              !state.pending.contains(where: { $0.itemID == itemID }) else {
            throw CrewError.staleConfirmation
        }
        let change = Change(id: UUID(), itemID: itemID, kind: .confirm, label: nil,
                            description: nil, parentID: nil, location: nil, photo: nil,
                            observedIDs: observedIDs, chosenID: chosenID)
        try enqueue(change)
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
                next.items = snapshot
                try commit(next)
                throw CrewError.staleConfirmation
            }
            var next = state
            next.items = Self.apply(change, to: next.items)
            next.pending.removeAll(where: { $0.id == change.id })
            try commit(next)
        }
        try Task.checkCancellation()
        let snapshot = try await service.fetch()
        guard snapshot != state.items else { return }
        var next = state
        next.items = snapshot
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
    }

    private static func isPresent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func display(_ store: Store) -> [Item] {
        store.pending.reduce(store.items) { apply($1, to: $0) }
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
        }
        return items
    }

    private struct Store: Codable {
        var items: [Item]
        var pending: [Change]
    }
}
