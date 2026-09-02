import SwiftUI
import Combine

/// Elige un único vídeo activo en el feed según la fracción visible de cada post.
@MainActor
final class FeedVisibilityCoordinator: ObservableObject {
    static let shared = FeedVisibilityCoordinator()

    @Published private(set) var activeVideoMomentId: String?
    /// El siguiente vídeo que entra en viewport: se monta el player sin reproducir.
    @Published private(set) var warmingVideoMomentId: String?

    private var visibilityByMomentId: [String: CGFloat] = [:]
    private let playThreshold: CGFloat = 0.32
    private let warmThreshold: CGFloat = 0.16
    /// Ignora micro-cambios de GeometryReader durante el scroll (evita pickWinner cada frame).
    private let reportEpsilon: CGFloat = 0.05

    private init() {}

    func update(all values: [String: CGFloat]) {
        // Snapshot vacío: PreferenceKey en transiciones (p. ej. Reels cover), no “nada visible”.
        guard !values.isEmpty else { return }

        var changed = false
        for (id, fraction) in values {
            let previous = visibilityByMomentId[id] ?? -1
            if abs(previous - fraction) >= reportEpsilon || (fraction == 0) != (previous == 0) {
                visibilityByMomentId[id] = fraction
                changed = true
            }
        }
        // Quitar ids que ya no reportan (scrolleados fuera).
        let incoming = Set(values.keys)
        for stale in visibilityByMomentId.keys where !incoming.contains(stale) {
            visibilityByMomentId.removeValue(forKey: stale)
            changed = true
        }
        guard changed else { return }
        pickWinner()
    }

    func report(momentId: String, fraction: CGFloat) {
        let previous = visibilityByMomentId[momentId] ?? -1
        guard abs(previous - fraction) >= reportEpsilon || (fraction == 0) != (previous == 0) else { return }
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
        warmingVideoMomentId = nil
    }

    func isActive(momentId: String?) -> Bool {
        guard let momentId, let activeVideoMomentId else { return false }
        return activeVideoMomentId == momentId
    }

    func isWarming(momentId: String?) -> Bool {
        guard let momentId, let warmingVideoMomentId else { return false }
        return warmingVideoMomentId == momentId
    }

    private func pickWinner() {
        let signpostID = PerformanceSignposts.makeID()
        PerformanceSignposts.begin("FeedPickActiveVideo", id: signpostID)

        let ranked = visibilityByMomentId.sorted { $0.value > $1.value }
        let playCandidate = ranked.first { $0.value >= playThreshold }?.key
        if let playCandidate, activeVideoMomentId != playCandidate {
            activeVideoMomentId = playCandidate
            PerformanceSignposts.event("FeedActiveVideoChanged")
        }

        let warmCandidate = ranked.first {
            $0.value >= warmThreshold && $0.key != activeVideoMomentId
        }?.key
        if warmingVideoMomentId != warmCandidate {
            warmingVideoMomentId = warmCandidate
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
                let screen = CGRect(origin: .zero, size: UIApplication.shared.activeWindowSize)
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
