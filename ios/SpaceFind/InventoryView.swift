import SwiftUI

struct InventoryView: View {
    @ObservedObject var inventory: Inventory
    @State private var query = ""
    @State private var isCreatingItem = false

    private var results: [Item] { inventory.search(query) }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    EmptyInventoryView(hasQuery: !query.isEmpty)
                } else {
                    List(results, id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(inventory: inventory, itemID: item.id)
                        } label: {
                            InventoryRow(item: item, isPending: inventory.isPending(item.id))
                        }
                        .accessibilityIdentifier("item-\(item.id.uuidString)")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $query, prompt: "Label, description, or location")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isCreatingItem = true
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .accessibilityHint("Create an inventory item with a photo and location")
                }
            }
            .sheet(isPresented: $isCreatingItem) {
                ItemEditor(inventory: inventory, original: nil)
            }
        }
    }
}

private struct InventoryRow: View {
    let item: Item
    let isPending: Bool

    private var displayedReport: Report? { item.reports.first }

    var body: some View {
        HStack(spacing: 14) {
            PhotoThumbnail(
                data: displayedReport?.photo,
                accessibilityLabel: "Photo of \(item.label)",
                maximumPixelSize: 420
            )
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.label)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(displayedReport?.location ?? "Location not recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if item.reports.count > 1 {
                    Label("Needs confirmation", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                if isPending {
                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyInventoryView: View {
    let hasQuery: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasQuery ? "magnifyingglass" : "shippingbox")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(hasQuery ? "No matching items" : "Your inventory is empty")
                .font(.headline)
            Text(hasQuery ? "Try a label, description, or location." : "Add an item with a photo and its location.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
