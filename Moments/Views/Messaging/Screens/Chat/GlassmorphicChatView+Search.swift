import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    func toggleChatSearch() {
        isSearchVisible.toggle()
        searchHighlightScrollTask?.cancel()
        searchHighlightScrollTask = nil
        pendingSearchHighlightId = nil
        searchQuery = ""
        viewModel.clearSearch()
        searchMatchIds = []
        currentSearchMatchIndex = 0
        pendingSearchTargetId = nil
        if isSearchVisible {
            isTextFieldFocused = false
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        } else {
            isSearchFieldFocused = false
        }
    }

    /// Re-ancla lista + composer tras quitar el header de búsqueda (evita input desplazado).
    func restoreLayoutAfterClosingSearch() {
        if hasCompletedInitialScroll, isPinnedToBottom {
            pendingPinnedBottomSnap = true
        }
        composerSnapTask?.cancel()
        composerSnapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, !isSearchVisible else { return }
            if hasCompletedInitialScroll, isPinnedToBottom {
                scheduleListBottomSnap(reason: .composerResized)
            }
        }
    }

    func scrollToCurrentSearchMatch() {
        guard let messageId = currentSearchMatchId else { return }
        pendingSearchHighlightId = messageId
        scheduleSearchHighlightScrollInList(to: messageId)
    }

    var currentSearchMatchId: String? {
        guard isSearchVisible,
              currentSearchMatchIndex >= 0,
              currentSearchMatchIndex < searchMatchIds.count else { return nil }
        return searchMatchIds[currentSearchMatchIndex]
    }

    func syncSearchMatchesFromViewModel() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchMatchIds = []
            currentSearchMatchIndex = 0
            return
        }

        searchMatchIds = viewModel.searchResults

        guard !searchMatchIds.isEmpty else {
            currentSearchMatchIndex = 0
            return
        }

        if currentSearchMatchIndex >= searchMatchIds.count {
            currentSearchMatchIndex = max(searchMatchIds.count - 1, 0)
        }
    }

    func moveSearchSelection(by step: Int) {
        guard step < 0, !searchMatchIds.isEmpty else { return }
        let count = searchMatchIds.count
        currentSearchMatchIndex = (currentSearchMatchIndex + step + count) % count
        scrollToCurrentSearchMatch()
    }

    func advanceSearchSelection() {
        let canScrollToBottom = !isPinnedToBottom || chatListController.distanceFromBottom > 16

        if searchMatchIds.isEmpty {
            if canScrollToBottom {
                scrollToBottomFromUserAction(animated: true)
            }
            return
        }

        let isLastMatch = currentSearchMatchIndex >= searchMatchIds.count - 1
        if isLastMatch {
            if canScrollToBottom {
                scrollToBottomFromUserAction(animated: true)
            }
            return
        }
        currentSearchMatchIndex += 1
        scrollToCurrentSearchMatch()
    }

}
