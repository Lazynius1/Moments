import SwiftUI

private struct StoryDeckGestureGateKey: EnvironmentKey {
    static let defaultValue: StoryDeckGestureGate? = nil
}

extension EnvironmentValues {
    var storyDeckGestureGate: StoryDeckGestureGate? {
        get { self[StoryDeckGestureGateKey.self] }
        set { self[StoryDeckGestureGateKey.self] = newValue }
    }
}

/// Coordina cuándo el Deck Pass y la navegación por tap deben ceder a stickers interactivos.
@MainActor
final class StoryDeckGestureGate: ObservableObject {
    @Published private(set) var isStickerInteractionActive = false

    var suppressDeckNavigation: Bool { isStickerInteractionActive }
    var suppressStoryNavigationGestures: Bool { isStickerInteractionActive }

    func setStickerInteractionActive(_ active: Bool) {
        guard isStickerInteractionActive != active else { return }
        isStickerInteractionActive = active
    }
}
