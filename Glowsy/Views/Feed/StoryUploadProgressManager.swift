import SwiftUI

class StoryUploadProgressManager: ObservableObject {
    static let shared = StoryUploadProgressManager()

    @Published var isUploading = false
    @Published var progress: Double = 0.0

    private init() {}

    func startUpload() {
        isUploading = true
        progress = 0.0
    }

    func updateProgress(_ value: Double) {
        progress = value
    }

    func finishUpload() {
        isUploading = false
        progress = 1.0
    }

    func cancelUpload() {
        isUploading = false
        progress = 0.0
    }
}
