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
                InventoryView(inventory: inventory)
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
                                    ? "Laptop unreachable. Showing the inventory saved on this iPhone."
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


private enum JoinIssue: LocalizedError {
    case pendingInventory
    var errorDescription: String? {
        "This phone has changes waiting for the original laptop. Use its pairing string to finish syncing."
    }
}
