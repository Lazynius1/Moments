import SwiftUI
import FirebaseAuth

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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 44))
                .foregroundStyle(adaptiveColors.primary.opacity(0.5))
            Text("messaging.section.archived")
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundStyle(adaptiveColors.primary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        let isMenuSelected = conversationMenuSelection?.conversation.id == conversation.id

        ConversationPressableRow(
            conversation: conversation,
            isMenuSelected: isMenuSelected,
            colorScheme: colorScheme,
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
}
