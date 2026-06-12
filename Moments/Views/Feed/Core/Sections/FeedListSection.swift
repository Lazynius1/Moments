import SwiftUI
import FirebaseAuth
import Kingfisher
import MapKit

private extension Moment {
    var feedViewIdentity: String {
        if let id, !id.isEmpty {
            return "\(authorId)_\(id)"
        }
        return "\(authorId)_\(timestamp.timeIntervalSince1970)_\(content.prefix(24))"
    }
}

struct FeedListSection: View {
    @Bindable var viewModel: FeedViewModel
    @Binding var isFeedHeaderHidden: Bool
    @Binding var selectedMoment: Moment?
    @Binding var selectedFeedType: FeedType
    @Binding var selectedHashtag: String
    @Binding var showExploreWithHashtag: Bool
    @Binding var selectedLocationName: String
    @Binding var selectedLocationCoordinate: CLLocationCoordinate2D?
    @Binding var showingLocationMap: Bool
    @Binding var showGlobalContextMenu: Bool
    @Binding var selectedMomentForMenu: Moment?
    @Binding var peekImageURL: String?
    @Binding var peekAspectRatio: CGFloat
    @Binding var isPeeking: Bool
    @Binding var peekIsProtected: Bool

    @EnvironmentObject var firestoreService: FirestoreService

    let colorScheme: ColorScheme
    let feedContentTopInset: CGFloat
    let feedHeaderHeight: CGFloat
    let feedSelectorHeight: CGFloat
    let onForceRefresh: () -> Void
    let onManualRefresh: (String) async -> Void
    let onOpenUserProfile: (String) -> Void
    let profileZoomNamespace: Namespace.ID

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    let screenHeight = UIScreen.main.bounds.height
                    let headerHeight = feedHeaderHeight
                    let segmentedToggleHeight = feedSelectorHeight
                    let tabbarHeight = 50.0
                    let availableHeight = screenHeight - headerHeight - segmentedToggleHeight - tabbarHeight - 60

                    LazyVStack(spacing: max(15, screenHeight * 0.02)) {
                        Spacer()
                            .frame(height: feedContentTopInset)

                        if viewModel.isLoading && viewModel.moments.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                FeedPostSkeletonView(colorScheme: colorScheme)
                            }
                        } else {
                            ForEach(Array(viewModel.moments.enumerated()), id: \.element.feedViewIdentity) { index, moment in
                                feedMomentRow(
                                    index: index,
                                    moment: moment,
                                    availableHeight: availableHeight,
                                    rowSpacing: max(15, screenHeight * 0.02)
                                )
                            }
                        }

                        if viewModel.isLoadingMore {
                            ModernLoadingMoreView(colorScheme: colorScheme)
                                .padding(.vertical, 15)
                        }
                    }
                    .padding(.vertical, 15)
                    .onPreferenceChange(MomentVisibilityPreference.self) { values in
                        FeedVisibilityCoordinator.shared.update(all: values)
                        viewModel.syncMomentListeners(visibilityByMomentId: values)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            if value.translation.height < -40 && !isFeedHeaderHidden {
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                                    isFeedHeaderHidden = true
                                }
                            } else if value.translation.height > 28 && isFeedHeaderHidden {
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                                    isFeedHeaderHidden = false
                                }
                            }
                        }
                )

                if viewModel.moments.isEmpty && !viewModel.isLoading {
                    ModernEmptyFeedView(feedType: selectedFeedType)
                        .zIndex(10)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
            .refreshable {
                if let userId = Auth.auth().currentUser?.uid {
                    onForceRefresh()
                    await onManualRefresh(userId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollFeedToTop"))) { _ in
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
                    proxy.scrollTo(0, anchor: .top)
                }
                if let userId = Auth.auth().currentUser?.uid {
                    onForceRefresh()
                    Task {
                        await onManualRefresh(userId)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.moments.count) { _, _ in
            VideoMomentsIndex.shared.rebuild(from: viewModel.moments)
        }
    }

    @ViewBuilder
    private func feedMomentRow(
        index: Int,
        moment: Moment,
        availableHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        VStack(spacing: rowSpacing) {
            feedMomentCard(moment: moment, availableHeight: availableHeight, index: index)

            let adInterval = selectedFeedType == .forYou ? 3 : 5
            if (index + 1) % adInterval == 0 && index < viewModel.moments.count - 1 {
                SmartNativeAdView()
            }
        }
    }

    @ViewBuilder
    private func feedMomentCard(moment: Moment, availableHeight: CGFloat, index: Int) -> some View {
        let isProtected = (moment.audience?.lowercased() ?? "") != "everyone"

        ScreenshotProtectedView(isProtected: isProtected) {
            ModernPostCardView(
                moment: moment,
                availableHeight: availableHeight,
                colorScheme: colorScheme,
                onComment: { selectedMoment = moment },
                onNearEnd: { handleFeedNearEnd(for: moment) },
                onHashtagTap: handleFeedHashtagTap,
                onLocationTap: handleFeedLocationTap,
                onContextMenu: handleFeedContextMenu,
                onTagTap: onOpenUserProfile,
                onOpenUserProfile: onOpenUserProfile,
                profileZoomNamespace: profileZoomNamespace,
                onPeek: { imageURL, ratio, isPressing in
                    handleFeedPeek(imageURL: imageURL, ratio: ratio, isPressing: isPressing, moment: moment)
                }
            )
            .equatable()
            .onAppear { prefetchUpcomingMoments(from: index) }
            .environmentObject(firestoreService)
            .environment(viewModel)
        }
    }

    private func handleFeedNearEnd(for moment: Moment) {
        guard moment.id == viewModel.moments.last?.id,
              let userId = Auth.auth().currentUser?.uid else { return }
        viewModel.loadMoreMoments(userId: userId)
    }

    private func handleFeedHashtagTap(_ hashtag: String) {
        selectedHashtag = "#\(hashtag)"
        showExploreWithHashtag = true
    }

    private func handleFeedLocationTap(_ locationName: String, _ coordinate: CLLocationCoordinate2D?) {
        selectedLocationName = locationName
        selectedLocationCoordinate = coordinate
        showingLocationMap = true
    }

    private func handleFeedContextMenu(_ moment: Moment) {
        selectedMomentForMenu = moment
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showGlobalContextMenu = true
        }
    }

    private func handleFeedPeek(imageURL: String, ratio: CGFloat, isPressing: Bool, moment: Moment) {
        if isPressing, let url = URL(string: imageURL) {
            KingfisherManager.shared.retrieveImage(with: url) { _ in }
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if isPressing {
                peekImageURL = imageURL
                peekAspectRatio = ratio
                peekIsProtected = (moment.audience?.lowercased() ?? "") != "everyone"
                isPeeking = true
            } else {
                isPeeking = false
                peekIsProtected = false
            }
        }
    }

    private func prefetchUpcomingMoments(from index: Int) {
        let nextIndex = index + 1
        guard nextIndex < viewModel.moments.count else { return }

        let endIndex = min(nextIndex + 8, viewModel.moments.count)
        let upcoming = Array(viewModel.moments[nextIndex..<endIndex])

        let imageURLs = upcoming.compactMap { moment -> URL? in
            guard let firstMedia = moment.mediaItems?.first?.url else { return nil }
            return URL(string: firstMedia)
        }
        if !imageURLs.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: imageURLs)
        }

        let videoURLs = VideoPlaybackSelector.shared.preloadURLStrings(from: upcoming, maxMoments: 4)
        if !videoURLs.isEmpty {
            VideoPreloader.shared.preloadAssets(urls: videoURLs)
        }
    }
}
