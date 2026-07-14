import SwiftUI
import UIKit

struct CameraImagePicker: UIViewControllerRepresentable {
  var onImageData: (Data) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.cameraCaptureMode = .photo
    picker.allowsEditing = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onImageData: onImageData, onCancel: onCancel)
  }

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let onImageData: (Data) -> Void
    let onCancel: () -> Void

    init(onImageData: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
      self.onImageData = onImageData
      self.onCancel = onCancel
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      onCancel()
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
      if let data = image?.jpegData(compressionQuality: 0.9) {
        onImageData(data)
      } else {
        onCancel()
      }
    }
  }
}
