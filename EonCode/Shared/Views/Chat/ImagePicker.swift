import SwiftUI

#if os(iOS)
import PhotosUI

/// Native SwiftUI photo picker — avoids the _UIReparentingView warning
/// that occurs when PHPickerViewController is wrapped in UIViewControllerRepresentable.
struct ImagePicker: View {
    @Binding var selectedImages: [Data]
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 5,
            matching: .images
        ) {
            // Empty label — this view is only used programmatically via .sheet
            EmptyView()
        }
        .photosPickerStyle(.presentation)
        .onChange(of: pickerItems) { _, items in
            Task {
                var loaded: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                await MainActor.run {
                    selectedImages.append(contentsOf: loaded)
                    dismiss()
                }
            }
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
