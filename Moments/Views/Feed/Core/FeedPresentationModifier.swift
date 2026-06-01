import SwiftUI
import MapKit

struct FeedPresentationModifier: ViewModifier {
    @Binding var showNotifications: Bool
    @Binding var showMessages: Bool
    @Binding var showSpecificUserStories: Bool
    @Binding var selectedStoryUserId: String
    @Binding var storyRingNavigationUserIds: [String]
    @Binding var showStories: Bool
    @Binding var selectedMoment: Moment?
    @Binding var showExploreWithHashtag: Bool
    @Binding var selectedHashtag: String
    @Binding var showExplore: Bool
    @Binding var showingLocationMap: Bool
    @Binding var selectedLocationName: String
    @Binding var selectedLocationCoordinate: CLLocationCoordinate2D?
    @Binding var showMomentDetail: Bool
    @Binding var targetMomentId: String?
    @Binding var targetMomentUserId: String?
    @Binding var showEditSheet: Bool
    @Binding var showDeleteAlert: Bool
    @Binding var selectedMomentForMenu: Moment?
    @Binding var selectedProfileRoute: FeedProfileSheetRoute?
    @Binding var selectedUserId: String
    @Binding var showEchoHistory: Bool
    @Binding var targetConversationId: String?

    let messagingViewModel: MessagingViewModel
    let firestoreService: FirestoreService
    let updateMoment: (Moment, EditMomentPayload) -> Void
    let deleteMoment: (Moment) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showNotifications) {
                NotificationsView(onNotificationsCleared: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NotificationsCleared"),
                        object: nil
                    )
                })
            }
            .fullScreenCover(isPresented: $showMessages) {
                MessagingView(targetConversationId: $targetConversationId, onDismiss: {
                    showMessages = false
                })
                .environmentObject(messagingViewModel)
                .environmentObject(firestoreService)
            }
            .fullScreenCover(isPresented: $showSpecificUserStories) {
                StoriesView(
                    startAtUserId: selectedStoryUserId,
                    ringNavigationUserIds: storyRingNavigationUserIds
                )
                    .environmentObject(firestoreService)
                    .ignoresSafeArea(.keyboard)
            }
            .fullScreenCover(isPresented: $showStories) {
                StoriesView(ringNavigationUserIds: storyRingNavigationUserIds)
                    .environmentObject(firestoreService)
                    .ignoresSafeArea(.keyboard)
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedMoment != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectedMoment = nil
                        }
                    }
                )
            ) {
                if let moment = selectedMoment {
                    ModernCommentsView(moment: moment)
                        .environmentObject(firestoreService)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showExploreWithHashtag) {
                ExploreView(initialSearchQuery: selectedHashtag)
            }
            .sheet(isPresented: $showExplore) {
                ExploreView()
            }
            .fullScreenCover(isPresented: $showingLocationMap) {
                LocationMapView(
                    locationName: selectedLocationName.isEmpty ? NSLocalizedString("feed.location.default", comment: "Default location name") : selectedLocationName,
                    coordinate: selectedLocationCoordinate,
                    isPresented: $showingLocationMap
                )
            }
            .sheet(isPresented: $showMomentDetail) {
                if let momentId = targetMomentId, let userId = targetMomentUserId {
                    MomentDetailFromNotificationView(
                        momentId: momentId,
                        userId: userId,
                        isPresented: $showMomentDetail
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        targetMomentId = nil
                        targetMomentUserId = nil
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let moment = selectedMomentForMenu {
                    EditMomentView(
                        moment: moment,
                        onSave: { payload in
                            updateMoment(moment, payload)
                        }
                    )
                }
            }
            .alert(NSLocalizedString("feed.actions.delete.title", comment: "Delete moment alert title"), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("feed.actions.cancel", comment: "Cancel action"), role: .cancel) { }
                Button(NSLocalizedString("feed.actions.delete", comment: "Delete action"), role: .destructive) {
                    if let moment = selectedMomentForMenu {
                        deleteMoment(moment)
                    }
                }
            } message: {
                Text("feed.delete.confirm")
            }
            .sheet(item: $selectedProfileRoute, onDismiss: {
                selectedUserId = ""
                selectedProfileRoute = nil
            }) {
                UserProfileView(userId: $0.userId)
                    .id($0.userId)
            }
            .sheet(isPresented: $showEchoHistory) {
                EchoHistoryView()
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    func feedPresentations(
        showNotifications: Binding<Bool>,
        showMessages: Binding<Bool>,
        showSpecificUserStories: Binding<Bool>,
        selectedStoryUserId: Binding<String>,
        storyRingNavigationUserIds: Binding<[String]>,
        showStories: Binding<Bool>,
        selectedMoment: Binding<Moment?>,
        showExploreWithHashtag: Binding<Bool>,
        selectedHashtag: Binding<String>,
        showExplore: Binding<Bool>,
        showingLocationMap: Binding<Bool>,
        selectedLocationName: Binding<String>,
        selectedLocationCoordinate: Binding<CLLocationCoordinate2D?>,
        showMomentDetail: Binding<Bool>,
        targetMomentId: Binding<String?>,
        targetMomentUserId: Binding<String?>,
        showEditSheet: Binding<Bool>,
        showDeleteAlert: Binding<Bool>,
        selectedMomentForMenu: Binding<Moment?>,
        selectedProfileRoute: Binding<FeedProfileSheetRoute?>,
        selectedUserId: Binding<String>,
        showEchoHistory: Binding<Bool>,
        targetConversationId: Binding<String?>,
        messagingViewModel: MessagingViewModel,
        firestoreService: FirestoreService,
        updateMoment: @escaping (Moment, EditMomentPayload) -> Void,
        deleteMoment: @escaping (Moment) -> Void
    ) -> some View {
        modifier(
            FeedPresentationModifier(
                showNotifications: showNotifications,
                showMessages: showMessages,
                showSpecificUserStories: showSpecificUserStories,
                selectedStoryUserId: selectedStoryUserId,
                storyRingNavigationUserIds: storyRingNavigationUserIds,
                showStories: showStories,
                selectedMoment: selectedMoment,
                showExploreWithHashtag: showExploreWithHashtag,
                selectedHashtag: selectedHashtag,
                showExplore: showExplore,
                showingLocationMap: showingLocationMap,
                selectedLocationName: selectedLocationName,
                selectedLocationCoordinate: selectedLocationCoordinate,
                showMomentDetail: showMomentDetail,
                targetMomentId: targetMomentId,
                targetMomentUserId: targetMomentUserId,
                showEditSheet: showEditSheet,
                showDeleteAlert: showDeleteAlert,
                selectedMomentForMenu: selectedMomentForMenu,
                selectedProfileRoute: selectedProfileRoute,
                selectedUserId: selectedUserId,
                showEchoHistory: showEchoHistory,
                targetConversationId: targetConversationId,
                messagingViewModel: messagingViewModel,
                firestoreService: firestoreService,
                updateMoment: updateMoment,
                deleteMoment: deleteMoment
            )
        )
    }
}
