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
                            VStack(alignment: .leading, spacing: 2) {
                                Label(message, systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Update connection") { reconnecting = true }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CrewTheme.accent)
                                    .frame(minHeight: 44)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(CrewTheme.ink)
                            .background(CrewTheme.surface)
                            .overlay(alignment: .top) { Rectangle().fill(CrewTheme.divider).frame(height: 1) }
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
                        Button("Try again") { restore() }.buttonStyle(.borderedProminent)
                    } else { ProgressView("Opening inventory…") }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CrewTheme.surface)
            }
        }
        .sheet(isPresented: $reconnecting) { pairingForm }
        .task { if !ready && inventory == nil { restore() } }
        .tint(CrewTheme.accent)
    }

    private var pairingForm: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pairing string").font(.subheadline.weight(.semibold))
                        SecureField("Paste pairing string", text: $pairing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Pairing string")
                            .accessibilityIdentifier("pairing")
                    }
                    Text("Connect to the laptop’s Wi-Fi, then paste the pairing string from your crew lead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let joinError {
                        Label(joinError, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                    }
                    Button {
                        joining = true
                        Task { await join() }
                    } label: {
                        Text(joining ? "Joining…" : "Join inventory")
                            .font(.headline)
                            .foregroundStyle(CrewTheme.surface)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(joining || pairing.isEmpty)
                } header: {
                    Text("Crew invite")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CrewTheme.surface)
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
