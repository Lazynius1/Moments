import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SharedActivityView<ViewModel: UserListViewModel & ObservableObject>: View {
    let currentUser: AppUser?
    let otherUser: AppUser
    @ObservedObject var viewModel: ViewModel
    var profileZoomNamespace: Namespace.ID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var chatAccessCoordinator = ChatAccessCoordinator.shared
    @StateObject private var messagingViewModel = MessagingViewModel()
    @State private var navigateToProfile = false
    @State private var navigateToChat = false
    @State private var targetConversation: Conversation?
    @State private var showingMessageRequestAlert = false
    @State private var messageRequestText = ""
    @State private var messageRequestError: String?
    @State private var showingSuccessMessage = false
    @State private var relationshipState: FollowButtonState = .canFollow
    @State private var showingUnfollowConfirmation = false
    @State private var followedYouAt: Date?
    @State private var followingSince: Date?

    private let firestore = Firestore.firestore()

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.58)
    }

    private var relationshipTimeline: [SharedActivityTimelineItem] {
        var items: [SharedActivityTimelineItem] = []

        if let followedYouAt {
            items.append(
                SharedActivityTimelineItem(
                    icon: "calendar",
                    text: String(
                        format: NSLocalizedString("sharedActivity.timeline.followedYou", comment: ""),
                        otherUser.username,
                        monthYearString(from: followedYouAt)
                    )
                )
            )
        }

        if let followingSince {
            items.append(
                SharedActivityTimelineItem(
                    icon: "calendar",
                    text: String(
                        format: NSLocalizedString("sharedActivity.timeline.youFollowed", comment: ""),
                        otherUser.username,
                        monthYearString(from: followingSince)
                    )
                )
            )
        }

        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                relationButtons
                timelineSection
                divider
                modulesSection
            }
            .padding(.bottom, 32)
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("sharedActivity.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .navigationDestination(isPresented: $navigateToProfile) {
            UserProfileView(userId: otherUser.id)
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let conversation = targetConversation {
                Group {
                    if chatAccessCoordinator.accessState == .available {
                        GlassmorphicChatView(
                            conversation: conversation,
                            session: ChatSessionEngine.shared.session(for: conversation)
                        )
                    } else {
                        ChatRecoveryGateView(onCancel: {
                            navigateToChat = false
                        }) {
                            GlassmorphicChatView(
                                conversation: conversation,
                                session: ChatSessionEngine.shared.session(for: conversation)
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingMessageRequestAlert) {
            MessageRequestModalView(
                messageText: $messageRequestText,
                errorMessage: $messageRequestError,
                showingSuccessMessage: $showingSuccessMessage,
                onSend: sendMessageRequest,
                onDismiss: {
                    showingMessageRequestAlert = false
                    messageRequestText = ""
                    messageRequestError = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            .presentationBackground(.clear)
        }
        .alert(NSLocalizedString("messageRequestModal.success.title", comment: ""), isPresented: $showingSuccessMessage) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                showingSuccessMessage = false
            }
        } message: {
            Text(NSLocalizedString("messageRequestModal.success.message", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                viewModel.unfollowUser(userId: otherUser.id)
                viewModel.prefetchRelationshipState(for: otherUser.id)
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
        .onAppear {
            refreshRelationshipState()
            viewModel.prefetchRelationshipState(for: otherUser.id)
            loadRelationshipTimeline()

            if let currentUserId = Auth.auth().currentUser?.uid {
                messagingViewModel.fetchConversations(for: currentUserId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  changedUserId == otherUser.id else { return }
            refreshRelationshipState()
        }
    }



    private var heroSection: some View {
        VStack(spacing: 18) {
            HStack(spacing: -18) {
                sharedAvatar(userId: currentUser?.id, fallbackLabel: "M")
                    .zIndex(2)

                sharedAvatar(userId: otherUser.id, fallbackLabel: String(otherUser.username.prefix(1)).uppercased())
                    .zIndex(1)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text(
                    String(
                        format: NSLocalizedString("sharedActivity.youAndUser", comment: ""),
                        otherUser.username
                    )
                )
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.center)

                Text(
                    String(
                        format: NSLocalizedString("sharedActivity.subtitle", comment: ""),
                        otherUser.username
                    )
                )
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
        }
    }

    private var relationButtons: some View {
        HStack(spacing: 10) {
            Button(action: handleRelationshipAction) {
                Text(relationshipState.buttonText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16), interactive: relationshipState.isActionable))
            }
            .buttonStyle(.plain)
            .disabled(!relationshipState.isActionable)

            Button(action: openMessageFlow) {
                Text(NSLocalizedString("userProfile.sendMessage", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true))
            }
            .buttonStyle(.plain)

            Button(action: { navigateToProfile = true }) {
                Text(NSLocalizedString("userActivity.event.action.viewProfile", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    private var timelineSection: some View {
        VStack(spacing: 18) {
            ForEach(relationshipTimeline) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 24)

                    Text(item.text)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    private var divider: some View {
        Rectangle()
            .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
            .frame(height: 10)
            .padding(.bottom, 6)
    }

    private var modulesSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SharedActivityDetailView(category: .tags, currentUser: currentUser, otherUser: otherUser)
            } label: {
                sharedModuleRow(
                    category: .tags,
                    title: NSLocalizedString("editMoment.tags.title", comment: ""),
                    subtitle: NSLocalizedString("sharedActivity.modules.tags.subtitle", value: "Momentos en los que os habéis etiquetado", comment: "")
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SharedActivityDetailView(category: .reactions, currentUser: currentUser, otherUser: otherUser)
            } label: {
                sharedModuleRow(
                    category: .reactions,
                    title: NSLocalizedString("userActivity.simple.item.reactions.title", comment: ""),
                    subtitle: NSLocalizedString("sharedActivity.modules.reactions.subtitle", value: "Reacciones en los momentos de cada uno", comment: "")
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                SharedActivityDetailView(category: .comments, currentUser: currentUser, otherUser: otherUser)
            } label: {
                sharedModuleRow(
                    category: .comments,
                    title: NSLocalizedString("comments.title", comment: ""),
                    subtitle: NSLocalizedString("sharedActivity.modules.comments.subtitle", value: "Comentarios en las publicaciones del otro", comment: "")
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sharedModuleIcon(for category: SharedActivityCategory) -> some View {
        switch category {
        case .reactions:
            AnimatedReactionIcon()
                .frame(width: 28, height: 28)
        case .comments:
            AttachmentIconView(
                icon: .comments,
                preset: .activityCategoryRow,
                tintColor: primaryTextColor
            )
            .frame(width: 28, height: 28)
        case .tags:
            AttachmentIconView(
                icon: .tagged,
                preset: .activityCategoryRow,
                tintColor: primaryTextColor
            )
            .frame(width: 28, height: 28)
        }
    }

    private func sharedModuleRow(category: SharedActivityCategory, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            sharedModuleIcon(for: category)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(primaryTextColor)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private func sharedAvatar(userId: String?, fallbackLabel: String) -> some View {
        ZStack {
            if let userId {
                StoryRingAvatarView(
                    userId: userId,
                    size: 118,
                    lineWidth: 3,
                    showBaseStroke: true,
                    baseStrokeColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.12),
                    baseStrokeWidth: 1,
                    profileZoomNamespace: profileZoomNamespace
                )
            } else {
                Circle()
                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                    .frame(width: 118, height: 118)
                    .overlay(
                        Text(fallbackLabel)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(primaryTextColor)
                    )
            }
        }
    }

    private func refreshRelationshipState() {
        relationshipState = viewModel.relationshipState(for: otherUser.id)
    }

    private func handleRelationshipAction() {
        switch relationshipState {
        case .following:
            showingUnfollowConfirmation = true
        case .canFollow, .canRequestFollow:
            let nextState: FollowButtonState = relationshipState == .canRequestFollow ? .requestPendingCancellable : .following
            relationshipState = nextState
            FollowStateStore.shared.setState(nextState, for: otherUser.id)
            viewModel.followUser(userId: otherUser.id)
        case .requestPendingCancellable:
            viewModel.cancelFollowRequest(userId: otherUser.id)
            relationshipState = .canRequestFollow
            FollowStateStore.shared.setState(.canRequestFollow, for: otherUser.id)
        case .ownProfile, .blocked, .requestPending:
            break
        }
    }

    private func openMessageFlow() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        messagingViewModel.startConversation(with: otherUser, from: currentUserId) { conversation in
            if let conversation {
                targetConversation = conversation
                navigateToChat = true
            } else if let errorMessage = messagingViewModel.errorMessage,
                      errorMessage.contains("solicitud") || errorMessage.contains("request") {
                showingMessageRequestAlert = true
            }
        }
    }

    private func sendMessageRequest() {
        guard Auth.auth().currentUser?.uid != nil else { return }

        messageRequestError = nil
        messageRequestText = messageRequestText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !messageRequestText.isEmpty else {
            messageRequestError = NSLocalizedString("messageRequestModal.error.empty", comment: "")
            return
        }

        MessageRequestService().sendMessageRequest(
            to: otherUser.id,
            message: messageRequestText
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    showingMessageRequestAlert = false
                    showingSuccessMessage = true
                    messageRequestText = ""
                case .failure(let error):
                    messageRequestError = String(
                        format: NSLocalizedString("messageRequestModal.error.generic", comment: ""),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func loadRelationshipTimeline() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        let group = DispatchGroup()
        var nextFollowedYouAt: Date?
        var nextFollowingSince: Date?

        group.enter()
        firestore.collection("users")
            .document(currentUserId)
            .collection("followers")
            .document(otherUser.id)
            .getDocument { snapshot, _ in
                if let timestamp = snapshot?.data()?["timestamp"] as? Timestamp {
                    nextFollowedYouAt = timestamp.dateValue()
                }
                group.leave()
            }

        group.enter()
        firestore.collection("users")
            .document(currentUserId)
            .collection("following")
            .document(otherUser.id)
            .getDocument { snapshot, _ in
                if let timestamp = snapshot?.data()?["timestamp"] as? Timestamp {
                    nextFollowingSince = timestamp.dateValue()
                }
                group.leave()
            }

        group.notify(queue: .main) {
            followedYouAt = nextFollowedYouAt
            followingSince = nextFollowingSince
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "LLL. yyyy"
        return formatter.string(from: date)
    }
}

private struct SharedActivityTimelineItem: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}
