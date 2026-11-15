import AVFoundation
import SwiftUI
import UIKit

struct RadarTrialView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    @State private var hasStartedTracking = false

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shared start")
                            .font(.headline)
                            .foregroundStyle(CrewTheme.ink)
                        Text("Use the same starting point beside a stationary MacBook on both phones. Hold each phone flat and screen-up, with its top edge aimed at the centre of the MacBook screen. As you walk, point each top edge in your direction of travel, especially when turning.")
                            .font(.body)
                            .foregroundStyle(CrewTheme.ink)
                        Text("Stop walking and let the latest distance reading settle before taking a photo.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CrewTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    VStack(spacing: 10) {
                        NavigationLink {
                            RadarTrialCaptureView(inventory: inventory, tracker: tracker)
                        } label: {
                            Label("Capture a target", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(CrewTheme.accent)

                        NavigationLink {
                            RadarTrialFindView(inventory: inventory, tracker: tracker)
                        } label: {
                            Label("Find a target", systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

private struct RadarTrialCaptureView: View {
    @ObservedObject var inventory: Inventory
    @ObservedObject var tracker: RadarTracker

    @State private var capture: TrialCapture?
    @State private var isShowingCamera = false
    @State private var alertMessage: String?
    @State private var savedLabel: String?
    @State private var savedItemID: UUID?
    @State private var targetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CrewWordmark()
                RadarStatusRow(status: tracker.status, hasPosition: tracker.position != nil)
                Text("The photo saves the current reading as its target point.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                positionReading
                targetNameField
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
        .navigationTitle("Capture target")
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
            Text("Target name (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CrewTheme.ink)
            TextField("e.g. Survey marker", text: $targetName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Target name, optional")
        }
    }

    private var cameraButton: some View {
        Button {
            openCamera()
        } label: {
            Label(capture == nil ? "Take target photo" : "Retake photo", systemImage: "camera")
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

            Button("Save target") { save(capture) }
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
        let label = captureLabel
        do {
            let itemID = try inventory.create(label: label, description: "Radar trial target",
                                               location: capture.position.trialLocation, photo: photo)
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
        return enteredName.isEmpty ? "Radar target \(UUID().uuidString.prefix(8))" : enteredName
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

    private var radarTargets: [Item] { inventory.items.filter(\.isRadarTarget) }

    private var selectedItem: Item? {
        radarTargets.first { $0.id == selectedItemID }
    }

    private var finderPosition: RadarPoint? {
        hasStopped ? stoppedPosition : tracker.position
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CrewWordmark()
                RadarStatusRow(status: tracker.status, hasPosition: tracker.position != nil,
                               prefix: "Radar status")
                    .accessibilityIdentifier("radar-finder-status")

                if radarTargets.isEmpty {
                    Text("Capture a radar target to make it available here.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    Text("Choose a target")
                        .font(.headline)
                        .foregroundStyle(CrewTheme.ink)
                    ForEach(radarTargets) { item in
                        Button {
                            if selectedItemID != item.id {
                                stoppedPosition = nil
                                hasStopped = false
                                revealedItemID = nil
                            }
                            selectedItemID = item.id
                        } label: {
                            targetRow(item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("radar-find-\(item.id.uuidString)")
                    }
                }

                if let item = selectedItem {
                    selectedTarget(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CrewTheme.surface.ignoresSafeArea())
        .navigationTitle("Find a target")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: tracker.status) { status in
            if status != "Stopped" {
                stoppedPosition = nil
                hasStopped = false
                revealedItemID = nil
            }
        }
    }

    private func targetRow(_ item: Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CrewTheme.ink)
                Text(targetSummary(item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if inventory.isPending(item.id) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Waiting to sync")
            }
            if selectedItemID == item.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CrewTheme.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedItemID == item.id ? CrewTheme.accent.opacity(0.08) : CrewTheme.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CrewTheme.divider, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
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
                Text("Multiple reports make this target ambiguous. No radar position is shown.")
                    .foregroundStyle(.secondary)
            } else if let report = item.reports.first,
                      let targetPosition = RadarPoint(trialLocation: report.location) {
                if let finderPosition {
                    RadarPlot(crew: finderPosition, target: targetPosition)
                }

                if hasStopped {
                    Button(revealedItemID == item.id ? "Hide photo" : "Reveal photo") {
                        revealedItemID = revealedItemID == item.id ? nil : item.id
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(CrewTheme.accent)
                    .accessibilityIdentifier("radar-reveal-\(item.id.uuidString)")

                    if revealedItemID == item.id, let image = UIImage(data: report.photo) {
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
                        hasStopped = true
                        tracker.stop()
                    }
                    .foregroundStyle(CrewTheme.surface)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(CrewTheme.accent)
                    .accessibilityIdentifier("radar-stop")
                } else {
                    Text("No finder position yet. Start radar at MacBook and wait for a reading before stopping here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No recognized radar position is available for this target. No dot is shown.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrewTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CrewTheme.divider, lineWidth: 1))
        .padding(.top, 4)
    }

    private func targetSummary(_ item: Item) -> String {
        if item.reports.count > 1 { return "Needs confirmation" }
        guard let report = item.reports.first,
              RadarPoint(trialLocation: report.location) != nil else {
            return "Radar position unavailable"
        }
        return inventory.isPending(item.id) ? "Valid position · waiting to sync" : "Saved radar position"
    }
}
