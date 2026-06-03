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
    @Published private(set) var activeSuppressionScopes: [String: StoryGestureSuppressionScope] = [:]
    @Published private(set) var interactionRegions: [StoryGestureRegion] = []

    var suppressionScope: StoryGestureSuppressionScope {
        activeSuppressionScopes.values.max() ?? .allowAll
    }

    var suppressDeckNavigation: Bool { suppressionScope >= .suppressDeck }
    var suppressStoryNavigationGestures: Bool { suppressionScope >= .suppressStoryNavigation }
    var suppressViewerGestures: Bool { suppressionScope >= .suppressViewerGestures }

    func setSuppressionScope(_ scope: StoryGestureSuppressionScope, for sourceID: String) {
        if scope == .allowAll {
            if activeSuppressionScopes.removeValue(forKey: sourceID) != nil {
                objectWillChange.send()
            }
            return
        }

        if activeSuppressionScopes[sourceID] != scope {
            activeSuppressionScopes[sourceID] = scope
        }
    }

    func clearSuppression(for sourceID: String) {
        setSuppressionScope(.allowAll, for: sourceID)
    }

    func setInteractionRegions(_ regions: [StoryGestureRegion]) {
        if interactionRegions != regions {
            interactionRegions = regions
        }
    }

    func setStickerInteractionActive(_ active: Bool) {
        setSuppressionScope(active ? .suppressViewerGestures : .allowAll, for: "legacy.sticker")
    }
}
