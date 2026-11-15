import AVFoundation
import SwiftUI
import UIKit

struct RadarTrialView: View {
    let inventory: Inventory

    @StateObject private var tracker = RadarTracker()
    @State private var hasStartedTracking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Capture a photo target on one iPhone, then find it from the other.")
                        .font(.headline)

                    Label(tracker.status, systemImage: tracker.position == nil
                          ? "exclamationmark.triangle.fill" : "location.north.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(tracker.position == nil ? .orange : .green)

                    Button {
                        hasStartedTracking = true
                        tracker.start()
                    } label: {
                        Label(hasStartedTracking ? "Restart at MacBook" : "Start radar at MacBook",
                              systemImage: "location.north.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("radar-start")

                    Text("Start both iPhones at the same spot. Hold each phone flat with its screen up and top edge pointed along the same floor mark. Walk with the phone held in a consistent forward orientation. At each target, stop and let the last walking readings settle before taking the photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        RadarTrialCaptureView(inventory: inventory, tracker: tracker)
                    } label: {
                        Label("Capture a target", systemImage: "camera")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        RadarTrialFindView(inventory: inventory, tracker: tracker)
                    } label: {
                        Label("Find a target", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("SpaceFind Radar Trial")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RadarTrialCaptureView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    @State private var capture: TrialCapture?
    @State private var isShowingCamera = false
    @State private var alertMessage: String?
    @State private var savedLabel: String?
    @State private var savedItemID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(tracker.status, systemImage: tracker.position == nil
                      ? "exclamationmark.triangle.fill" : "location.north.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tracker.position == nil ? .orange : .green)

                Text("Stop walking and let the latest distance reading settle before taking the photo. The shutter position is saved with that photo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let position = tracker.position {
                    Text("Current estimate: \(position.x.formatted(.number.precision(.fractionLength(1)))) m right, \(position.y.formatted(.number.precision(.fractionLength(1)))) m forward")
                        .font(.subheadline.monospacedDigit())
                        .accessibilityIdentifier("radar-current-position")
                } else {
                    Text("No current position. Start or restart radar at MacBook.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    openCamera()
                } label: {
                    Label(capture == nil ? "Take target photo" : "Retake photo", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("radar-capture")

                if let capture {
                    Image(uiImage: capture.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Captured target photo")

                    Text("Frozen position: \(capture.position.x.formatted(.number.precision(.fractionLength(1)))) m right, \(capture.position.y.formatted(.number.precision(.fractionLength(1)))) m forward")
                        .font(.subheadline.monospacedDigit())

                    Button("Save target") { save(capture) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("radar-save")

                    Button("Discard photo", role: .destructive) { self.capture = nil }
                        .accessibilityIdentifier("radar-cancel-capture")
                } else if let savedLabel {
                    let waitingToSync = savedItemID.map { inventory.isPending($0) } ?? true
                    Label(waitingToSync ? "Saved locally · Waiting to sync" : "Saved locally · Synced",
                          systemImage: waitingToSync ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(savedLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Capture target")
        .navigationBarTitleDisplayMode(.inline)
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
        let label = "Radar target \(UUID().uuidString.prefix(8))"
        do {
            try inventory.create(label: label, description: "Radar trial target",
                                 location: capture.position.trialLocation, photo: photo)
            self.capture = nil
            savedLabel = label
            savedItemID = inventory.items.first(where: { $0.label == label })?.id
        } catch {
            alertMessage = "Unable to save \(label). Your capture is still here: \(error.localizedDescription)"
        }
    }
}

private struct TrialCapture {
    let image: UIImage
    let position: RadarPoint
}

private struct RadarTrialFindView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    @State private var selectedItemID: UUID?
    @State private var stoppedPosition: RadarPoint?
    @State private var hasStopped = false
    @State private var revealedItemID: UUID?

    private var selectedItem: Item? {
        inventory.items.first { $0.id == selectedItemID }
    }

    private var finderPosition: RadarPoint? {
        hasStopped ? stoppedPosition : tracker.position
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Radar status: \(tracker.status)", systemImage: tracker.position == nil
                      ? "exclamationmark.triangle.fill" : "location.north.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tracker.position == nil ? .orange : .green)
                    .accessibilityIdentifier("radar-finder-status")

                if inventory.items.isEmpty {
                    Text("Saved targets will appear here after a target photo is captured.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose a target")
                        .font(.headline)
                    ForEach(inventory.items) { item in
                        Button {
                            if selectedItemID != item.id {
                                stoppedPosition = nil
                                hasStopped = false
                                revealedItemID = nil
                            }
                            selectedItemID = item.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label).font(.headline)
                                    Text(targetSummary(item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if inventory.isPending(item.id) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Waiting to sync")
                                }
                                if selectedItemID == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("radar-find-\(item.id.uuidString)")
                    }
                }

                if let item = selectedItem {
                    selectedTarget(item)
                }
            }
            .padding()
        }
        .navigationTitle("Find a target")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: tracker.status) { status in
            if status != "Stopped" {
                stoppedPosition = nil
                hasStopped = false
                revealedItemID = nil
            }
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

            if item.reports.count != 1 {
                Text(item.reports.isEmpty
                     ? "This target has no saved photo or radar position."
                     : "This target has multiple location reports, so its radar position is ambiguous.")
                    .foregroundStyle(.secondary)
            } else if let report = item.reports.first,
                      let targetPosition = RadarPoint(trialLocation: report.location) {
                if let finderPosition {
                    RadarPlot(crew: finderPosition, target: targetPosition)
                } else {
                    Text("Start or restart radar at MacBook and wait for tracking readiness. No finder position is available yet.")
                        .foregroundStyle(.secondary)
                }

                if hasStopped {
                    Button(revealedItemID == item.id ? "Hide photo" : "Reveal photo") {
                        revealedItemID = revealedItemID == item.id ? nil : item.id
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("radar-reveal-\(item.id.uuidString)")

                    if revealedItemID == item.id, let image = UIImage(data: report.photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Photo of \(item.label)")
                    }
                    Text("Finder stopped. Reveal the photo when you are ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let position = tracker.position {
                    Button("Stop tracking here") {
                        stoppedPosition = position
                        hasStopped = true
                        tracker.stop()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("radar-stop")
                } else {
                    Text("Start or restart radar at MacBook and wait for tracking readiness before stopping here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No recognized trial radar position is available for this target. No dot is shown.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func targetSummary(_ item: Item) -> String {
        guard item.reports.count == 1, let report = item.reports.first,
              RadarPoint(trialLocation: report.location) != nil else {
            return "Radar position unavailable"
        }
        return inventory.isPending(item.id) ? "Valid position · waiting to sync" : "Valid trial position"
    }
}
