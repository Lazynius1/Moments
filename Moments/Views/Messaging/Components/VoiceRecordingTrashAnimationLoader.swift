import Foundation
import Lottie

enum VoiceRecordingTrashAnimationLoader {
    static func load() -> LottieAnimation? {
        let bundle = Bundle.main
        let resourceName = "chat_voice_record_trash"
        let subdirectories: [String?] = ["Resources/Lottie", "Lottie", nil]

        for subdirectory in subdirectories {
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: subdirectory
            ), let animation = LottieAnimation.filepath(url.path) {
                return animation
            }
        }

        if let resourceURL = bundle.resourceURL {
            let directURL = resourceURL
                .appendingPathComponent("Resources/Lottie")
                .appendingPathComponent("\(resourceName).json")
            if FileManager.default.fileExists(atPath: directURL.path),
               let animation = LottieAnimation.filepath(directURL.path) {
                return animation
            }
        }

        return LottieAnimation.named(resourceName)
    }
}
