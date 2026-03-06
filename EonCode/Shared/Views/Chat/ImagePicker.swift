import SwiftUI

#if os(iOS)
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [Data]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 5
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                        if let uiImage = image as? UIImage,
                           let data = uiImage.jpegData(compressionQuality: 0.8) {
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(data)
                            }
                        }
                    }
                }
            }
            parent.dismiss()
        }
    }
}
#endif

#if os(macOS)
struct ImagePicker: View {
    @Binding var selectedImages: [Data]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Välj bilder")
                .font(.headline)

            Button("Välj från disk…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.image]
                if panel.runModal() == .OK {
                    for url in panel.urls {
                        if let data = try? Data(contentsOf: url) {
                            selectedImages.append(data)
                        }
                    }
                }
                dismiss()
            }

            Button("Avbryt") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 300)
    }
}
#endif
