import SwiftUI
import UIKit

/// The camera delegate may finish after the photographer has moved.
struct TrialShutter {
    private var point: RadarPoint?

    mutating func press(at position: RadarPoint?) -> Bool {
        guard point == nil, let position else { return false }
        point = position
        return true
    }

    mutating func finish() -> RadarPoint? {
        defer { point = nil }
        return point
    }
}

struct RadarTrialCamera: UIViewControllerRepresentable {
    let position: () -> RadarPoint?
    let onCapture: (UIImage, RadarPoint) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.delegate = context.coordinator
        context.coordinator.installControls(on: picker)
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.camera = self
    }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var camera: RadarTrialCamera
        private weak var picker: UIImagePickerController?
        private let take = UIButton(type: .system)
        private var shutter = TrialShutter()

        init(_ camera: RadarTrialCamera) { self.camera = camera }

        func installControls(on picker: UIImagePickerController) {
            self.picker = picker
            let overlay = UIView(frame: picker.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let cancel = UIButton(type: .system)
            cancel.configuration = .filled()
            cancel.setTitle("Cancel", for: .normal)
            cancel.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
            take.configuration = .filled()
            take.setTitle("Take photo", for: .normal)
            take.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
            let controls = UIStackView(arrangedSubviews: [cancel, take])
            controls.axis = .horizontal
            controls.spacing = 20
            controls.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(controls)
            NSLayoutConstraint.activate([
                controls.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                controls.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
            ])
            picker.cameraOverlayView = overlay
        }

        @objc private func takePhoto() {
            guard shutter.press(at: camera.position()) else {
                take.setTitle("Restart tracking at MacBook", for: .normal)
                take.isEnabled = false
                return
            }
            take.isEnabled = false
            picker?.takePicture()
        }

        @objc private func cancelCapture() {
            _ = shutter.finish()
            camera.onCancel()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancelCapture() }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let point = shutter.finish() else { return }
            guard let image = info[.originalImage] as? UIImage else {
                camera.onCancel()
                return
            }
            camera.onCapture(image, point)
        }
    }
}
