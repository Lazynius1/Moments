import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    var shouldShowHistoryLoadNotice: Bool {
        switch viewModel.historyLoadNotice {
        case .hidden:
            return false
        case .offline, .error:
            return hasCompletedInitialScroll && !isPinnedToBottom
        }
    }

    var historyLoadNoticeTextKey: LocalizedStringKey {
        switch viewModel.historyLoadNotice {
        case .hidden:
            return "common.error"
        case .offline:
            return "network.offline.title"
        case .error:
            return "common.error"
        }
    }

    var historyLoadNoticeRetryTextKey: LocalizedStringKey? {
        switch viewModel.historyLoadNotice {
        case .offline, .error:
            return "messaging.retry"
        case .hidden:
            return nil
        }
    }

    func retryHistoryLoadFromNotice() {
        viewModel.clearHistoryLoadNotice()
        loadOlderHistoryIfNeeded()
    }

    // ✅ Lista de mensajes — orden cronológico + anclaje inferior nativo (sin invertir LazyVStack)
    var messagesListSection: some View {
        invertedMessagesList
            .overlay(alignment: .top) {
                if shouldShowHistoryLoadNotice {
                    ChatHistoryLoadingIndicator(
                        adaptiveColors: adaptiveColors,
                        textKey: historyLoadNoticeTextKey,
                        showsProgress: false,
                        retryTextKey: historyLoadNoticeRetryTextKey,
                        onTap: historyLoadNoticeRetryTextKey == nil ? nil : retryHistoryLoadFromNotice
                    )
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : MotionPolicy.Spring.header,
                value: viewModel.historyLoadNotice
            )
    }

    var listRows: [ChatRenderRow] {
        var rows = viewModel.chatRenderRows
        let introContext = pendingChatContext ?? conversationIntroContext
        let shouldShowConversationIntro = isPendingChat || (!viewModel.canLoadMore && (hasCompletedInitialScroll || rows.isEmpty))
        if shouldShowConversationIntro {
            if !isPendingChat {
                rows.insert(.historyStart, at: 0)
            }
            if pendingChatContext != nil,
               pendingChatContext?.status != .outgoingRequestDraft,
               pendingChatContext?.status != .outgoingRequestBlocked {
                rows.insert(.requestDisclaimer(pendingChatContext), at: 0)
            }
            rows.insert(.conversationIntro(introContext), at: 0)
            if let pendingMessage = pendingChatTimelineMessage {
                rows.insert(.pendingRequestMessage(pendingMessage), at: min(3, rows.count))
            }
        }
        if !viewModel.typingUsers.isEmpty {
            rows.append(.typing)
        }
        return rows
    }

    var invertedMessagesList: some View {
        chatMessageListWithReconfigure
    }

    var listUpdateTransaction: ChatListUpdateTransaction {
        ChatListUpdateTransaction(
            kind: viewModel.chatTimelineMutation.kind,
            rows: listRows,
            anchorRowId: viewModel.chatTimelineMutation.anchorMessageId
                .flatMap { messageRowId(containingMessageId: $0) },
            reason: viewModel.chatTimelineMutation.reason
        )
    }

    var chatMessageListWithReconfigure: some View {
        chatMessageListWithNotifications
            .onChange(of: searchQuery) { _, _ in chatListController.reconfigureVisible() }
            .onChange(of: currentSearchMatchIndex) { _, _ in chatListController.reconfigureVisible() }
            .onChange(of: flashingMessageIds) { _, _ in chatListController.reconfigureVisible() }
            .onChange(of: messageMenuSelection) { _, _ in chatListController.reconfigureVisible() }
            .onChange(of: viewModel.uploadProgress) { old, new in
                let changed = changedProgressKeys(old, new)
                if !changed.isEmpty { chatListController.reconfigure(messageIds: changed) }
            }
            .onChange(of: viewModel.downloadProgress) { old, new in
                let changed = changedProgressKeys(old, new)
                if !changed.isEmpty {
                    ChatScrollDebug.log("downloadProgress onChange changed=\(changed.count) pinned=\(isPinnedToBottom) loadingOlder=\(viewModel.isLoadingOlderHistory)")
                    if !viewModel.isLoadingOlderHistory {
                        chatListController.reconfigure(messageIds: changed)
                    }
                }
            }
    }

    var chatMessageListWithNotifications: some View {
        chatMessageListWithScrollEvents
            .onReceive(NotificationCenter.default.publisher(for: .chatMessageReactionHighlight)) { notification in
                guard
                    let conversationId = notification.userInfo?["conversationId"] as? String,
                    conversationId == viewModel.conversation.id,
                    let messageId = notification.userInfo?["messageId"] as? String
                else { return }
                reloadNotificationOpenIntent()
                let hasNavigationIntent = notificationOpenIntent?.highlightMessageIds.contains(messageId) == true
                let isLiveReaction = notification.userInfo?["isLiveReaction"] as? Bool ?? false
                guard hasNavigationIntent || isLiveReaction else { return }
                if hasNavigationIntent {
                    scheduleSingleHighlightScrollInList()
                } else {
                    highlightMessages([messageId], scroll: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatBuzzHighlight)) { notification in
                guard
                    let conversationId = notification.userInfo?["conversationId"] as? String,
                    conversationId == viewModel.conversation.id
                else { return }
                reloadNotificationOpenIntent()
                if hasCompletedInitialScroll {
                    processPendingBuzzInList()
                }
            }
    }

    var chatMessageListWithScrollEvents: some View {
        chatMessageListWithLifecycle
            .onChange(of: viewModel.messages.last?.id) { oldValue, lastMessageId in
                handleLastMessageScrollChangeInList(oldValue: oldValue, lastMessageId: lastMessageId)
                guard hasCompletedInitialScroll,
                      isPinnedToBottom,
                      let lastMessageId,
                      oldValue != nil,
                      oldValue != lastMessageId else { return }
                scheduleListBottomSnap(reason: .incomingWhilePinned)
            }
            .onChange(of: viewModel.unreadIncomingCount) { _, count in
                deferListStateUpdate {
                    if count == 0 {
                        refreshPendingIncomingState()
                        if !hasCompletedInitialScroll {
                            reconcileScrollStateForCurrentConversation()
                            routeInitialScrollInList()
                        }
                    } else if hasCompletedInitialScroll {
                        refreshPendingIncomingState()
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                deferListStateUpdate {
                    guard hasCompletedInitialScroll, !isPinnedToBottom else { return }
                    refreshPendingIncomingState()
                }
            }
            .onChange(of: pendingSearchTargetId) { _, targetId in
                guard let targetId else { return }
                pendingSearchTargetId = nil
                pendingSearchHighlightId = targetId
                scheduleSearchHighlightScrollInList(to: targetId)
            }
            .onChange(of: pendingReplyScrollMessageId) { _, messageId in
                guard let messageId else { return }
                pendingReplyScrollMessageId = nil
                pendingSearchHighlightId = messageId
                scheduleSearchHighlightScrollInList(to: messageId)
            }
            .onChange(of: pendingScrollMessageId) { _, messageId in
                guard let messageId else { return }
                pendingScrollMessageId = nil
                pendingSearchHighlightId = messageId
                scheduleSearchHighlightScrollInList(to: messageId)
            }
            .onChange(of: pendingPinnedBottomSnap) { _, shouldSnap in
                guard shouldSnap else { return }
                pendingPinnedBottomSnap = false
                scheduleListBottomSnap(reason: .composerResized)
            }
            .onChange(of: keyboardScrollCoordinator.keyboardHeight) { oldHeight, newHeight in
                guard hasCompletedInitialScroll, isPinnedToBottom, !isSearchVisible else { return }
                guard newHeight > oldHeight, newHeight > 1 else { return }
                scheduleListBottomSnap(reason: .keyboard)
            }
            .onChange(of: viewModel.buzzEvents.map(\.id)) { _, _ in
                guard hasCompletedInitialScroll else { return }
                processPendingBuzzInList()
                scheduleNotificationBuzzRetriesInList()
            }
            .onChange(of: pendingReactionHighlightIds) { _, ids in
                guard hasCompletedInitialScroll, !ids.isEmpty else { return }
                processPendingReactionHighlightsInList()
                pendingReactionHighlightIds.removeAll()
            }
            .onChange(of: viewModel.liveReactionOverlays.count) { _, _ in
                guard !hasCompletedInitialScroll else { return }
                guard preferredReactionHighlightMessageId() != nil else { return }
                frozenInitialScrollTarget = nil
                pendingInitialScrollRoute = true
                routeInitialScrollInList()
            }
    }

    var chatMessageListWithLifecycle: some View {
        chatMessageListDecorated
            .onAppear {
                configureListInitialScrollPolicy()
                routeInitialScrollInList()
                processPendingBuzzInList()
                scheduleNotificationBuzzRetriesInList()
            }
            .onChange(of: listIsAtBottom) { _, atBottom in
                deferListStateUpdate {
                    handleListAtBottomChange(atBottom)
                }
            }
            .onChange(of: listRows.map(\.id)) { _, _ in
                deferListStateUpdate {
                    handleListRowsChange()
                }
            }
            .onChange(of: viewModel.messages.isEmpty) { _, isEmpty in
                guard !isEmpty else { return }
                routeInitialScrollInList()
            }
    }

    var chatMessageListDecorated: some View {
        chatMessageListBase
    }

    var chatMessageListBase: some View {
        ChatMessageListView(
            transaction: listUpdateTransaction,
            controller: chatListController,
            isAtBottom: $listIsAtBottom,
            onReachedTop: {
                deferListStateUpdate {
                    ChatScrollDebug.log("onReachedTop fired pinned=\(isPinnedToBottom) loadingOlder=\(viewModel.isLoadingOlderHistory) canLoadMore=\(viewModel.canLoadMore)")
                    loadOlderHistoryIfNeeded()
                }
            },
            composerBottomInset: max(lastComposerHeight, 0),
            isVanishGestureEnabled: hasCompletedInitialScroll && !isSearchVisible,
            isVanishModeActive: viewModel.vanishModeActive,
            onVanishPullReleased: { result in
                handleVanishPullReleased(result)
            },
            onContentExtentChanged: { exceedsViewport in
                deferListStateUpdate {
                    if scrollContentExceedsViewport != exceedsViewport {
                        scrollContentExceedsViewport = exceedsViewport
                    }
                }
            },
            onPrependFinished: {
                ChatScrollDebug.log("onPrependFinished pinned=\(isPinnedToBottom) listAtBottom=\(listIsAtBottom)")
                viewModel.endHistoryScrollRestoration()
            },
            onPrefetchRows: { rows in
                prefetchMediaForRows(rows)
            },
            rowContent: { row in
                chatMessageListRowContent(row)
            }
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    func prefetchMediaForRows(_ rows: [ChatRenderRow]) {
        var messages: [EnhancedMessage] = []
        for row in rows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message):
                messages.append(message)
            case .mediaCluster(let clusterMessages):
                messages.append(contentsOf: clusterMessages)
            }
        }
        guard !messages.isEmpty else { return }
        ChatMediaGalleryPrefetcher.prefetch(messages: messages)
    }

    func changedProgressKeys(_ old: [String: Double], _ new: [String: Double]) -> [String] {
        var keys = Set(old.keys)
        keys.formUnion(new.keys)
        return keys.filter { old[$0] != new[$0] }
    }

    func chatMessageListRowContent(_ row: ChatRenderRow) -> AnyView {
        AnyView(
            chatRenderRow(row, index: 0, proxy: nil)
                .environment(\.chatSearchHighlightTerm, activeSearchHighlightTerm)
                .environment(\.chatSearchActiveMessageId, currentSearchMatchId)
        )
    }

    func handleListAtBottomChange(_ atBottom: Bool) {
        isPinnedToBottom = atBottom
    }

    func handleListRowsChange() {
        scrollContentExceedsViewport = chatListController.contentExceedsViewport
        initializeUnreadDividerIfNeeded()
        if !isPinnedToBottom {
            refreshPendingIncomingState()
        }
        if isSearchVisible, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            syncSearchMatchesFromViewModel()
        }
        if let highlightId = pendingSearchHighlightId,
           messageIsReadyForScroll(highlightId) {
            completeSearchHighlightScroll(to: highlightId)
            return
        }
        if !hasCompletedInitialScroll || pendingInitialScrollRoute {
            routeInitialScrollInList()
        }
    }

    func handleVanishPullReleased(_ result: VanishPullResult) {
        guard result.completed, result.effectivePull > 0 else { return }
        HapticManager.shared.mediumImpact()
        let willActivate = !viewModel.vanishModeActive
        viewModel.toggleVanishMode()
        if willActivate {
            presentVanishTimerPickerIfFirstActivation()
        }
    }

}
