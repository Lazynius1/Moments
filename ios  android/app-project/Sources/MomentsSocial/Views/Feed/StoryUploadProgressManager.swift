import SwiftUI

class StoryUploadProgressManaager: ObservableObject {
    static let shared = StoryUploadProgressManager()
    
    @Published var isUploading: Bool = false
    @Published var progress: Double = 0.0
    
    private init() {}
    
    func startUpload() {
        DispatchQueue.main.async {
            self.isUploading = true
            self.progress = 0.0
        }
    }
    
    func updateProgress(_ progress: Double) {
        DispatchQueue.main.async {
            self.progress = min(max(progress, 0.0), 1.0)
        }
    }
    
    func finishUpload() {
        DispatchQueue.main.async {
            self.progress = 1.0
            
            // Delay para mostrar completado
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isUploading = false
                self.progress = 0.0
            }
        }
    }
    
    func cancelUpload() {
        DispatchQueue.main.async {
            self.isUploading = false
            self.progress = 0.0
        }
    }
}
