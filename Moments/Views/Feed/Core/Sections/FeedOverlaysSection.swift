import SwiftUI
import Kingfisher

struct FeedOverlaysSection: View {
    @Binding var isPeeking: Bool
    @Binding var peekImageURL: String?
    @Binding var peekAspectRatio: CGFloat
    @Binding var peekIsProtected: Bool
    @Binding var showGlobalContextMenu: Bool
    @Binding var showShareSheet: Bool
    @Binding var showEditSheet: Bool
    @Binding var showDeleteAlert: Bool
    @Binding var editedContent: String
    @Binding var selectedMomentForMenu: Moment?
    @Binding var pendingEchoInvitationRoute: FeedEchoInvitationRoute?
    @Binding var showPendingEchoInvitation: Bool
    @Binding var selectedPendingEchoId: String

    @ObservedObject var notificationSummaryService: NotificationSummaryService
    @ObservedObject var badgeService: NotificationBadgeService

    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if isPeeking, let imageURL = peekImageURL {
                ZStack {
                    ScreenshotProtectedView(isProtected: peekIsProtected, fillsContainer: true) {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()

                            KFImage(URL(string: imageURL))
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: UIScreen.main.bounds.width - 32,
                                    height: (UIScreen.main.bounds.width - 32) / peekAspectRatio
                                )
                                .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPeeking)
                .allowsHitTesting(false)
                .zIndex(998)
            }

            if showGlobalContextMenu, let moment = selectedMomentForMenu {
                ModernContextMenuOverlay(
                    moment: moment,
                    isPresented: $showGlobalContextMenu,
                    onEdit: {
                        editedContent = moment.content
                        showEditSheet = true
                    },
                    onDelete: {
                        showDeleteAlert = true
                    },
                    onReport: {}
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1000)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showGlobalContextMenu)
            }

            if showShareSheet, let moment = selectedMomentForMenu {
                ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1001)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showShareSheet)
            }

            VStack {
                NotificationSummaryPopup(
                    isPresented: $notificationSummaryService.shouldShowSummary,
                    unreadNotifications: badgeService.unreadNotificationsCount,
                    unreadMessages: badgeService.unreadMessagesCount,
                    colorScheme: colorScheme
                )
                Spacer()
            }
            .zIndex(2000)

            if let route = pendingEchoInvitationRoute {
                EchoInvitationView(
                    echoId: route.echoId,
                    onDismiss: {
                        pendingEchoInvitationRoute = nil
                        showPendingEchoInvitation = false
                        selectedPendingEchoId = ""
                    },
                    onAccept: { echoId in
                        AppRouter.shared.navigate(to: .echo(echoId: echoId))
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2100)
            }
        }
    }
}
