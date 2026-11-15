import SwiftUI

struct LostItemsView: View {
    @ObservedObject var inventory: Inventory
    @State private var isReportingMissing = false

    private var missing: [LostItemReport] { inventory.lostReports.filter { $0.foundAt == nil } }
    private var found: [LostItemReport] { inventory.lostReports.filter { $0.foundAt != nil } }

    var body: some View {
        NavigationStack {
            Group {
                if inventory.lostReports.isEmpty {
                    EmptyLostItemsView { isReportingMissing = true }
                } else {
                    List {
                        if !missing.isEmpty {
                            Section("Missing") {
                                ForEach(missing) { report in
                                    reportLink(report)
                                }
                            }
                        }
                        if !found.isEmpty {
                            Section("Found") {
                                ForEach(found) { report in
                                    reportLink(report)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Lost items")
            .navigationDestination(for: UUID.self) { id in
                LostItemDetailView(inventory: inventory, reportID: id)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isReportingMissing = true
                    } label: {
                        Label("Report a missing item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isReportingMissing) {
                MissingItemEditor(inventory: inventory)
            }
        }
    }

    private func reportLink(_ report: LostItemReport) -> some View {
        NavigationLink(value: report.id) {
            LostItemRow(report: report, isPending: inventory.isPending(report.id))
        }
        .accessibilityIdentifier("lost-report-\(report.id.uuidString)")
    }
}

private struct EmptyLostItemsView: View {
    let reportMissing: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No missing items")
                .font(.headline)
            Text("Report an item so your crew knows where to start looking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Report a missing item", action: reportMissing)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LostItemRow: View {
    let report: LostItemReport
    let isPending: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(report.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(report.foundAt == nil ? "Missing" : "Found")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            LabeledContent(report.foundAt == nil ? "Last seen" : "Found at", value: report.foundAt ?? report.lastSeen)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isPending {
                Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct LostItemDetailView: View {
    @ObservedObject var inventory: Inventory
    let reportID: UUID

    @State private var isMarkingFound = false

    private var report: LostItemReport? { inventory.lostReports.first { $0.id == reportID } }

    var body: some View {
        Group {
            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(report.foundAt == nil ? "Missing" : "Found")
                            .font(.title2.weight(.semibold))

                        if let photo = report.photo {
                            PhotoThumbnail(
                                data: photo,
                                accessibilityLabel: "Photo of \(report.name)",
                                maximumPixelSize: 1200,
                                contentMode: .fit
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 250)
                        }

                        LabeledContent("Last seen", value: report.lastSeen)
                            .font(.body)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Last seen, \(report.lastSeen)")
                        if let foundAt = report.foundAt {
                            LabeledContent("Found at", value: foundAt)
                                .font(.body)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Found at, \(foundAt)")
                        }

                        if inventory.isPending(report.id) {
                            Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(report.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if report.foundAt == nil {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Mark as found") { isMarkingFound = true }
                        }
                    }
                }
            } else {
                Text("This report is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isMarkingFound) {
            FoundItemEditor(inventory: inventory, reportID: reportID)
        }
        .onChange(of: report?.foundAt) { location in
            if location != nil { isMarkingFound = false }
        }
    }
}

private struct MissingItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var inventory: Inventory

    @State private var name = ""
    @State private var lastSeen = ""
    @State private var photo: Data?
    @State private var isLoadingPhoto = false
    @State private var editorError: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastSeen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoadingPhoto
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item name", text: $name)
                        .textContentType(.name)
                        .accessibilityLabel("Item name")
                    TextField("Where was it last seen?", text: $lastSeen, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Where was it last seen?")
                }

                ItemPhotoSection(photo: $photo, isLoading: $isLoadingPhoto, required: false)
            }
            .navigationTitle("Report a missing item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-report-missing")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report missing item", action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Unable to report item", isPresented: Binding(
                get: { editorError != nil },
                set: { if !$0 { editorError = nil } }
            )) {
                Button("OK", role: .cancel) { editorError = nil }
            } message: {
                Text(editorError ?? "Please try again.")
            }
        }
    }

    private func save() {
        do {
            try inventory.reportMissing(name: name, lastSeen: lastSeen, photo: photo)
            dismiss()
        } catch {
            editorError = error.localizedDescription
        }
    }
}

private struct FoundItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var inventory: Inventory
    let reportID: UUID

    @State private var foundAt = ""
    @State private var editorError: String?
    @State private var confirmingDiscard = false

    private var canSave: Bool { !foundAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Found location") {
                    TextField("Where did you find it?", text: $foundAt, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Where did you find it?")
                }
            }
            .navigationTitle("Mark as found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if canSave {
                            confirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("cancel-mark-found")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save location", action: save)
                        .accessibilityIdentifier("mark-found-save")
                        .disabled(!canSave)
                }
            }
            .alert("Unable to mark item as found", isPresented: Binding(
                get: { editorError != nil },
                set: { if !$0 { editorError = nil } }
            )) {
                Button("OK", role: .cancel) { editorError = nil }
            } message: {
                Text(editorError ?? "Please try again.")
            }
        }
        .interactiveDismissDisabled(canSave)
        .alert("Discard the found location?", isPresented: $confirmingDiscard) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        }
    }

    private func save() {
        do {
            try inventory.markFound(reportID: reportID, foundAt: foundAt)
            dismiss()
        } catch {
            editorError = error.localizedDescription
        }
    }
}
