import SwiftUI
import Kingfisher

@MainActor
final class StoryPlaybackCoordinator: ObservableObject {
    @Published private(set) var preloadedStories: [String: Story] = [:]
    @Published private(set) var preloadedImages: [String: UIImage] = [:]
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var isPaused: Bool = false

    private let maxPreloadedStories = 6
    private let storiesToPreloadAhead = 5
    private let defaultStoryDuration: Double = 15.0
    private var imageTimer: Timer?
    private var currentStoryId: String?
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: .momentsDidReceiveMemoryWarning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Conservamos la story actual y soltamos las precargadas para liberar RAM.
            Task { @MainActor [weak self] in
                self?.preloadedImages.removeAll()
                self?.preloadedStories.removeAll()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func prepareStory(_ story: Story, onImageComplete: @escaping () -> Void) {
        progress = 0.0
        isPaused = false
        currentStoryId = story.id

        if story.mediaItem.type == .image {
            startImageTimer(for: story, onComplete: onImageComplete)
        }
    }

    func stopStory() {
        isPaused = true
        progress = 0.0
        currentStoryId = nil
        invalidateImageTimer()
    }

    func pauseStory() {
        isPaused = true
        invalidateImageTimer()
    }

    func resumeStory(_ story: Story, canResume: Bool, onImageComplete: @escaping () -> Void) {
        guard canResume else { return }

        isPaused = false

        if story.mediaItem.type == .image {
            startImageTimer(for: story, onComplete: onImageComplete)
        }
    }

    func setPausedFromVideoBinding(_ shouldPause: Bool) {
        isPaused = shouldPause
    }

    func updateVideoProgress(_ newProgress: Double, for story: Story) {
        guard currentStoryId == story.id else { return }
        let storyId = story.id
        let clampedProgress = min(max(newProgress, 0.0), 1.0)

        Task { @MainActor [weak self] in
            guard let self,
                  self.currentStoryId == storyId,
                  self.progress != clampedProgress else { return }
            self.progress = clampedProgress
        }
    }

    func canAdvanceAfterVideoComplete() -> Bool {
        !isPaused
    }

    func progressForSegment(index: Int, storyIndex: Int) -> Double {
        if index < storyIndex {
            return 1.0
        } else if index == storyIndex {
            return progress
        } else {
            return 0.0
        }
    }

    func preloadNextStory(currentStoryId: String, allStories: [Story]) {
        guard let currentIndex = allStories.firstIndex(where: { $0.id == currentStoryId }) else {
            return
        }

        let endIndex = min(currentIndex + storiesToPreloadAhead, allStories.count - 1)
        guard currentIndex < endIndex else { return }

        for index in (currentIndex + 1)...endIndex {
            preloadStory(allStories[index])
        }
    }

    func preloadStory(_ story: Story) {
        guard let storyId = story.id else { return }

        if preloadedStories[storyId] != nil {
            return
        }

        if preloadedStories.count >= maxPreloadedStories {
            clearOldestPreloadedStory()
        }

        preloadedStories[storyId] = story

        switch story.mediaItem.type {
        case .image:
            preloadImage(for: story)
        case .video:
            preloadVideo(for: story)
            preloadVideoPoster(for: story)
        }
    }

    func clearPreloadCache() {
        preloadedStories.removeAll()
        preloadedImages.removeAll()
    }

    func getPreloadedStory(_ storyId: String) -> Story? {
        preloadedStories[storyId]
    }

    func getPreloadedImage(_ storyId: String) -> UIImage? {
        preloadedImages[storyId]
    }

    private func preloadImage(for story: Story) {
        guard let storyId = story.id,
              let url = URL(string: story.mediaItem.url) else { return }

        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard let self else { return }

            if case .success(let imageResult) = result {
                Task { @MainActor in
                    self.preloadedImages[storyId] = imageResult.image
                }
            }
        }
    }

    private func preloadVideo(for story: Story) {
        guard story.id != nil else { return }

        let trimmed = story.mediaItem.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        VideoPreloader.shared.preloadAssets(urls: [trimmed])
    }

    private func preloadVideoPoster(for story: Story) {
        guard let storyId = story.id,
              let thumb = story.mediaItem.thumbnailUrl?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !thumb.isEmpty,
              let url = URL(string: thumb) else { return }

        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard let self else { return }
            if case .success(let imageResult) = result {
                Task { @MainActor in
                    self.preloadedImages[storyId] = imageResult.image
                }
            }
        }
    }

    private func clearOldestPreloadedStory() {
        guard let oldestStoryId = preloadedStories.keys.first else { return }

        preloadedStories.removeValue(forKey: oldestStoryId)
        preloadedImages.removeValue(forKey: oldestStoryId)
    }

    private func startImageTimer(for story: Story, onComplete: @escaping () -> Void) {
        let duration = story.duration > 0 ? story.duration : defaultStoryDuration
        invalidateImageTimer()

        imageTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickImageStory(duration: duration, onComplete: onComplete)
            }
        }
    }

    private func tickImageStory(duration: Double, onComplete: @escaping () -> Void) {
        guard !isPaused else { return }

        progress += 0.1 / duration

        if progress >= 1.0 {
            progress = 1.0
            invalidateImageTimer()
            onComplete()
        }
    }

    private func invalidateImageTimer() {
        imageTimer?.invalidate()
        imageTimer = nil
    }
}
