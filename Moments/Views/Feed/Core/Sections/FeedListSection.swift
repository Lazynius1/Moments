import SwiftUI
import FirebaseAuth
import Kingfisher
import MapKit

extension Moment {
    var feedViewIdentity: String {
        if let id, !id.isEmpty {
            return "\(authorId)_\(id)"
        }
        return "\(authorId)_\(timestamp.timeIntervalSince1970)_\(content.prefix(24))"
    }
}

struct FeedListSection: View {
    @ObservedObject private var recommendations = ForYouPreferences.shared
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
    let onAuthorAvatarLongPress: (String, String, CGRect, CGRect) -> Void
    var hiddenMomentId: String? = nil
    let profileZoomNamespace: Namespace.ID

    private var displayedMoments: [Moment] {
        guard selectedFeedType == .forYou else { return viewModel.moments }
        let hidden = recommendations.hiddenKeys()
        return viewModel.moments.filter { !hidden.contains(recommendations.momentKey($0)) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    let screenHeight = UIApplication.shared.activeWindowSize.height
                    let headerHeight = feedHeaderHeight
                    let segmentedToggleHeight = feedSelectorHeight
                    let tabbarHeight = 50.0
                    let availableHeight = screenHeight - headerHeight - segmentedToggleHeight - tabbarHeight - 60
                    let adAfterIndices = FeedAdPlacement.indicesAfterWhichToShowAd(
                        momentIds: displayedMoments.map { $0.id ?? "" },
                        minGap: selectedFeedType == .forYou ? 3 : 5,
                        maxGap: selectedFeedType == .forYou ? 5 : 7
                    )

                    LazyVStack(spacing: 12) {
                        Spacer()
                            .frame(height: feedContentTopInset)
                            .id("feed-top")

                        if viewModel.isLoading && displayedMoments.isEmpty {
                            ForEach(0..<4, id: \.self) { _ in
                                FeedPostSkeletonView(colorScheme: colorScheme)
                            }
                        } else {
                            // Reels usa VideoMomentsIndex.shared (rebuild en onChange).
                            // No pasar el array completo a cada card: invalidaba .equatable() al paginar.
                            ForEach(Array(displayedMoments.enumerated()), id: \.element.feedViewIdentity) { index, moment in
                                feedMomentRow(
                                    index: index,
                                    moment: moment,
                                    availableHeight: availableHeight,
                                    rowSpacing: 12,
                                    showAdAfter: adAfterIndices.contains(index)
                                )
                            }
                        }

                        if viewModel.isLoadingMore {
                            ModernLoadingMoreView(colorScheme: colorScheme)
                                .padding(.vertical, 15)
                        }
                    }
                    .padding(.vertical, 15)
                    .feedScrollVisibilityAnchor { values in
                        viewModel.syncMomentListeners(visibilityByMomentId: values)
                        recommendations.updateVisibility(moments: displayedMoments, fractions: values, enabled: selectedFeedType == .forYou)
                    }
                }
                .adoptForFloatingTabBar()
                .id(selectedFeedType)
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

                if displayedMoments.isEmpty && !viewModel.isLoading {
                    ModernEmptyFeedView(feedType: selectedFeedType)
                        .zIndex(10)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("feed-top", anchor: .top)
                }
            }
            .momentRefresh {
                if let userId = Auth.auth().currentUser?.uid {
                    // Un solo pipeline de refresco (antes se llamaba también onForceRefresh()
                    // que disparaba un segundo fetchMoments en paralelo).
                    await onManualRefresh(userId)
                }
            }
            .momentsScrollEdgeChrome()
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollFeedToTop"))) { _ in
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
                    proxy.scrollTo("feed-top", anchor: .top)
                }
                if let userId = Auth.auth().currentUser?.uid {
                    Task {
                        await onManualRefresh(userId)
                    }
                }
            }
            .onChange(of: selectedFeedType) { _, _ in
                recommendations.clearVisibility()
                isFeedHeaderHidden = false
                DispatchQueue.main.async { proxy.scrollTo("feed-top", anchor: .top) }
            }
            .onDisappear { recommendations.clearVisibility() }
            .onChange(of: recommendations.revision) { _, _ in
                if selectedFeedType == .forYou, displayedMoments.count < 3,
                   let userId = Auth.auth().currentUser?.uid {
                    viewModel.loadMoreMoments(userId: userId)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // IDs, no solo count: For You ↔ Following con el mismo tamaño dejaba el índice de Reels viejo.
        .onChange(of: displayedMoments.map(\.feedViewIdentity)) { _, _ in
            VideoMomentsIndex.shared.rebuild(from: displayedMoments)
            FeedFirstVideoPrewarmer.prepareFirstVideo(in: displayedMoments)
        }
        .onAppear {
            VideoMomentsIndex.shared.rebuild(from: displayedMoments)
            FeedFirstVideoPrewarmer.prepareFirstVideo(in: displayedMoments)
        }
    }

    @ViewBuilder
    private func feedMomentRow(
        index: Int,
        moment: Moment,
        availableHeight: CGFloat,
        rowSpacing: CGFloat,
        showAdAfter: Bool
    ) -> some View {
        VStack(spacing: rowSpacing) {
            let isHiddenForPreview = !(hiddenMomentId ?? "").isEmpty && moment.id == hiddenMomentId
            feedMomentCard(
                moment: moment,
                availableHeight: availableHeight,
                index: index
            )
            .opacity(isHiddenForPreview ? 0 : 1)
            .allowsHitTesting(!isHiddenForPreview)
            .animation(
                hiddenMomentId == nil
                    ? (UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.12))
                    : (UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.42, dampingFraction: 0.84)),
                value: isHiddenForPreview
            )

            if showAdAfter {
                SmartNativeAdView(slotId: "feed-\(moment.id ?? "\(index)")")
            }
        }
    }

    @ViewBuilder
    private func feedMomentCard(
        moment: Moment,
        availableHeight: CGFloat,
        index: Int
    ) -> some View {
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
                onAuthorAvatarLongPress: { userId, avatarFrame, postFrame in
                    onAuthorAvatarLongPress(userId, moment.id ?? "", avatarFrame, postFrame)
                },
                profileZoomNamespace: profileZoomNamespace,
                onPeek: { imageURL, ratio, isPressing in
                    handleFeedPeek(imageURL: imageURL, ratio: ratio, isPressing: isPressing, moment: moment)
                },
                reelsVideos: nil
            )
            .equatable()
            .onAppear { prefetchUpcomingMoments(from: index) }
            .environmentObject(firestoreService)
            .environment(viewModel)
        }
    }

    private func handleFeedNearEnd(for moment: Moment) {
        guard moment.id == displayedMoments.last?.id,
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
        guard nextIndex < displayedMoments.count else { return }

        let endIndex = min(nextIndex + 8, displayedMoments.count)
        let upcoming = Array(displayedMoments[nextIndex..<endIndex])

        let imageURLs = VideoPlaybackSelector.shared.imagePrefetchURLs(from: upcoming, maxMoments: 8)
        if !imageURLs.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: imageURLs)
        }

        let videoURLs = VideoPlaybackSelector.shared.preloadURLStrings(from: upcoming, maxMoments: 4)
        if !videoURLs.isEmpty {
            VideoPreloader.shared.preloadAssets(urls: videoURLs)
        }
    }
}
