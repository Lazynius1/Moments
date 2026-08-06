import SwiftUI
import FirebaseAuth

private struct ArchivedProfileRoute: Identifiable, Hashable {
    let id: String
}

struct ArchivedConversationsView: View {
    @ObservedObject var viewModel: MessagingViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedConversation: Conversation?

    let onMarkUnread: (Conversation) -> Void
    let onPin: (Conversation) -> Void
    let onMute: (Conversation) -> Void
    let onUnarchive: (Conversation) -> Void
    let onDelete: (Conversation) -> Void

    @State private var conversationMenuSelection: ConversationMenuSelection?
    @State private var conversationRowFrames: [String: CGRect] = [:]
    @Namespace private var profileZoomNamespace
    @State private var profileRoute: ArchivedProfileRoute?

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            GlassmorphicBackground(adaptiveColors: adaptiveColors)

            if viewModel.archivedConversations.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.archivedConversations) { conversation in
                        if let conversationId = conversation.id, !conversationId.isEmpty {
                            conversationRow(conversation)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .chatScrollEdgeEffect()
                .scrollDisabled(conversationMenuSelection != nil)
                .onPreferenceChange(ConversationRowFrameKey.self) { conversationRowFrames = $0 }
            }

            GeometryReader { proxy in
                ConversationContextMenuOverlay(
                    selection: $conversationMenuSelection,
                    containerSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets,
                    colorScheme: colorScheme,
                    onMarkUnread: onMarkUnread,
                    onPin: onPin,
                    onMute: onMute,
                    onArchive: { _ in },
                    onUnarchive: onUnarchive,
                    onDelete: onDelete
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(conversationMenuSelection != nil)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .chatInteractivePopEnabled()
        .momentsFloatingTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ProfileChromeIconButton(
                    systemName: "chevron.left",
                    foregroundColor: adaptiveColors.primary,
                    preset: .navigationBack,
                    action: { dismiss() }
                )
            }
            .chatHideSharedBackgroundIfAvailable()

            ToolbarItem(placement: .principal) {
                Text("messaging.section.archived")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
            }
        }
        .onChange(of: viewModel.archivedConversations.isEmpty) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
        .navigationDestination(item: $profileRoute) { route in
            UserProfileView(userId: route.id)
                .userProfileZoomDestination(userId: route.id, namespace: profileZoomNamespace)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundStyle(adaptiveColors.primary.opacity(0.5))
            Text("messaging.section.archived")
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .momentsEmptyStateAppear()
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        let isMenuSelected = conversationMenuSelection?.conversation.id == conversation.id

        ConversationPressableRow(
            conversation: conversation,
            isMenuSelected: isMenuSelected,
            colorScheme: colorScheme,
            profileZoomNamespace: profileZoomNamespace,
            onOpenProfile: { openConversationProfile(userId: conversation.otherParticipantId) },
            onTap: {
                selectedConversation = conversation
            },
            onLongPress: {
                guard let conversationId = conversation.id,
                      let frame = conversationRowFrames[conversationId],
                      frame.width > 0, frame.height > 0 else { return }
                conversationMenuSelection = ConversationMenuSelection(
                    conversation: conversation,
                    rowFrame: frame
                )
            }
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .zIndex(isMenuSelected ? 1 : 0)
    }

    private func openConversationProfile(userId: String) {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profileRoute = ArchivedProfileRoute(id: trimmed)
    }
}
