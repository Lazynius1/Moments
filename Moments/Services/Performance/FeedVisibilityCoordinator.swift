import SwiftUI
import Combine

/// Elige un único vídeo activo en el feed según la fracción visible de cada post.
@MainActor
final class FeedVisibilityCoordinator: ObservableObject {
    static let shared = FeedVisibilityCoordinator()

    @Published private(set) var activeVideoMomentId: String?

    private var visibilityByMomentId: [String: CGFloat] = [:]
    private let playThreshold: CGFloat = 0.55

    private init() {}

    func update(all values: [String: CGFloat]) {
        visibilityByMomentId = values
        pickWinner()
    }

    func report(momentId: String, fraction: CGFloat) {
        visibilityByMomentId[momentId] = fraction
        pickWinner()
    }

    func clear(momentId: String) {
        visibilityByMomentId.removeValue(forKey: momentId)
        pickWinner()
    }

    /// Fija un único vídeo activo (p. ej. durante hero → detalle).
    func pinActiveVideo(momentId: String) {
        visibilityByMomentId = [momentId: 1.0]
        activeVideoMomentId = momentId
    }

    func isActive(momentId: String?) -> Bool {
        guard let momentId, let activeVideoMomentId else { return false }
        return activeVideoMomentId == momentId
    }

    private func pickWinner() {
        let signpostID = PerformanceSignposts.makeID()
        PerformanceSignposts.begin("FeedPickActiveVideo", id: signpostID)

        let candidate = visibilityByMomentId
            .filter { $0.value >= playThreshold }
            .max(by: { $0.value < $1.value })?
            .key

        if activeVideoMomentId != candidate {
            activeVideoMomentId = candidate
            PerformanceSignposts.event("FeedActiveVideoChanged")
        }

        PerformanceSignposts.end("FeedPickActiveVideo", id: signpostID)
    }
}

// MARK: - Visibility reporting

struct MomentVisibilityPreference: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct FeedMomentVisibilityReporter: ViewModifier {
    let momentId: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let screen = UIScreen.main.bounds
                let intersection = frame.intersection(screen)
                let fraction: CGFloat = frame.height > 0
                    ? max(0, min(1, intersection.height / frame.height))
                    : 0

                Color.clear.preference(
                    key: MomentVisibilityPreference.self,
                    value: [momentId: fraction]
                )
            }
        )
    }
}

extension View {
    func feedMomentVisibility(momentId: String) -> some View {
        modifier(FeedMomentVisibilityReporter(momentId: momentId))
    }
}
