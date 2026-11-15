import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ItemDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var inventory: Inventory
    let itemID: UUID

    @State private var editSession: EditSession?
    @State private var isRenaming = false
    @State private var newLabel = ""
    @State private var saveError: String?

    private var item: Item? { inventory.items.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if item.reports.count > 1 {
                            conflictReports(item)
                        } else if let report = item.reports.first {
                            PhotoThumbnail(
                                data: report.photo,
                                accessibilityLabel: "Photo of \(item.label)",
                                maximumPixelSize: 1200,
                                contentMode: .fit
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 250)
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 8) {
                                Label(report.location, systemImage: "mappin.and.ellipse")
                                    .font(.title3.weight(.semibold))
                                if inventory.isPending(item.id) {
                                    Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("No location report is available.")
                                .foregroundStyle(.secondary)
                        }

                        if !item.description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                Text(item.description)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Button {
                            newLabel = item.label
                            isRenaming = true
                        } label: {
                            Label("Rename item", systemImage: "pencil")
                        }
                        .alert("Rename item", isPresented: $isRenaming) {
                            TextField("New label", text: $newLabel)
                            Button("Cancel", role: .cancel) {}
                            Button("Save") {
                                do {
                                    try inventory.rename(itemID: itemID, label: newLabel)
                                } catch {
                                    saveError = error.localizedDescription
                                }
                            }
                            .disabled(newLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .foregroundStyle(CrewTheme.ink)
                }
                .background(CrewTheme.surface)
                .navigationTitle(item.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if item.reports.count == 1 {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Update location") {
                                editSession = EditSession(item: item)
                            }
                            .accessibilityIdentifier("update-location")
                        }
                    }
                }
            } else {
                Text("This item is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editSession) { session in
            ItemEditor(inventory: inventory, original: session.item)
        }
        .alert("Unable to save change", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    @ViewBuilder
    private func conflictReports(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Choose the recorded location", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Both crew members recorded a move. Select the photo and location to keep.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(item.reports, id: \.id) { report in
                conflictOption(report, for: item)
            }

            if inventory.isPending(item.id) {
                Label("Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func conflictOption(_ report: Report, for item: Item) -> some View {
        Button {
            confirm(item: item, report: report)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        conflictPhoto(report)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                        conflictDetails(report)
                    }
                } else {
                    HStack(spacing: 14) {
                        conflictPhoto(report)
                            .frame(width: 84, height: 84)
                        conflictDetails(report)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CrewTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CrewTheme.divider, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("confirm-\(report.id.uuidString)")
        .accessibilityLabel("Keep \(report.location)")
        .accessibilityHint("Confirms this location and its photo for \(item.label)")
    }

    private func conflictPhoto(_ report: Report) -> some View {
        PhotoThumbnail(
            data: report.photo,
            accessibilityLabel: "Photo for \(report.location)",
            maximumPixelSize: 420,
            contentMode: .fit
        )
        .accessibilityHidden(true)
    }

    private func conflictDetails(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.location)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(CrewTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text("Keep this location")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(CrewTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confirm(item: Item, report: Report) {
        do {
            try inventory.confirm(
                itemID: item.id,
                observedIDs: item.reports.map(\.id),
                chosenID: report.id
            )
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var inventory: Inventory

    private let original: Item?
    @State private var label: String
    @State private var description: String
    @State private var location: String
    @State private var selectedPhoto: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoLoadID = UUID()
    @State private var isShowingCamera = false
    @State private var editorError: String?
    @State private var cameraAlert: CameraAlert?

    init(inventory: Inventory, original: Item?) {
        self.inventory = inventory
        self.original = original
        _label = State(initialValue: original?.label ?? "")
        _description = State(initialValue: original?.description ?? "")
        _location = State(initialValue: original?.reports.first?.location ?? "")
        _selectedPhoto = State(initialValue: original?.reports.first?.photo)
    }

    private var isReadyToSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedPhoto != nil && !isLoadingPhoto
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    if original == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Label")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(CrewTheme.ink)
                            TextField("Enter a label", text: $label)
                                .textContentType(.name)
                                .accessibilityLabel("Item label")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description (optional)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(CrewTheme.ink)
                            TextField("Add details", text: $description, axis: .vertical)
                                .lineLimit(2...4)
                                .accessibilityLabel("Description, optional")
                        }
                    } else {
                        LabeledContent("Label", value: label)
                    }
                }
                .listRowBackground(CrewTheme.surface)

                Section("Location") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Location")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CrewTheme.ink)
                        TextField("Where is it?", text: $location, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel("Item location")
                    }
                }
                .listRowBackground(CrewTheme.surface)

                Section("Photo") {
                    if let selectedPhoto {
                        PhotoThumbnail(
                            data: selectedPhoto,
                            accessibilityLabel: "Selected photo for \(label.isEmpty ? "item" : label)",
                            maximumPixelSize: 640,
                            contentMode: .fit
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .accessibilityHidden(true)
                    } else {
                        Label("A photo is required", systemImage: "photo.badge.plus")
                            .foregroundStyle(.secondary)
                    }

                    if isLoadingPhoto {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing photo…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityHint("Choose a photo from the library")

                    Button {
                        requestCamera()
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
                .listRowBackground(CrewTheme.surface)

                if !isReadyToSave {
                    Section {
                        Text("Add a label, location, and photo to save.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(CrewTheme.surface)
                }
            }
            .navigationTitle(original == nil ? "New Item" : "Update Location")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(CrewTheme.surface)
            .foregroundStyle(CrewTheme.ink)
            .tint(CrewTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isReadyToSave)
                }
            }
            .onChange(of: selectedPhotoItem) { item in
                let requestID = UUID()
                photoLoadID = requestID
                guard let item else {
                    isLoadingPhoto = false
                    return
                }
                Task { await loadPhoto(item, requestID: requestID) }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPicker(isPresented: $isShowingCamera, onImage: acceptCameraImage)
                    .ignoresSafeArea()
            }
            .alert("Unable to save", isPresented: Binding(
                get: { editorError != nil },
                set: { if !$0 { editorError = nil } }
            )) {
                Button("OK", role: .cancel) { editorError = nil }
            } message: {
                Text(editorError ?? "Please try again.")
            }
            .alert(item: $cameraAlert) { alert in
                if alert.canOpenSettings {
                    return Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text("Open Settings"), action: openSettings),
                        secondaryButton: .cancel(Text("OK"))
                    )
                }
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func save() {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let selectedPhoto else {
            editorError = "Choose or take a photo before saving."
            return
        }

        do {
            if let original {
                guard original.reports.count == 1, let parent = original.reports.first else {
                    editorError = "Resolve the location conflict before moving this item."
                    return
                }
                try inventory.move(
                    itemID: original.id,
                    parentID: parent.id,
                    location: cleanLocation,
                    photo: selectedPhoto
                )
            } else {
                try inventory.create(
                    label: cleanLabel,
                    description: cleanDescription,
                    location: cleanLocation,
                    photo: selectedPhoto
                )
            }
            dismiss()
        } catch {
            editorError = error.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem, requestID: UUID) async {
        guard photoLoadID == requestID else { return }
        isLoadingPhoto = true

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard photoLoadID == requestID else { return }
                isLoadingPhoto = false
                editorError = "The selected photo could not be read. Choose another photo."
                return
            }
            let normalized = await Task.detached(priority: .userInitiated) {
                PhotoImage.normalizedJPEG(from: data)
            }.value
            guard photoLoadID == requestID else { return }
            isLoadingPhoto = false
            guard let normalized else {
                editorError = "The photo could not be prepared. Choose another photo."
                return
            }
            selectedPhoto = normalized
        } catch {
            guard photoLoadID == requestID else { return }
            isLoadingPhoto = false
            editorError = error.localizedDescription
        }
    }

    private func acceptCameraImage(_ image: UIImage) {
        let requestID = UUID()
        photoLoadID = requestID
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            isLoadingPhoto = false
            editorError = "The camera photo could not be read. Please try again."
            return
        }
        isLoadingPhoto = true
        Task {
            let normalized = await Task.detached(priority: .userInitiated) {
                PhotoImage.normalizedJPEG(from: data)
            }.value
            guard photoLoadID == requestID else { return }
            isLoadingPhoto = false
            if let normalized {
                selectedPhoto = normalized
            } else {
                editorError = "The photo could not be prepared. Please take another photo."
            }
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlert = CameraAlert(
                title: "Camera unavailable",
                message: "This device cannot take a camera photo. You can still choose one from the library.",
                canOpenSettings: false
            )
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
                        showCameraPermissionAlert()
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert()
        @unknown default:
            showCameraPermissionAlert()
        }
    }

    private func showCameraPermissionAlert() {
        cameraAlert = CameraAlert(
            title: "Camera access is off",
            message: "Allow camera access in Settings to take a photo. Choose from Library remains available.",
            canOpenSettings: true
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct EditSession: Identifiable {
    let id = UUID()
    let item: Item
}

private struct CameraAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let canOpenSettings: Bool
}

struct PhotoThumbnail: View {
    let data: Data?
    let accessibilityLabel: String
    let maximumPixelSize: Int
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill

    @State private var thumbnailData: Data?
    @State private var thumbnailSource: Data?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)

                if thumbnailSource == data, let thumbnailData, let image = UIImage(data: thumbnailData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .task(id: data) {
            thumbnailData = nil
            thumbnailSource = nil
            guard let data else { return }
            let maximumPixelSize = maximumPixelSize
            let result = await Task.detached(priority: .utility) {
                PhotoImage.thumbnailJPEG(from: data, maximumPixelSize: maximumPixelSize)
            }.value
            if !Task.isCancelled {
                thumbnailData = result
                thumbnailSource = data
            }
        }
    }
}

private enum PhotoImage {
    static let maximumBytes = 2 * 1024 * 1024

    static func normalizedJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        for size in [1600, 1200, 900, 675, 500, 375] {
            guard let image = thumbnail(source: source, maximumPixelSize: size) else { return nil }
            for quality: CGFloat in [0.84, 0.68, 0.52, 0.38] {
                guard let jpeg = jpegData(from: image, quality: quality) else { continue }
                if jpeg.count <= maximumBytes { return jpeg }
            }
        }
        return nil
    }

    static func thumbnailJPEG(from data: Data, maximumPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = thumbnail(source: source, maximumPixelSize: maximumPixelSize) else { return nil }
        return jpegData(from: image, quality: 0.72)
    }

    private static func thumbnail(source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
