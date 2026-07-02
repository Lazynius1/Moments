import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension GlassmorphicChatView {
    // MARK: - Toolbar nativo (scroll edge blur del sistema en iOS 26)

    @ToolbarContentBuilder
    var chatToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            chatToolbarBackButton
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .topBarLeading) {
            Button(action: openProfileOrStoryFromHeader) {
                chatToolbarAvatar
            }
            .buttonStyle(.plain)
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .principal) {
            chatToolbarTitleStack
                .contentShape(Rectangle())
                .onTapGesture {
                    showingUserProfile = true
                }
        }

        ToolbarItem(placement: .topBarTrailing) {
            chatToolbarTrailingCluster
        }
        .chatHideSharedBackgroundIfAvailable()
    }

    /// Header de búsqueda a ancho completo (sin fondo opaco; solo pill + X glass).
    var chatSearchNavigationHeader: some View {
        chatHeaderSearchBar
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
    }

    /// Fila completa del header en modo búsqueda: pill glass + botón X circular.
    var chatHeaderSearchBar: some View {
        HStack(spacing: 8) {
            chatHeaderSearchField
                .frame(maxWidth: .infinity)

            chatHeaderSearchCloseButton
        }
        .frame(height: 44)
    }

    var chatHeaderSearchField: some View {
        HStack(spacing: 0) {
            Group {
                if viewModel.isSearchingHistory {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(adaptiveColors.secondary.opacity(0.85))
                }
            }
            .frame(width: 36, height: 44)

            TextField(LocalizedStringKey("chat.search.placeholder"), text: $searchQuery)
                .font(.system(size: legacyPoppinsSize(17)))
                .foregroundStyle(adaptiveColors.primary)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($isSearchFieldFocused)
                .onSubmit(scrollToCurrentSearchMatch)

            if !searchQuery.isEmpty {
                Button(action: clearSearchQueryKeepingMode) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(adaptiveColors.secondary.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .momentsChromeGlass(in: Capsule(), interactive: true)
    }

    var chatHeaderSearchCloseButton: some View {
        Button(action: toggleChatSearch) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
                .frame(width: 44, height: 44)
                .momentsChromeGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("common.cancel"))
    }

    func clearSearchQueryKeepingMode() {
        searchQuery = ""
        viewModel.clearSearch()
        searchMatchIds = []
        currentSearchMatchIndex = 0
        pendingSearchTargetId = nil
        isSearchFieldFocused = true
    }

    var chatToolbarBackButton: some View {
        ProfileChromeIconButton(
            systemName: "chevron.left",
            foregroundColor: adaptiveColors.primary,
            preset: .navigationBack,
            action: { dismiss() }
        )
    }

    @ViewBuilder
    var chatToolbarAvatar: some View {
        if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
            ProfileUnavailableAvatar(size: 40)
                .userProfileZoomSource(
                    userId: viewModel.conversation.otherParticipantId,
                    namespace: profileZoomNamespace,
                    cornerRadius: 20
                )
        } else {
            AsyncProfileImageView(userId: viewModel.conversation.otherParticipantId)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .userProfileZoomSource(
                    userId: viewModel.conversation.otherParticipantId,
                    namespace: profileZoomNamespace,
                    cornerRadius: 20
                )
                .overlay(
                    StorySegmentedRing(
                        storyCount: storyCount,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseenStory,
                        storyViewedStatus: storyViewedStatus,
                        storyAudiences: storyAudiences,
                        isOwnStory: false,
                        colorScheme: colorScheme,
                        ringSize: 40,
                        lineWidth: 2.7
                    )
                )
        }
    }

    var chatToolbarTitleStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(otherParticipantDisplayName)
                    .font(.system(size: 17, weight: .semibold))
                    .strikethrough(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser, color: adaptiveColors.secondary)
                    .foregroundStyle(adaptiveColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if !isOtherParticipantUnavailable {
                    VerifiedBadgeView(userId: viewModel.conversation.otherParticipantId, size: 14)
                }
            }

            chatToolbarSubtitle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    var chatToolbarSubtitle: some View {
        if isOtherParticipantBlockedByCurrentUser {
            Text("chat.blockedByMe.subtitle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if isOtherParticipantUnavailable {
            Text("chat.profileUnavailable")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if !viewModel.typingUsers.isEmpty {
            Text("chat.typing")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if let presence = onlineStatusService.presenceDisplay(
            for: otherUserStatus,
            lastSeen: otherUserLastSeen
        ) {
            HStack(spacing: 4) {
                Image(systemName: presence.status.icon)
                    .foregroundStyle(presence.status.color)
                    .font(.system(size: 7))

                Text(presence.statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(adaptiveColors.secondary)
                    .lineLimit(1)

                if let lastSeenText = presence.supplementalText {
                    Text("• \(lastSeenText)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    var chatToolbarTrailingCluster: some View {
        ProfileChromeControlsCluster {


            ProfileChromeIconButton(
                systemName: "magnifyingglass",
                foregroundColor: adaptiveColors.primary,
                preset: .toolbarAction,
                standaloneGlass: false,
                action: toggleChatSearch
            )

            chatToolbarMenu
        }
    }

    var chatToolbarMenu: some View {
        Menu {
            Button(action: { showingConversationSettings = true }) {
                Label(
                    NSLocalizedString("chat.menu.details", comment: "Conversation details"),
                    systemImage: "gearshape"
                )
            }

            Button(role: .destructive, action: { showingReportSheet = true }) {
                Label(
                    NSLocalizedString("report.action.user", comment: "Report user"),
                    systemImage: "flag"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: MomentsGlassControlMetrics.toolbarIconSize, weight: .semibold))
                .foregroundColor(adaptiveColors.primary)
                .frame(
                    width: MomentsGlassControlMetrics.toolbarControlSize,
                    height: MomentsGlassControlMetrics.toolbarControlSize
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    func openProfileOrStoryFromHeader() {
        if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
            showingUserProfile = true
        } else if hasStory && !isOtherParticipantBlockedByCurrentUser {
            storyRoute = ChatStoryRoute(userId: viewModel.conversation.otherParticipantId)
        } else {
            showingUserProfile = true
        }
    }

}
