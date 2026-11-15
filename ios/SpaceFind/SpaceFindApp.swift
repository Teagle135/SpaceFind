import SwiftUI

@main
struct SpaceFindApp: App {
    var body: some Scene { WindowGroup { CrewRoot() } }
}

private struct CrewRoot: View {
    @Environment(\.scenePhase) private var phase
    @State private var service: CrewService?
    @State private var inventory: Inventory?
    @State private var pairing = ""
    @State private var message: String?
    @State private var ready = false
    @State private var joining = false
    @State private var reconnecting = false
    @State private var joinError: String?

    var body: some View {
        Group {
            if let inventory, let service {
                CrewWorkspace(inventory: inventory)
                    .safeAreaInset(edge: .bottom) {
                        if let message {
                            VStack(spacing: 4) {
                                Text(message).font(.footnote)
                                Button("Update connection") { reconnecting = true }
                            }
                            .frame(maxWidth: .infinity).padding(8).background(.thinMaterial)
                        }
                    }
                    .task(id: phase) {
                        guard phase == .active else { return }
                        while !Task.isCancelled {
                            do {
                                try await inventory.sync(using: service)
                                message = nil
                            } catch {
                                if Task.isCancelled { return }
                                message = (error as? URLError) != nil
                                    ? "Laptop unreachable. Showing items and lost reports saved on this iPhone."
                                    : error.localizedDescription
                            }
                            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                        }
                    }
                    .id(ObjectIdentifier(service))
            } else if ready {
                pairingForm
            } else {
                VStack(spacing: 12) {
                    if let message {
                        Text(message)
                        Button("Try again") { restore() }
                    } else { ProgressView("Opening inventory…") }
                }
                .padding()
            }
        }
        .sheet(isPresented: $reconnecting) { pairingForm }
        .task { if !ready && inventory == nil { restore() } }
    }

    private var pairingForm: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Pairing string", text: $pairing).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityIdentifier("pairing")
                    Button(joining ? "Joining…" : "Join inventory") {
                        joining = true
                        Task { await join() }
                    }
                    .disabled(joining || pairing.isEmpty)
                } header: {
                    Text("Crew invite")
                } footer: {
                    Text("Connect to the laptop’s Wi-Fi, then paste the pairing string from your crew lead.")
                }
                if let joinError { Text(joinError).foregroundStyle(.secondary) }
            }
            .navigationTitle("SpaceFind")
        }
    }

    @MainActor private func restore() {
        do {
            if let saved = try CrewCredentials.load() { try open(CrewService(saved)) }
            ready = true
            message = nil
        } catch { message = error.localizedDescription }
    }

    @MainActor private func open(_ newService: CrewService) throws {
        let storage = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let file = storage.appendingPathComponent(newService.credentials.fingerprint + ".json")
        let store: Inventory
        if let inventory, service?.credentials.fingerprint == newService.credentials.fingerprint {
            store = inventory
        } else {
            if let inventory, !inventory.pendingChanges.isEmpty {
                throw JoinIssue.pendingInventory
            }
            store = try Inventory(file: file)
        }
        try newService.credentials.save()
        inventory = store
        service = newService
    }

    @MainActor private func join() async {
        defer { joining = false }
        do {
            let newService = try await CrewService.join(Pairing(pairing))
            try open(newService)
            pairing = ""
            reconnecting = false
            joinError = nil
            message = nil
        } catch { joinError = error.localizedDescription }
    }
}

private struct CrewWorkspace: View {
    @ObservedObject var inventory: Inventory

    private var activeNotice: (id: UUID, name: String, location: String)? {
        guard let id = inventory.closureNotices.keys.sorted(by: { $0.uuidString < $1.uuidString }).first,
              let location = inventory.closureNotices[id] else { return nil }
        let name = inventory.lostReports.first(where: { $0.id == id })?.name ?? "Lost item"
        return (id, name, location)
    }

    var body: some View {
        TabView {
            InventoryView(inventory: inventory)
                .tabItem { Label("Inventory", systemImage: "shippingbox") }

            LostItemsView(inventory: inventory)
                .tabItem { Label("Lost items", systemImage: "magnifyingglass") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let activeNotice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(activeNotice.name) was already marked found at \(activeNotice.location).")
                        .font(.footnote)
                        .accessibilityIdentifier("closure-notice")
                    Button("OK") {
                        inventory.dismissClosureNotice(reportID: activeNotice.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            }
        }
    }
}


private enum JoinIssue: LocalizedError {
    case pendingInventory
    var errorDescription: String? {
        "This phone has changes waiting for the original laptop. Use its pairing string to finish syncing."
    }
}
