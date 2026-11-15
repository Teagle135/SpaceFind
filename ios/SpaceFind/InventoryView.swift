import SwiftUI

struct InventoryView: View {
    @ObservedObject var inventory: Inventory
    @State private var query = ""
    @State private var isCreatingItem = false

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let results = inventory.search(query).filter { !$0.isRadarTarget }

        NavigationStack {
            List {
                inventoryHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(CrewTheme.surface)

                HStack {
                    Text(hasQuery ? "Results" : "All items")
                    Spacer()
                    Text("\(results.count)")
                        .accessibilityLabel(results.count == 1 ? "1 item" : "\(results.count) items")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CrewTheme.ink)
                .padding(.bottom, 8)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(CrewTheme.surface)

                if results.isEmpty {
                    EmptyInventoryView(hasQuery: hasQuery)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(CrewTheme.surface)
                } else {
                    ForEach(results, id: \.id) { item in
                        NavigationLink {
                            ItemDetailView(inventory: inventory, itemID: item.id)
                        } label: {
                            InventoryRow(item: item, isPending: inventory.isPending(item.id))
                        }
                        .accessibilityIdentifier("item-\(item.id.uuidString)")
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(CrewTheme.surface)
                        .listRowSeparatorTint(CrewTheme.divider)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(CrewTheme.surface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Label, description, or location")
            .sheet(isPresented: $isCreatingItem) {
                ItemEditor(inventory: inventory, original: nil)
            }
        }
    }

    private var inventoryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            CrewWordmark()

            HStack {
                Text("Inventory")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(CrewTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    isCreatingItem = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CrewTheme.surface)
                        .frame(width: 36, height: 36)
                        .background(CrewTheme.accent, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Add item")
                .accessibilityHint("Create an inventory item with a photo and location")
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InventoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: Item
    let isPending: Bool

    private var displayedReport: Report? { item.reports.count == 1 ? item.reports.first : nil }
    private var hasConflict: Bool { item.reports.count > 1 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    thumbnail
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    thumbnail
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var thumbnail: some View {
        PhotoThumbnail(
            data: displayedReport?.photo,
            accessibilityLabel: "Photo of \(item.label)",
            maximumPixelSize: 420,
            cornerRadius: 8
        )
        .frame(width: 100, height: 72)
        .accessibilityHidden(displayedReport == nil)
        .accessibilitySortPriority(-1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.label)
                .font(.headline.weight(.semibold))
                .foregroundStyle(CrewTheme.ink)

            if hasConflict {
                Label("Needs confirmation", systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(CrewTheme.ink)
            } else {
                Text(displayedReport?.location ?? "Location not recorded")
                    .font(.body)
                    .foregroundStyle(CrewTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isPending {
                Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
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
                .foregroundStyle(CrewTheme.ink)
            Text(hasQuery ? "Try a label, description, or location." : "Add an item with a photo and its location.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
