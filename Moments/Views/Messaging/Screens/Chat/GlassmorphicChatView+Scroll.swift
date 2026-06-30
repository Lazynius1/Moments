import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    func loadOlderHistoryIfNeeded() {
        guard hasCompletedInitialScroll,
              !viewModel.isLoadingMore,
              !viewModel.isLoadingOlderHistory,
              viewModel.canLoadMore,
              !viewModel.messages.isEmpty else { return }
        viewModel.loadMoreMessages()
    }

    // MARK: - UIKit list scroll orchestration

    enum ListBottomSnapReason {
        case keyboard
        case composerResized
        case userRequested
        case incomingWhilePinned
    }

    func configureListInitialScrollPolicy() {
        // routeInitialScrollInList es el único conductor del scroll inicial (highlight > no leído > fondo).
        // No se restaura posición guardada. `.deferred` evita que el controller haga un scroll al fondo
        // que pelee con el salto al primer no leído.
        chatListController.initialScrollPolicy = .deferred
    }

    func routeInitialScrollInList() {
        guard !viewModel.chatRenderRows.isEmpty else { return }

        reloadNotificationOpenIntent()
        reconcileScrollStateForCurrentConversation()
        initializeUnreadDividerIfNeeded()

        if let intent = notificationOpenIntent, !intent.highlightMessageIds.isEmpty {
            pendingInitialScrollRoute = true
            scheduleSingleHighlightScrollInList()
            return
        }

        if preferredReactionHighlightMessageId() != nil {
            pendingInitialScrollRoute = true
            scheduleSingleHighlightScrollInList()
            return
        }

        if !hasCompletedInitialScroll {
            pendingInitialScrollRoute = true
            refreshFrozenScrollTargetForReactionHighlight()
            if frozenInitialScrollTarget == nil || shouldOpenAtBottom() {
                frozenInitialScrollTarget = resolveInitialScrollTarget()
            }
            guard let target = frozenInitialScrollTarget else { return }

            if target.pinsToBottom {
                scheduleInitialScrollToBottom()
            } else {
                scrollToTargetInList(target, animated: false)
                finishInitialOpenInList(pinsToBottom: false)
            }
            pendingInitialScrollRoute = false
            return
        }

        guard !didReapplyFrozenScrollPosition else { return }
        didReapplyFrozenScrollPosition = true

        // No se restaura posición guardada. Si estábamos pegados al fondo, mantenerlo
        // (p.ej. tras la transición caché→live). Si el usuario está scrolleado arriba a
        // media conversación, no tocamos su posición: el prepend del controller la preserva.
        if isPinnedToBottom || shouldOpenAtBottom() {
            chatListController.forceScrollToBottom(animated: false)
        }
    }

    func scrollToTargetInList(_ target: ChatScrollTarget, animated: Bool) {
        switch target {
        case .bottom:
            chatListController.forceScrollToBottom(animated: animated)
        case .firstUnread(let messageId):
            let rowId = messageRowId(containingMessageId: messageId) ?? messageId
            isPinnedToBottom = false
            listIsAtBottom = false
            chatListController.scrollToRow(id: rowId, at: .top, animated: animated)
        case .highlightedMessage(let messageId):
            let rowId = messageRowId(containingMessageId: messageId) ?? messageId
            isPinnedToBottom = false
            listIsAtBottom = false
            chatListController.scrollToRow(id: rowId, at: .centeredVertically, animated: animated)
        }
    }

    /// Scroll al fondo tras el layout (estilo Telegram `scrollToEndOfHistory` + reintentos).
    func scheduleInitialScrollToBottom() {
        initialScrollTask?.cancel()
        initialScrollTask = Task { @MainActor in
            defer { initialScrollTask = nil }

            // forceScrollToBottom ya estabiliza el self-sizing internamente (scroll→invalidate→
            // layout hasta que el contentSize deje de moverse). Aquí solo se reintenta por si las
            // filas todavía no llegaron al controller (carga async, no un problema de medición).
            let delays: [UInt64] = [0, 80_000_000, 200_000_000]
            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !viewModel.chatRenderRows.isEmpty else { continue }
                chatListController.forceScrollToBottom(animated: false)
            }

            finishInitialOpenInList(pinsToBottom: true)
        }
    }

    func finishInitialOpenInList(pinsToBottom: Bool) {
        hasCompletedInitialScroll = true
        pendingInitialScrollRoute = false
        isPinnedToBottom = pinsToBottom
        listIsAtBottom = pinsToBottom
        if pinsToBottom {
            clearUnreadDividerAndMarkReadIfNeeded()
        }
        frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
        viewModel.prefetchUnresolvedMediaIfNeeded()
        processPendingReactionHighlightsInList()
        processPendingBuzzInList()
        scheduleNotificationBuzzRetriesInList()
        clearNotificationOpenIntentIfFinished()
    }

    func scrollToBottomFromUserAction(animated: Bool = true) {
        listBottomSnapTask?.cancel()
        guard !viewModel.chatRenderRows.isEmpty else { return }
        pendingIncomingMessages = 0
        listIsAtBottom = false
        isPinnedToBottom = false
        chatListController.forceScrollToBottom(animated: animated && !reduceMotion)
    }

    func scheduleListBottomSnap(reason: ListBottomSnapReason, animated: Bool? = nil) {
        if reason == .userRequested {
            scrollToBottomFromUserAction(animated: animated ?? true)
            return
        }

        listBottomSnapTask?.cancel()
        listBottomSnapTask = Task { @MainActor in
            defer { listBottomSnapTask = nil }

            let delayNs: UInt64 = switch reason {
            case .keyboard:
                UInt64(keyboardScrollCoordinator.animationDuration * 1_000_000_000) + 16_000_000
            case .composerResized:
                50_000_000
            case .userRequested, .incomingWhilePinned:
                0
            }

            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
            }

            guard !viewModel.chatRenderRows.isEmpty, isPinnedToBottom else { return }
            let shouldAnimate = (animated ?? (reason == .keyboard || reason == .composerResized)) && !reduceMotion
            chatListController.forceScrollToBottom(animated: shouldAnimate)
        }
    }

    func handleComposerHeightChangeInList(_ height: CGFloat) {
        guard hasCompletedInitialScroll, isPinnedToBottom else {
            lastComposerHeight = height
            return
        }
        guard abs(height - lastComposerHeight) > 0.5 else { return }
        lastComposerHeight = height
        composerSnapTask?.cancel()
        composerSnapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            scheduleListBottomSnap(reason: .composerResized)
        }
    }

    func handleLastMessageScrollChangeInList(oldValue: String?, lastMessageId: String?) {
        guard let lastMessageId, hasCompletedInitialScroll else { return }
        guard oldValue != nil else { return }
        let isLastMessageMine = viewModel.messages.last?.senderId == viewModel.currentUserId

        if isLastMessageMine {
            if !isPinnedToBottom {
                scheduleListBottomSnap(reason: .userRequested, animated: true)
            }
        } else if !viewModel.isLoadingMore, !isPinnedToBottom {
            if unreadDividerMessageId == nil {
                unreadDividerMessageId = lastMessageId
            }
            pendingIncomingMessages += 1
        }
    }

    func scheduleSingleHighlightScrollInList() {
        reloadNotificationOpenIntent()
        guard let ids = notificationOpenIntent?.highlightMessageIds, ids.count == 1, let messageId = ids.first else { return }
        guard highlightScrollTask == nil else { return }

        highlightScrollTask = Task { @MainActor in
            defer { highlightScrollTask = nil }

            let delays: [UInt64] = [0, 200_000_000, 600_000_000, 1_500_000_000, 3_000_000_000]
            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                reloadNotificationOpenIntent()
                guard notificationOpenIntent?.highlightMessageIds.contains(messageId) == true else { return }

                if messageIsReadyForScroll(messageId) {
                    scrollToTargetInList(.highlightedMessage(messageId: messageId), animated: !reduceMotion)
                    highlightMessages([messageId], scroll: false)
                    finishInitialOpenInList(pinsToBottom: false)
                    if let conversationId = viewModel.conversation.id {
                        ChatNavigationIntentStore.clearHighlights(for: conversationId)
                        reloadNotificationOpenIntent()
                        clearNotificationOpenIntentIfFinished()
                    }
                    return
                }

                if !viewModel.messages.contains(where: { $0.id == messageId }) {
                    viewModel.loadMessageForHighlightIfNeeded(messageId: messageId)
                    if viewModel.canLoadMore, !viewModel.isLoadingMore {
                        loadOlderHistoryIfNeeded()
                    }
                }
            }
        }
    }

    func processPendingReactionHighlightsInList() {
        if case .highlightedMessage(let messageId) = frozenInitialScrollTarget {
            var ids = pendingReactionHighlightIds
            ids.insert(messageId)
            if let stored = notificationOpenIntent?.highlightMessageIds {
                ids.formUnion(stored)
            }
            pendingReactionHighlightIds.removeAll()
            if !ids.isEmpty {
                highlightMessages(ids, duration: 1.2, scroll: false)
            }
            if let conversationId = viewModel.conversation.id {
                ChatNavigationIntentStore.clearHighlights(for: conversationId)
                reloadNotificationOpenIntent()
                clearNotificationOpenIntentIfFinished()
            }
            return
        }

        var ids = pendingReactionHighlightIds
        if let stored = notificationOpenIntent?.highlightMessageIds {
            ids.formUnion(stored)
        }
        guard !ids.isEmpty else { return }
        pendingReactionHighlightIds.removeAll()
        let shouldScroll = hasExplicitReactionHighlightIntent()
        if shouldScroll, let firstId = ids.first {
            scrollToTargetInList(.highlightedMessage(messageId: firstId), animated: !reduceMotion)
        }
        highlightMessages(ids, scroll: false)

        if let conversationId = viewModel.conversation.id {
            ChatNavigationIntentStore.clearHighlights(for: conversationId)
            reloadNotificationOpenIntent()
            clearNotificationOpenIntentIfFinished()
        }
    }

    func processPendingBuzzInList() {
        reloadNotificationOpenIntent()
        guard let conversationId = viewModel.conversation.id else { return }
        guard let event = resolvePendingBuzzEventForReplay() else { return }

        guard event.senderId != viewModel.currentUserId else {
            markBuzzEventProcessed(event)
            clearNotificationOpenIntentIfFinished()
            return
        }

        guard !ChatBuzzProcessedStore.isProcessed(eventId: event.id, conversationId: conversationId) else {
            clearNotificationOpenIntentIfFinished()
            return
        }

        markBuzzEventProcessed(event)

        let message = String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz toast"),
            otherParticipantDisplayName
        )
        triggerBuzzEffect(text: message, isLocal: false, showsToast: true)

        ChatNavigationIntentStore.clearBuzz(for: conversationId)
        reloadNotificationOpenIntent()
        clearNotificationOpenIntentIfFinished()
    }

    func scheduleNotificationBuzzRetriesInList() {
        guard pendingBuzzReplayNeedsRetry() else { return }

        Task { @MainActor in
            let retryDelays: [UInt64] = [250_000_000, 700_000_000, 1_500_000_000, 2_500_000_000, 4_000_000_000, 5_000_000_000]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard pendingBuzzReplayNeedsRetry() else { return }
                reloadNotificationOpenIntent()
                processPendingBuzzInList()
            }
        }
    }

    func scheduleSearchHighlightScrollInList(to messageId: String) {
        searchHighlightScrollTask?.cancel()
        guard !messageId.isEmpty else { return }

        searchHighlightScrollTask = Task { @MainActor in
            defer { searchHighlightScrollTask = nil }
            let delays: [UInt64] = [0, 120_000_000, 350_000_000, 800_000_000, 1_600_000_000, 3_000_000_000]
            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard pendingSearchHighlightId == messageId else { return }

                if viewModel.messages.contains(where: { $0.id == messageId }) {
                    isPinnedToBottom = false
                    listIsAtBottom = false
                    let rowId = messageRowId(containingMessageId: messageId) ?? messageId
                    chatListController.scrollToRow(id: rowId, at: .centeredVertically, animated: !reduceMotion)
                    highlightMessages([messageId], scroll: false)
                    pendingSearchHighlightId = nil
                    return
                }
                viewModel.loadMessageForHighlightIfNeeded(messageId: messageId)
            }
            if pendingSearchHighlightId == messageId {
                pendingSearchHighlightId = nil
            }
        }
    }


    var activeSearchHighlightTerm: String {
        isSearchVisible ? searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    var allowsVerticalScrolling: Bool {
        hasCompletedInitialScroll && scrollContentExceedsViewport
    }

    /// Evita «Modifying state during view update» al puente UIKit → SwiftUI.
    func deferListStateUpdate(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }

    var scrollToBottomAccentColor: Color {
        colorScheme == .dark ? Color(hex: "8EB6CE") : Color(hex: "3F6F8F")
    }

    var scrollToBottomBadgeTextColor: Color {
        colorScheme == .dark ? Color(hex: "071015") : .white
    }

}

