import SwiftUI
import Combine

/// Elige un único vídeo activo en el feed según la fracción visible de cada post.
@MainActor
final class FeedVisibilityCoordinator: ObservableObject {
    static let shared = FeedVisibilityCoordinator()

    @Published private(set) var activeVideoMomentId: String?
    /// El siguiente vídeo que entra en viewport: se monta el player sin reproducir.
    @Published private(set) var warmingVideoMomentId: String?

    /// Snapshot actual (ids de momento / consumer). Lo usan listeners del feed.
    private(set) var visibilitySnapshot: [String: CGFloat] = [:]

    private let playThreshold: CGFloat = 0.32
    private let warmThreshold: CGFloat = 0.16
    /// Ignora micro-cambios de fracción (evita pickWinner cada frame).
    private let reportEpsilon: CGFloat = 0.05

    private init() {}

    func update(all values: [String: CGFloat]) {
        applyVisibility(values, allowEmpty: false)
    }

    /// Snapshot ya transformado (p. ej. perfil fuerza el post abierto a 1.0).
    func applyTransformedSnapshot(_ values: [String: CGFloat]) {
        applyVisibility(values, allowEmpty: true)
    }

    func report(momentId: String, fraction: CGFloat) {
        let previous = visibilitySnapshot[momentId] ?? -1
        guard abs(previous - fraction) >= reportEpsilon || (fraction == 0) != (previous == 0) else { return }
        visibilitySnapshot[momentId] = fraction
        pickWinner()
    }

    func clear(momentId: String) {
        visibilitySnapshot.removeValue(forKey: momentId)
        pickWinner()
    }

    /// Fija un único vídeo activo (p. ej. durante hero → detalle).
    func pinActiveVideo(momentId: String) {
        visibilitySnapshot = [momentId: 1.0]
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

    private func applyVisibility(_ values: [String: CGFloat], allowEmpty: Bool) {
        if values.isEmpty && !allowEmpty { return }

        var changed = false
        for (id, fraction) in values {
            let previous = visibilitySnapshot[id] ?? -1
            if abs(previous - fraction) >= reportEpsilon || (fraction == 0) != (previous == 0) {
                visibilitySnapshot[id] = fraction
                changed = true
            }
        }
        let incoming = Set(values.keys)
        for stale in visibilitySnapshot.keys where !incoming.contains(stale) {
            visibilitySnapshot.removeValue(forKey: stale)
            changed = true
        }
        guard changed else { return }
        pickWinner()
    }

    private func pickWinner() {
        let signpostID = PerformanceSignposts.makeID()
        PerformanceSignposts.begin("FeedPickActiveVideo", id: signpostID)

        let ranked = visibilitySnapshot.sorted { $0.value > $1.value }
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

struct FeedMomentVisibilityReporter: ViewModifier {
    let momentId: String

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                let frame = proxy.frame(in: .global)
                let screen = CGRect(origin: .zero, size: UIApplication.shared.activeWindowSize)
                let intersection = frame.intersection(screen)
                guard frame.height > 0 else { return 0 }
                return max(0, min(1, intersection.height / frame.height))
            } action: { _, fraction in
                FeedVisibilityCoordinator.shared.report(momentId: momentId, fraction: fraction)
            }
            .onDisappear {
                FeedVisibilityCoordinator.shared.clear(momentId: momentId)
            }
    }
}

extension View {
    func feedMomentVisibility(momentId: String) -> some View {
        modifier(FeedMomentVisibilityReporter(momentId: momentId))
    }

    /// Recalcula listeners con el snapshot actual (la fracción la reporta cada card).
    func feedScrollVisibilityAnchor(
        transform: @escaping ([String: CGFloat]) -> [String: CGFloat] = { $0 },
        onSnapshot: (([String: CGFloat]) -> Void)? = nil
    ) -> some View {
        self
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, _ in
                let coordinator = FeedVisibilityCoordinator.shared
                let snapshot = transform(coordinator.visibilitySnapshot)
                if snapshot != coordinator.visibilitySnapshot {
                    coordinator.applyTransformedSnapshot(snapshot)
                }
                onSnapshot?(snapshot)
            }
    }
}
