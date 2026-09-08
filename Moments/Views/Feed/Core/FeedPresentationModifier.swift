import SwiftUI
import MapKit

struct FeedPresentationModifier: ViewModifier {
    @Binding var showNotifications: Bool
    @Binding var showNova: Bool
    @Binding var selectedStoryRoute: StoryUserPresentationRoute?
    @Binding var storyRingNavigationUserIds: [String]
    @Binding var showStories: Bool
    @Binding var selectedMoment: Moment?
    @Binding var showExploreWithHashtag: Bool
    @Binding var selectedHashtag: String
    @Binding var showExplore: Bool
    @Binding var showingLocationMap: Bool
    @Binding var selectedLocationName: String
    @Binding var selectedLocationCoordinate: CLLocationCoordinate2D?
    @Binding var zoomDestination: MomentZoomDestination?
    @Binding var zoomResolvedMoment: Moment?
    @Binding var showEditSheet: Bool
    @Binding var showDeleteAlert: Bool
    @Binding var selectedMomentForMenu: Moment?
    @Binding var selectedProfileRoute: FeedProfileSheetRoute?
    @Binding var selectedUserId: String
    @Binding var showEchoHistory: Bool

    let profileZoomNamespace: Namespace.ID
    let momentZoomNamespace: Namespace.ID
    let storyZoomNamespace: Namespace.ID
    let messagingViewModel: MessagingViewModel
    let firestoreService: FirestoreService
    let updateMoment: (Moment, EditMomentPayload) -> Void
    let deleteMoment: (Moment) -> Void

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsView(onNotificationsCleared: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NotificationsCleared"),
                        object: nil
                    )
                })
                .environmentObject(messagingViewModel)
                .environmentObject(firestoreService)
            }
            .navigationDestination(isPresented: $showNova) {
                NovaView()
            }
            .fullScreenCover(item: $selectedStoryRoute) { route in
                StoriesView(
                    startAtUserId: route.userId,
                    ringNavigationUserIds: storyRingNavigationUserIds,
                    startStoryId: route.startStoryId,
                    startElapsed: route.startElapsed
                )
                    .environmentObject(firestoreService)
                    .ignoresSafeArea(.keyboard)
                    .navigationTransition(.zoom(sourceID: "story-ring-\(route.userId)", in: storyZoomNamespace))
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
                    .momentRefreshOverlayHost()
            }
            .sheet(isPresented: $showExplore) {
                ExploreView()
                    .momentRefreshOverlayHost()
            }
            .navigationDestination(isPresented: $showingLocationMap) {
                LocationMapView(
                    locationName: selectedLocationName.isEmpty ? NSLocalizedString("feed.location.default", comment: "Default location name") : selectedLocationName,
                    coordinate: selectedLocationCoordinate,
                    isPresented: $showingLocationMap
                )
            }
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: momentZoomNamespace
                )
            }
            .onChange(of: zoomDestination) { _, newValue in
                if newValue == nil {
                    zoomResolvedMoment = nil
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
            .userProfileNavigationDestination(
                item: $selectedProfileRoute,
                namespace: profileZoomNamespace
            )
            .onChange(of: selectedProfileRoute) { _, newRoute in
                if newRoute == nil {
                    selectedUserId = ""
                }
            }
            .sheet(isPresented: $showEchoHistory) {
                EchoHistoryView()
                    .presentationDetents([.medium, .large])
            }
    }

    private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
        guard let moment = zoomResolvedMoment else { return [] }
        if let initialMomentId = destination.initialMomentId, moment.id != initialMomentId {
            return []
        }
        return [moment]
    }
}

extension View {
    func feedPresentations(
        showNotifications: Binding<Bool>,
        showNova: Binding<Bool>,
        selectedStoryRoute: Binding<StoryUserPresentationRoute?>,
        storyRingNavigationUserIds: Binding<[String]>,
        showStories: Binding<Bool>,
        selectedMoment: Binding<Moment?>,
        showExploreWithHashtag: Binding<Bool>,
        selectedHashtag: Binding<String>,
        showExplore: Binding<Bool>,
        showingLocationMap: Binding<Bool>,
        selectedLocationName: Binding<String>,
        selectedLocationCoordinate: Binding<CLLocationCoordinate2D?>,
        zoomDestination: Binding<MomentZoomDestination?>,
        zoomResolvedMoment: Binding<Moment?>,
        showEditSheet: Binding<Bool>,
        showDeleteAlert: Binding<Bool>,
        selectedMomentForMenu: Binding<Moment?>,
        selectedProfileRoute: Binding<FeedProfileSheetRoute?>,
        selectedUserId: Binding<String>,
        showEchoHistory: Binding<Bool>,
        profileZoomNamespace: Namespace.ID,
        momentZoomNamespace: Namespace.ID,
        storyZoomNamespace: Namespace.ID,
        messagingViewModel: MessagingViewModel,
        firestoreService: FirestoreService,
        updateMoment: @escaping (Moment, EditMomentPayload) -> Void,
        deleteMoment: @escaping (Moment) -> Void
    ) -> some View {
        modifier(
            FeedPresentationModifier(
                showNotifications: showNotifications,
                showNova: showNova,
                selectedStoryRoute: selectedStoryRoute,
                storyRingNavigationUserIds: storyRingNavigationUserIds,
                showStories: showStories,
                selectedMoment: selectedMoment,
                showExploreWithHashtag: showExploreWithHashtag,
                selectedHashtag: selectedHashtag,
                showExplore: showExplore,
                showingLocationMap: showingLocationMap,
                selectedLocationName: selectedLocationName,
                selectedLocationCoordinate: selectedLocationCoordinate,
                zoomDestination: zoomDestination,
                zoomResolvedMoment: zoomResolvedMoment,
                showEditSheet: showEditSheet,
                showDeleteAlert: showDeleteAlert,
                selectedMomentForMenu: selectedMomentForMenu,
                selectedProfileRoute: selectedProfileRoute,
                selectedUserId: selectedUserId,
                showEchoHistory: showEchoHistory,
                profileZoomNamespace: profileZoomNamespace,
                momentZoomNamespace: momentZoomNamespace,
                storyZoomNamespace: storyZoomNamespace,
                messagingViewModel: messagingViewModel,
                firestoreService: firestoreService,
                updateMoment: updateMoment,
                deleteMoment: deleteMoment
            )
        )
    }
}
