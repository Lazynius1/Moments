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

    func timelineScrollCommand(for target: ChatScrollTarget, animated: Bool) -> ChatListScrollCommand? {
        switch target {
        case .bottom:
            return .bottom(animated: animated)
        case .firstUnread(let messageId):
            guard messageRowId(containingMessageId: messageId) != nil else {
                ChatScrollDebug.log("timeline command firstUnread — row not ready for \(messageId)")
                return nil
            }
            return .firstUnread(messageId: messageId, animated: animated)
        case .highlightedMessage(let messageId):
            return .highlight(messageId: messageId, animated: animated)
        }
    }

    func routeInitialScrollInList() {
        ChatScrollDebug.log("routeInitialScrollInList completed=\(hasCompletedInitialScroll) pinned=\(isPinnedToBottom) pendingHighlight=\(pendingSearchHighlightId != nil) rows=\(viewModel.chatRenderRows.count)")
        guard !viewModel.chatRenderRows.isEmpty else { return }

        if let highlightId = pendingSearchHighlightId, !highlightId.isEmpty {
            scheduleSearchHighlightScrollInList(to: highlightId)
            return
        }

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

        if pendingSearchHighlightId != nil {
            ChatScrollDebug.log("routeInitialScrollInList skipped bottom snap — pending highlight")
            return
        }

        // No se restaura posición guardada. Si estábamos pegados al fondo, mantenerlo
        // (p.ej. tras la transición caché→live). Si el usuario está scrolleado arriba a
        // media conversación, no tocamos su posición: el prepend del controller la preserva.
        if isPinnedToBottom || shouldOpenAtBottom() {
            ChatScrollDebug.log("routeInitialScrollInList issuing bottom command")
            chatListController.perform(.bottom(animated: false))
        }
    }

    func scrollToTargetInList(_ target: ChatScrollTarget, animated: Bool) {
        guard let command = timelineScrollCommand(for: target, animated: animated) else { return }
        ChatScrollDebug.log("scrollToTargetInList target=\(String(describing: target)) animated=\(animated)")
        if target.pinsToBottom {
            pendingIncomingMessages = 0
        } else {
            isPinnedToBottom = false
            listIsAtBottom = false
        }
        chatListController.perform(command)
    }

    /// Scroll al fondo tras el layout con reintentos.
    func scheduleInitialScrollToBottom() {
        guard pendingSearchHighlightId == nil else {
            ChatScrollDebug.log("scheduleInitialScrollToBottom skipped — pending highlight")
            return
        }
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
                chatListController.perform(.bottom(animated: false))
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
            frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
        }
        viewModel.prefetchUnresolvedMediaIfNeeded()
        processPendingReactionHighlightsInList()
        processPendingBuzzInList()
        scheduleNotificationBuzzRetriesInList()
        clearNotificationOpenIntentIfFinished()
    }

    func scrollToBottomFromUserAction(animated: Bool = true) {
        listBottomSnapTask?.cancel()
        searchHighlightScrollTask?.cancel()
        pendingSearchHighlightId = nil
        chatListController.clearNavigationTarget()
        guard !viewModel.chatRenderRows.isEmpty else { return }
        pendingIncomingMessages = 0
        listIsAtBottom = false
        isPinnedToBottom = false
        chatListController.forceScrollToBottomIgnoringNavigation(animated: animated && !reduceMotion)
    }

    func scheduleListBottomSnap(reason: ListBottomSnapReason, animated: Bool? = nil) {
        ChatScrollDebug.log("scheduleListBottomSnap reason=\(reason) pinned=\(isPinnedToBottom) pendingHighlight=\(pendingSearchHighlightId != nil)")
        if reason != .userRequested, pendingSearchHighlightId != nil {
            ChatScrollDebug.log("scheduleListBottomSnap(\(reason)) blocked — pending highlight")
            return
        }
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
            chatListController.perform(.bottom(animated: shouldAnimate))
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
            dismissUnreadDividerOnUserReply()
            if !isPinnedToBottom {
                scheduleListBottomSnap(reason: .userRequested, animated: true)
            }
        } else if !viewModel.isLoadingMore, !isPinnedToBottom {
            if unreadDividerMessageId == nil {
                unreadDividerMessageId = lastMessageId
            }
            refreshPendingIncomingState()
        }
    }

    func scheduleSingleHighlightScrollInList() {
        reloadNotificationOpenIntent()
        guard let ids = notificationOpenIntent?.highlightMessageIds, ids.count == 1, let messageId = ids.first else { return }
        guard highlightScrollTask == nil else { return }

        highlightScrollTask = Task { @MainActor in
            defer { highlightScrollTask = nil }

            isPinnedToBottom = false
            listIsAtBottom = false
            didReapplyFrozenScrollPosition = true
            frozenInitialScrollTarget = .highlightedMessage(messageId: messageId)
            ChatScrollDebug.log("single highlight nav messageId=\(messageId)")

            if !viewModel.messages.contains(where: { $0.id == messageId }) {
                let loaded = await viewModel.navigateToMessage(messageId: messageId)
                guard loaded, !Task.isCancelled else { return }
            }
            guard !Task.isCancelled else { return }
            reloadNotificationOpenIntent()
            guard notificationOpenIntent?.highlightMessageIds.contains(messageId) == true else { return }
            if messageIsReadyForScroll(messageId) {
                completeSearchHighlightScroll(to: messageId)
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
        initialScrollTask?.cancel()
        listBottomSnapTask?.cancel()
        composerSnapTask?.cancel()
        guard !messageId.isEmpty else { return }

        ChatScrollDebug.log("scheduleSearchHighlightScroll → messageId=\(messageId)")

        isPinnedToBottom = false
        listIsAtBottom = false
        didReapplyFrozenScrollPosition = true
        hasCompletedInitialScroll = true
        frozenInitialScrollTarget = .highlightedMessage(messageId: messageId)

        searchHighlightScrollTask = Task { @MainActor in
            defer { searchHighlightScrollTask = nil }

            let alreadyLoaded = viewModel.messages.contains(where: { $0.id == messageId })
            ChatScrollDebug.log("message in viewModel: \(alreadyLoaded) (total=\(viewModel.messages.count))")

            if !alreadyLoaded {
                ChatScrollDebug.log("navigateToMessage starting…")
                let loaded = await viewModel.navigateToMessage(messageId: messageId)
                ChatScrollDebug.log("navigateToMessage finished loaded=\(loaded) messages=\(viewModel.messages.count)")
                if Task.isCancelled { return }
                if !loaded {
                    ChatScrollDebug.log("navigateToMessage FAILED — giving up")
                    pendingSearchHighlightId = nil
                    frozenInitialScrollTarget = nil
                    chatListController.clearNavigationTarget()
                    return
                }
            }

            guard !Task.isCancelled, pendingSearchHighlightId == messageId else { return }
            if messageIsReadyForScroll(messageId) {
                completeSearchHighlightScroll(to: messageId)
            } else {
                scrollToTargetInList(.highlightedMessage(messageId: messageId), animated: false)
            }
        }
    }

    func completeSearchHighlightScroll(to messageId: String) {
        let rowId = messageRowId(containingMessageId: messageId) ?? messageId
        ChatScrollDebug.log("completeSearchHighlightScroll messageId=\(messageId) rowId=\(rowId)")
        // Sin animación: un apply de filas a mitad de la animación la cancela sin que llegue
        // scrollViewDidEndScrollingAnimation, dejando la cola de intents y el offset a medias.
        scrollToTargetInList(.highlightedMessage(messageId: messageId), animated: false)
        highlightMessages([messageId], scroll: false)
        finishInitialOpenInList(pinsToBottom: false)
        pendingSearchHighlightId = nil
        frozenInitialScrollTarget = nil
    }

    /// Salto a un mensaje desde fuera del hilo (p. ej. destacados en Conversation Settings).
    func handleJumpToMessageFromOutside(_ messageId: String) {
        guard !messageId.isEmpty else { return }
        ChatScrollDebug.log("handleJumpToMessageFromOutside id=\(messageId)")
        pendingSearchHighlightId = messageId
        scheduleSearchHighlightScrollInList(to: messageId)
    }

    /// Consumido desde el onChange del flag de settings y desde onAppear al volver al chat:
    /// el que llegue primero se lo lleva. El delay deja terminar la animación del pop para que
    /// el scroll no aterrice a mitad de transición.
    func consumeDeferredJumpToMessageIfNeeded() {
        guard let messageId = deferredJumpToMessageId else { return }
        deferredJumpToMessageId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            handleJumpToMessageFromOutside(messageId)
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
