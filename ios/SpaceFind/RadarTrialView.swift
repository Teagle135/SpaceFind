import AVFoundation
import SwiftUI
import UIKit

struct RadarTrialView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CrewWordmark()

                    Text("Radar")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(CrewTheme.ink)
                        .accessibilityAddTraits(.isHeader)

                    RadarStatusRow(status: tracker.status, hasPosition: tracker.position != nil)

                    RadarStartButton(tracker: tracker)

                    VStack(spacing: 10) {
                        NavigationLink {
                            RadarTrialCaptureView(inventory: inventory, tracker: tracker, original: nil)
                        } label: {
                            Label("Create inventory item", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(CrewTheme.accent)

                        NavigationLink {
                            RadarInventoryList(inventory: inventory, tracker: tracker)
                        } label: {
                            Label("Find inventory item", systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(CrewTheme.accent)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CrewTheme.surface.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(CrewTheme.accent)
    }
}

private struct RadarStartButton: View {
    @ObservedObject var tracker: RadarTracker
    @State private var hasStartedTracking = false

    var body: some View {
        Button {
            hasStartedTracking = true
            tracker.start()
        } label: {
            Label(hasStartedTracking || tracker.status != "Stopped"
                  ? "Restart at MacBook" : "Start radar at MacBook",
                  systemImage: "scope")
                .font(.headline)
                .foregroundStyle(CrewTheme.surface)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(CrewTheme.accent)
        .accessibilityIdentifier("radar-start")
    }
}

private struct RadarStatusRow: View {
    let status: String
    let hasPosition: Bool
    var prefix: String? = nil

    private var isWarning: Bool {
        !hasPosition && status != "Stopped" && !status.hasPrefix("Waiting for")
    }

    var body: some View {
        Label(prefix.map { "\($0): \(status)" } ?? status,
              systemImage: hasPosition ? "scope" : isWarning ? "exclamationmark.triangle.fill" : "circle.dotted")
            .font(.body.weight(.medium))
            .foregroundStyle(isWarning ? .orange : hasPosition ? CrewTheme.accent : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(CrewTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CrewTheme.divider, lineWidth: 1))
    }
}

struct RadarTrialCaptureView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    @State private var capture: TrialCapture?
    @State private var isShowingCamera = false
    @State private var alertMessage: String?
    @State private var savedLabel: String?
    @State private var savedItemID: UUID?
    @State private var targetName = ""

    @State private var original: Item?
    @State private var locationNote: String

    init(inventory: Inventory, tracker: RadarTracker, original: Item?) {
        self.inventory = inventory
        self.tracker = tracker
        _original = State(initialValue: original)
        _locationNote = State(initialValue: original?.reports.first?.locationNote ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CrewWordmark()
                RadarStatusRow(status: tracker.status, hasPosition: tracker.position != nil)
                Text("Taking a photo records this item’s radar position.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                positionReading
                if tracker.position == nil {
                    RadarStartButton(tracker: tracker)
                }
                if let original {
                    Text(original.label).font(.headline)
                } else {
                    targetNameField
                }
                TextField("Location note (optional)", text: $locationNote)
                    .textFieldStyle(.roundedBorder)
                cameraButton

                if let capture {
                    capturedPhoto(capture)
                } else if let savedLabel {
                    savedConfirmation(savedLabel)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CrewTheme.surface.ignoresSafeArea())
        .navigationTitle(original == nil ? "Create inventory item" : "Record radar position")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $isShowingCamera) {
            RadarTrialCamera(
                position: { tracker.position },
                onCapture: { image, position in
                    capture = TrialCapture(image: image, position: position)
                    savedLabel = nil
                    savedItemID = nil
                    isShowingCamera = false
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert("Capture", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var positionReading: some View {
        if let position = tracker.position {
            Text("Current estimate: \(position.x.formatted(.number.precision(.fractionLength(1)))) m right, \(position.y.formatted(.number.precision(.fractionLength(1)))) m forward")
                .font(.body.monospacedDigit())
                .foregroundStyle(CrewTheme.ink)
                .accessibilityIdentifier("radar-current-position")
        } else {
            Text("No current position. Start or restart radar at MacBook.")
                .font(.body)
                .foregroundStyle(tracker.status == "Stopped" ? CrewTheme.ink.opacity(0.7) : .orange)
        }
    }

    private var targetNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Item name (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CrewTheme.ink)
            TextField("e.g. Survey marker", text: $targetName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Item name, optional")
        }
    }

    private var cameraButton: some View {
        Button {
            openCamera()
        } label: {
            Label(capture == nil ? "Take item photo" : "Retake photo", systemImage: "camera")
                .font(.headline)
                .foregroundStyle(CrewTheme.surface)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(CrewTheme.accent)
        .accessibilityIdentifier("radar-capture")
    }

    private func capturedPhoto(_ capture: TrialCapture) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(uiImage: capture.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Captured target photo")

            Text("Photo point: \(capture.position.x.formatted(.number.precision(.fractionLength(1)))) m right, \(capture.position.y.formatted(.number.precision(.fractionLength(1)))) m forward")
                .font(.body.monospacedDigit())
                .foregroundStyle(CrewTheme.ink)

            Button(original == nil ? "Save inventory item" : "Save radar position") { save(capture) }
                .foregroundStyle(CrewTheme.surface)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(CrewTheme.accent)
                .accessibilityIdentifier("radar-save")

            Button("Discard photo", role: .destructive) { self.capture = nil }
                .frame(minHeight: 44)
                .accessibilityIdentifier("radar-cancel-capture")
        }
    }

    private func savedConfirmation(_ label: String) -> some View {
        let waitingToSync = savedItemID.map { inventory.isPending($0) } ?? true
        return VStack(alignment: .leading, spacing: 8) {
            Label(waitingToSync ? "Saved · Waiting to sync" : "Saved · Synced",
                  systemImage: waitingToSync ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CrewTheme.accent)
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(CrewTheme.ink)
        }
    }

    private func openCamera() {
        guard tracker.position != nil else {
            alertMessage = "Start or restart radar at MacBook and wait for tracking readiness before taking a photo."
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            alertMessage = "A camera is not available on this device. Use an iPhone to capture a target."
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isShowingCamera = true
                    } else {
                        alertMessage = "Allow camera access in Settings to photograph a target."
                    }
                }
            }
        case .denied, .restricted:
            alertMessage = "Allow camera access in Settings to photograph a target."
        @unknown default:
            alertMessage = "Camera access could not be checked."
        }
    }

    private func save(_ capture: TrialCapture) {
        guard let imageData = capture.image.jpegData(compressionQuality: 1),
              let photo = PhotoImage.normalizedJPEG(from: imageData) else {
            alertMessage = "This photo could not be prepared. Your capture is still here; retake it or try saving again."
            return
        }
        let label = original?.label ?? captureLabel
        do {
            let itemID = try inventory.saveRadarPhoto(for: original, label: label, locationNote: locationNote,
                                                      photo: photo, at: capture.position)
            if original != nil {
                original = inventory.items.first { $0.id == itemID }
            } else {
                locationNote = ""
            }
            self.capture = nil
            targetName = ""
            savedLabel = label
            savedItemID = itemID
        } catch {
            alertMessage = "Unable to save \(label). Your capture is still here: \(error.localizedDescription)"
        }
    }

    private var captureLabel: String {
        let enteredName = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return enteredName.isEmpty ? "Item \(UUID().uuidString.prefix(8))" : enteredName
    }
}

private struct TrialCapture {
    let image: UIImage
    let position: RadarPoint
}

private struct RadarInventoryList: View {
    @ObservedObject var inventory: Inventory
    let tracker: RadarTracker
    @State private var query = ""

    var body: some View {
        let results = inventory.search(query)
        List {
            ForEach(results) { item in
                NavigationLink {
                    RadarTrialFindView(inventory: inventory, tracker: tracker, itemID: item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label).font(.headline)
                        Text(summary(item))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("radar-find-\(item.id.uuidString)")
                .listRowBackground(CrewTheme.surface)
            }
            if results.isEmpty {
                Text(inventory.items.isEmpty ? "Your inventory is empty" : "No matching items")
                    .foregroundStyle(.secondary)
                    .listRowBackground(CrewTheme.surface)
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search inventory")
        .scrollContentBackground(.hidden)
        .background(CrewTheme.surface)
        .navigationTitle("Find inventory item")
    }

    private func summary(_ item: Item) -> String {
        if item.reports.count > 1 { return "Needs confirmation" }
        return item.reports.first?.radarPosition == nil ? "No radar position yet" : "Saved radar position"
    }
}

struct RadarTrialFindView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker
    let itemID: UUID

    @State private var stoppedPosition: RadarPoint?
    @State private var photoRevealed = false

    private var selectedItem: Item? { inventory.items.first { $0.id == itemID } }

    private var finderPosition: RadarPoint? {
        stoppedPosition ?? tracker.position
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CrewWordmark()
                RadarStatusRow(status: tracker.status, hasPosition: tracker.position != nil,
                               prefix: "Radar status")
                    .accessibilityIdentifier("radar-finder-status")

                if let item = selectedItem {
                    selectedTarget(item)
                } else {
                    Text("This item is no longer available.")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CrewTheme.surface.ignoresSafeArea())
        .navigationTitle(selectedItem?.label ?? "Find inventory item")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: tracker.status) { status in
            if status != "Stopped" {
                stoppedPosition = nil
                photoRevealed = false
            }
        }
        .onChange(of: selectedItem?.reports.map(\.id)) { _ in
            stoppedPosition = nil
            photoRevealed = false
        }
    }

    @ViewBuilder
    private func selectedTarget(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if inventory.isPending(item.id) {
                Label("Waiting to sync this target", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if item.reports.count > 1 {
                Text("Open this item in Inventory and confirm its location before using Radar.")
                    .foregroundStyle(.secondary)
            } else if let report = item.reports.first,
                      let targetPosition = report.radarPosition {
                if let finderPosition {
                    RadarPlot(crew: finderPosition, target: targetPosition)
                }

                if stoppedPosition != nil {
                    Button(photoRevealed ? "Hide photo" : "Reveal photo") {
                        photoRevealed.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(CrewTheme.accent)
                    .accessibilityIdentifier("radar-reveal-\(item.id.uuidString)")

                    if photoRevealed, let image = UIImage(data: report.photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Photo of \(item.label)")
                    }
                    Text("Finder stopped. Reveal the photo when you are ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let position = tracker.position {
                    Button("Stop tracking here") {
                        stoppedPosition = position
                        tracker.stop()
                    }
                    .foregroundStyle(CrewTheme.surface)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(CrewTheme.accent)
                    .accessibilityIdentifier("radar-stop")
                } else {
                    Text("Start at the MacBook and wait for a position reading.")
                        .foregroundStyle(.secondary)
                    RadarStartButton(tracker: tracker)
                }
            } else {
                Text("Photograph this item at its location to place it on Radar.")
                    .foregroundStyle(.secondary)
                NavigationLink("Record radar position") {
                    RadarTrialCaptureView(inventory: inventory, tracker: tracker, original: item)
                }
                .buttonStyle(.bordered)
                .tint(CrewTheme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrewTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CrewTheme.divider, lineWidth: 1))
        .padding(.top, 4)
    }
}
