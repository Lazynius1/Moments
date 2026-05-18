import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StoryMediaPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    let onSelect: (UIImage?, URL?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var pickerBackgroundColor: UIColor {
        colorScheme == .dark
            ? UIColor(red: 11.0 / 255.0, green: 18.0 / 255.0, blue: 21.0 / 255.0, alpha: 1.0)
            : UIColor(red: 250.0 / 255.0, green: 249.0 / 255.0, blue: 246.0 / 255.0, alpha: 1.0)
    }

    private var pickerForegroundColor: UIColor {
        colorScheme == .dark ? .white : .black
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        picker.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        picker.view.backgroundColor = pickerBackgroundColor
        applyAppearance(to: picker)

        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        uiViewController.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        uiViewController.view.backgroundColor = pickerBackgroundColor
        applyAppearance(to: uiViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyAppearance(to picker: PHPickerViewController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = pickerBackgroundColor
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: pickerForegroundColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: pickerForegroundColor]

        picker.navigationController?.navigationBar.standardAppearance = appearance
        picker.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        picker.navigationController?.navigationBar.compactAppearance = appearance
        picker.navigationController?.navigationBar.tintColor = pickerForegroundColor
        picker.navigationController?.view.backgroundColor = pickerBackgroundColor
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: StoryMediaPicker

        init(_ parent: StoryMediaPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.onSelect(nil, nil)
                parent.dismiss()
                return
            }

            if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    DispatchQueue.main.async {
                        if let image = object as? UIImage {
                            self.parent.selectedImage = image
                            self.parent.onSelect(image, nil)
                        } else {
                            self.parent.onSelect(nil, nil)
                        }
                        self.parent.dismiss()
                    }
                }
            } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.movie.identifier) { data, error in
                    DispatchQueue.main.async {
                        if let videoData = data {
                            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let tempFileName = "temp_video_\(UUID().uuidString).mp4"
                            let tempURL = documentsPath.appendingPathComponent(tempFileName)

                            do {
                                try videoData.write(to: tempURL)
                                self.parent.selectedVideoURL = tempURL
                                self.parent.onSelect(nil, tempURL)
                            } catch {
                                self.parent.onSelect(nil, nil)
                            }
                        } else {
                            self.parent.onSelect(nil, nil)
                        }
                        self.parent.dismiss()
                    }
                }
            } else {
                parent.onSelect(nil, nil)
                parent.dismiss()
            }
        }
    }
}
