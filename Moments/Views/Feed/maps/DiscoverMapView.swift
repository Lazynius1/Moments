import SwiftUI
import MapKit
import Kingfisher
import FirebaseAuth
import FirebaseFirestore

struct DiscoverMapView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var locationManager = LocationUtilities.shared
    @State private var mapPosition = MapCameraPosition.region(MapRegionStore.initialRegion())
    @State private var region = MapRegionStore.initialRegion()

    @State private var contentFilter: MapDiscoverContentFilter = .all
    @State private var moments: [Moment] = []
    @State private var stories: [MapStoryPreview] = []
    @State private var friendPins: [MapFriendActivityPin] = []
    @State private var followingIds: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasRecoverableError = false
    @State private var showingBottomSheet = false
    @State private var mapSheetDetent: PresentationDetent = .medium
    @State private var momentDetailRoute: MapMomentDetailRoute?
    @State private var pendingMomentDetailRoute: MapMomentDetailRoute?
    @State private var pendingStoryPresentation: MapStoryViewerPresentation?
    @State private var resumeBottomSheetAfterDetail = false
    @State private var selectedPlaceCluster: MapPlaceCluster?
    @State private var selectedMomentIndex = 0
    @State private var storyViewerPresentation: MapStoryViewerPresentation?
    @State private var isOpeningStory = false
    @State private var regionSearchTask: Task<Void, Never>?
    @State private var hasPerformedInitialSearch = false
    @State private var timeFilter: MapDiscoverTimeFilter = .all
    @State private var zoneName: String?
    @State private var discoverWeather: WeatherData?
    @State private var weatherEffectsEnabled = true
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var searchFieldFocused: Bool
    @State private var isViewActive = true

    private struct MapStoryViewerPresentation: Identifiable {
        let id = UUID()
        let previews: [MapStoryPreview]
        let initialPreviewId: String?
    }

    private var mapPlaceLayout: MapPlaceLayout {
        MapPlaceClusterEngine.build(
            moments: filteredMoments,
            stories: filteredStories,
            friendPins: friendPins,
            filter: contentFilter,
            region: region
        )
    }

    private var sheetCluster: MapPlaceCluster {
        if let selectedPlaceCluster {
            return selectedPlaceCluster
        }
        return MapPlaceClusterEngine.aggregateRegionCluster(
            title: zoneName ?? NSLocalizedString("maps.discover.title", comment: "Discover map title"),
            moments: filteredMoments,
            stories: filteredStories,
            center: region.center
        )
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var filteredMoments: [Moment] {
        var result: [Moment]
        switch contentFilter {
        case .all, .places:
            result = moments
        case .friends:
            result = moments.filter { followingIds.contains($0.authorId) }
        }
        if let cutoff = timeFilter.cutoffDate {
            result = result.filter { $0.timestamp >= cutoff }
        }
        return result
    }

    private var filteredStories: [MapStoryPreview] {
        var result: [MapStoryPreview]
        switch contentFilter {
        case .all:
            result = stories
        case .friends:
            result = stories.filter { followingIds.contains($0.authorId) }
        case .places:
            return []
        }
        if let cutoff = timeFilter.cutoffDate {
            result = result.filter { $0.timestamp >= cutoff }
        }
        return result
    }

    private var showsWeatherEffects: Bool {
        weatherEffectsEnabled && discoverWeather != nil
    }

    var body: some View {
        ZStack {
            Map(position: $mapPosition) {
                ForEach(mapPlaceLayout.placeClusters) { cluster in
                    Annotation(clusterAccessibilityLabel(for: cluster), coordinate: cluster.coordinate) {
                        Button {
                            openPlaceCluster(cluster)
                        } label: {
                            MapPlacePin(cluster: cluster, colorScheme: colorScheme)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(Array(mapPlaceLayout.standaloneFriends.enumerated()), id: \.element.id) { index, friend in
                    let coordinate = MapPlaceClusterEngine.jitteredCoordinate(
                        for: friend.coordinate,
                        seed: friend.authorId,
                        index: index
                    )
                    Annotation(friend.username, coordinate: coordinate) {
                        Button {
                            openFriendCluster(friend)
                        } label: {
                            MapFriendActivityPinView(pin: friend, colorScheme: colorScheme)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                MapRegionStore.save(region: context.region)
                scheduleRegionSearch()
            }

            if showsWeatherEffects, let discoverWeather {
                Rectangle()
                    .fill(discoverWeather.mapOverlayColor)
                    .allowsHitTesting(false)
                    .opacity(discoverWeather.mapOverlayOpacity)
                    .animation(.easeInOut(duration: 2.0), value: discoverWeather.condition)
                    .ignoresSafeArea()

                MapWeatherEffectsView(weather: discoverWeather)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            VStack(spacing: 12) {
                header
                if isSearchActive {
                    searchBar
                }
                filterChips
                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                if let errorMessage {
                    if hasRecoverableError && (moments.isEmpty && stories.isEmpty) {
                        discoverErrorCard(message: errorMessage)
                    } else {
                        discoverErrorBanner(message: errorMessage)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingBottomSheet) {
            MapPlaceBottomSheet(
                cluster: sheetCluster,
                momentAvailability: [:],
                isLoading: isLoading,
                colorScheme: colorScheme,
                onMomentTap: { moment in
                    guard let index = sheetCluster.moments.firstIndex(where: { $0.id == moment.id }) else { return }
                    openMomentDetail(at: index, in: sheetCluster.moments, title: sheetCluster.displayName)
                },
                onPlaceStoriesTap: { cluster in
                    openPlaceStories(cluster)
                },
                weather: discoverWeather,
                userLocation: locationManager.currentLocation?.coordinate,
                placeIndex: mapPlaceLayout.placeClusters,
                onPlaceTap: { place in
                    selectPlaceFromIndex(place)
                },
                timeFilter: $timeFilter,
                onTimeFilterChange: {
                    selectedPlaceCluster = nil
                    updateBottomSheetForCurrentFilter()
                }
            )
            .mapLocationSystemSheet(detent: $mapSheetDetent)
        }
        .onChange(of: showingBottomSheet) { _, isShowing in
            if isShowing {
                mapSheetDetent = .medium
                return
            }
            presentDeferredMapContent()
        }
        .onChange(of: sheetCluster.totalCount) { _, count in
            if count == 0 && !isLoading {
                showingBottomSheet = false
            }
        }
        .onAppear {
            isViewActive = true
            locationManager.requestLocationPermission()
            loadFollowingIds()
            bootstrapMapCenter()
        }
        .onDisappear {
            isViewActive = false
            regionSearchTask?.cancel()
            regionSearchTask = nil
        }
        .fullScreenCover(item: $momentDetailRoute, onDismiss: {
            restoreBottomSheetIfNeeded()
        }) { route in
            MomentDetailContainerView(
                context: .map(
                    moments: route.moments,
                    initialIndex: route.initialIndex,
                    locationName: route.locationName,
                    momentAvailability: .constant([:]),
                    isPresented: Binding(
                        get: { momentDetailRoute != nil },
                        set: { if !$0 { momentDetailRoute = nil } }
                    )
                )
            )
        }
        .fullScreenCover(item: $storyViewerPresentation, onDismiss: {
            restoreBottomSheetIfNeeded()
        }) { presentation in
            MapPlaceStoryDeckView(
                previews: presentation.previews,
                initialPreviewId: presentation.initialPreviewId,
                onClose: { storyViewerPresentation = nil }
            )
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseStoryViewer"))) { _ in
                storyViewerPresentation = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        closeDiscoverMap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(adaptiveColors.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.momentsPressIcon)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(zoneName ?? NSLocalizedString("maps.discover.title", comment: "Discover map title"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(adaptiveColors.primary)
                            .lineLimit(1)

                        Text(headerSubtitle)
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(adaptiveColors.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .background(Color.clear.liquidGlass(in: Capsule()))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: adaptiveColors.shadowColor.opacity(0.15), radius: 10, x: 0, y: 5)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 10) {
                        Button {
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                isSearchActive.toggle()
                            }
                            if isSearchActive {
                                searchFieldFocused = true
                            } else {
                                searchText = ""
                            }
                        } label: {
                            Image(systemName: isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(adaptiveColors.primary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.momentsPressIcon)

                        Button {
                            recenterOnUser()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(adaptiveColors.accent)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.momentsPressIcon)

                        if let discoverWeather {
                            Button {
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                    weatherEffectsEnabled.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: weatherEffectsEnabled ? discoverWeather.condition.systemImageName : "cloud.slash.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(weatherEffectsEnabled ? adaptiveColors.accent : adaptiveColors.primary.opacity(0.7))

                                    VStack(alignment: .leading, spacing: -2) {
                                        Text(discoverWeather.temperatureFormatted)
                                            .font(.custom("Poppins-Bold", size: 13))
                                            .foregroundColor(adaptiveColors.primary)

                                        Text(discoverWeather.condition.displayName)
                                            .font(.custom("Poppins-Medium", size: 9))
                                            .foregroundColor(adaptiveColors.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.momentsPressSubtle)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .background(Color.clear.liquidGlass(in: Capsule()))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: adaptiveColors.shadowColor.opacity(0.15), radius: 10, x: 0, y: 5)

                    if discoverWeather != nil && weatherEffectsEnabled {
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("weather.attribution.text", comment: "Weather attribution text"))
                                .font(.custom("Poppins-Regular", size: 7))
                                .foregroundColor(.secondary.opacity(0.8))

                            Link(
                                NSLocalizedString("weather.attribution.link", comment: "Weather attribution link"),
                                destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
                            )
                            .font(.custom("Poppins-Medium", size: 7))
                            .foregroundColor(.blue.opacity(0.6))
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
        }
    }

    private var headerSubtitle: String {
        let placeCount = mapPlaceLayout.placeClusters.count
        if placeCount > 0 {
            return String(
                format: NSLocalizedString("maps.discover.activePlaces", comment: "Active places count"),
                placeCount
            )
        }
        return NSLocalizedString("maps.discover.subtitle", comment: "Discover map subtitle")
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(adaptiveColors.secondary)

            TextField(
                NSLocalizedString("maps.search.placeholder", comment: "Map search placeholder"),
                text: $searchText
            )
            .font(.custom("Poppins-Medium", size: 14))
            .focused($searchFieldFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit {
                performPlaceSearch()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(MapDiscoverContentFilter.allCases) { filter in
                Button {
                    applyContentFilter(filter)
                } label: {
                    Text(NSLocalizedString(filter.titleKey, comment: "Map filter"))
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(contentFilter == filter ? .white : adaptiveColors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(contentFilter == filter ? adaptiveColors.accent : Color.clear)
                                .liquidGlass(in: Capsule(), interactive: contentFilter != filter)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func closeDiscoverMap() {
        guard isViewActive else { return }
        isViewActive = false
        regionSearchTask?.cancel()
        regionSearchTask = nil
        searchFieldFocused = false

        let hadSheet = showingBottomSheet
        showingBottomSheet = false
        momentDetailRoute = nil
        storyViewerPresentation = nil
        pendingMomentDetailRoute = nil
        pendingStoryPresentation = nil

        if hadSheet {
            DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.dismissBeforeNextPresentation) {
                isPresented = false
            }
        } else {
            isPresented = false
        }
    }

    private func clusterAccessibilityLabel(for cluster: MapPlaceCluster) -> String {
        String(
            format: NSLocalizedString("maps.pin.accessibility", comment: "Map pin accessibility label"),
            cluster.displayName,
            cluster.totalCount
        )
    }

    private func bootstrapMapCenter() {
        if let coordinate = locationManager.currentLocation?.coordinate {
            focus(on: coordinate, autoSearch: true)
            return
        }

        locationManager.getCurrentLocation { coordinate in
            DispatchQueue.main.async {
                guard isViewActive else { return }
                if let coordinate {
                    focus(on: coordinate, autoSearch: true)
                } else {
                    applyFallbackRegion(andSearch: true)
                }
            }
        }
    }

    private func applyFallbackRegion(andSearch: Bool) {
        MapRegionStore.resolveFallbackRegion { fallbackRegion in
            DispatchQueue.main.async {
                guard isViewActive else { return }
                region = fallbackRegion
                mapPosition = .region(fallbackRegion)
                if andSearch {
                    performRegionSearch()
                }
            }
        }
    }

    private func recenterOnUser() {
        if let coordinate = locationManager.currentLocation?.coordinate {
            focus(on: coordinate, autoSearch: true)
            return
        }
        locationManager.getCurrentLocation { coordinate in
            guard let coordinate else { return }
            DispatchQueue.main.async {
                guard isViewActive else { return }
                focus(on: coordinate, autoSearch: true)
            }
        }
    }

    private func focus(on coordinate: CLLocationCoordinate2D, autoSearch: Bool) {
        let nextRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
        region = nextRegion
        mapPosition = .region(nextRegion)
        MapRegionStore.save(region: nextRegion)
        if autoSearch {
            performRegionSearch()
        }
    }

    private func scheduleRegionSearch() {
        regionSearchTask?.cancel()
        regionSearchTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isViewActive else { return }
                performRegionSearch()
            }
        }
    }

    private func performPlaceSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else { return }
            DispatchQueue.main.async {
                guard isViewActive else { return }
                searchFieldFocused = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchActive = false
                }
                searchText = ""
                focus(on: item.placemark.coordinate, autoSearch: true)
            }
        }
    }

    private func selectPlaceFromIndex(_ place: MapPlaceCluster) {
        selectedPlaceCluster = place
        let nextRegion = MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .region(nextRegion)
        }
    }

    private func refreshZoneContext() {
        MapZoneContextService.shared.zoneName(for: region.center) { name in
            guard isViewActive else { return }
            zoneName = name
        }

        let center = region.center
        Task {
            let weather = await WeatherService.shared.getWeatherSafely(for: center)
            await MainActor.run {
                guard isViewActive else { return }
                discoverWeather = weather
            }
        }
    }

    private func performRegionSearch() {
        isLoading = true
        errorMessage = nil
        hasRecoverableError = false
        refreshZoneContext()

        LocationSearchService.shared.searchDiscoverContentInRegion(region: region) { payload in
            guard isViewActive else { return }
            moments = payload.moments
            stories = payload.stories
            friendPins = LocationSearchService.shared.buildFriendActivityPins(
                moments: payload.moments,
                stories: payload.stories,
                followingIds: followingIds
            )
            isLoading = false
            hasPerformedInitialSearch = true
            if payload.isCompleteFailure {
                errorMessage = NSLocalizedString("maps.error.mapUnavailable", comment: "Map content unavailable")
                hasRecoverableError = true
                showingBottomSheet = false
            } else if payload.moments.isEmpty && payload.stories.isEmpty {
                errorMessage = NSLocalizedString("maps.discover.empty", comment: "Discover map empty state")
                hasRecoverableError = false
                showingBottomSheet = false
            } else if payload.hasPartialFailure {
                errorMessage = NSLocalizedString("maps.error.mapPartialContent", comment: "Map partial content warning")
                hasRecoverableError = false
                selectedPlaceCluster = nil
                updateBottomSheetForCurrentFilter()
            } else {
                errorMessage = nil
                hasRecoverableError = false
                selectedPlaceCluster = nil
                updateBottomSheetForCurrentFilter()
            }
        }
    }

    private func discoverErrorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)

            Text(message)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(adaptiveColors.primary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                performRegionSearch()
            } label: {
                Text(NSLocalizedString("maps.error.retry", comment: "Retry button text"))
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .foregroundColor(adaptiveColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func discoverErrorCard(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(adaptiveColors.accent)

            Text(message)
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(adaptiveColors.primary)
                .multilineTextAlignment(.center)

            Button {
                performRegionSearch()
            } label: {
                Text(NSLocalizedString("maps.error.retry", comment: "Retry button text"))
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(adaptiveColors.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func applyContentFilter(_ filter: MapDiscoverContentFilter) {
        contentFilter = filter
        selectedPlaceCluster = nil
        updateBottomSheetForCurrentFilter()
    }

    private func updateBottomSheetForCurrentFilter() {
        switch contentFilter {
        case .friends:
            showingBottomSheet = false
        case .all, .places:
            if filteredMoments.isEmpty && filteredStories.isEmpty {
                showingBottomSheet = false
            } else {
                showingBottomSheet = true
            }
        }
    }

    private func openPlaceCluster(_ cluster: MapPlaceCluster) {
        selectedPlaceCluster = cluster
        showingBottomSheet = true
    }

    private func openFriendCluster(_ pin: MapFriendActivityPin) {
        let cluster = MapPlaceClusterEngine.cluster(
            for: pin,
            moments: filteredMoments,
            stories: filteredStories
        )

        if cluster.momentCount == 0, cluster.primaryStory != nil {
            openPlaceStories(cluster)
            return
        }

        selectedPlaceCluster = cluster
        showingBottomSheet = true
    }

    private func openMomentDetail(at index: Int, in moments: [Moment], title: String) {
        selectedMomentIndex = index
        let route = MapMomentDetailRoute(
            moments: moments,
            initialIndex: index,
            locationName: title
        )

        if showingBottomSheet {
            pendingMomentDetailRoute = route
            resumeBottomSheetAfterDetail = true
            showingBottomSheet = false
        } else {
            momentDetailRoute = route
        }
    }

    private func presentDeferredMapContent() {
        guard pendingMomentDetailRoute != nil || pendingStoryPresentation != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.dismissBeforeNextPresentation) {
            guard isViewActive else { return }
            if let pendingRoute = pendingMomentDetailRoute {
                momentDetailRoute = pendingRoute
                pendingMomentDetailRoute = nil
                return
            }

            if let pendingStory = pendingStoryPresentation {
                storyViewerPresentation = pendingStory
                pendingStoryPresentation = nil
            }
        }
    }

    private func restoreBottomSheetIfNeeded() {
        guard resumeBottomSheetAfterDetail else { return }
        resumeBottomSheetAfterDetail = false

        DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.reopenBottomSheetAfterDetail) {
            guard isViewActive else { return }
            if sheetCluster.totalCount > 0 {
                showingBottomSheet = true
            }
        }
    }

    private func openPlaceStories(_ cluster: MapPlaceCluster, startingAt preview: MapStoryPreview? = nil) {
        guard !cluster.stories.isEmpty, !isOpeningStory else { return }
        isOpeningStory = true

        let presentation = MapStoryViewerPresentation(
            previews: cluster.stories,
            initialPreviewId: preview?.id ?? cluster.primaryStory?.id
        )

        DispatchQueue.main.async {
            guard isViewActive else { return }
            isOpeningStory = false
            if showingBottomSheet {
                pendingStoryPresentation = presentation
                resumeBottomSheetAfterDetail = true
                showingBottomSheet = false
            } else {
                storyViewerPresentation = presentation
            }
        }
    }

    private func loadFollowingIds() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("following")
            .getDocuments { snapshot, _ in
                let ids = Set(snapshot?.documents.map(\.documentID) ?? [])
                DispatchQueue.main.async {
                    guard isViewActive else { return }
                    followingIds = ids
                    friendPins = LocationSearchService.shared.buildFriendActivityPins(
                        moments: moments,
                        stories: stories,
                        followingIds: ids
                    )
                }
            }
    }
}

struct MapStoryPin: View {
    let story: MapStoryPreview
    let colorScheme: ColorScheme

    private let ringSize: CGFloat = 54
    private let thumbSize: CGFloat = 46
    private let privacyService = PrivacyService()

    @State private var snapshot = StoryRingSnapshot(
        hasStory: true,
        hasUnseenStory: true,
        storyCount: 1,
        storyViewedStatus: [],
        storyAudiences: []
    )

    private var isOwnStory: Bool {
        story.authorId == Auth.auth().currentUser?.uid
    }

    var body: some View {
        Group {
            if let previewURL = story.previewURL, let url = URL(string: previewURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .overlay(
                        Image(systemName: "sparkles")
                            .foregroundColor(.white)
                    )
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(Circle())
        .overlay(
            StorySegmentedRing(
                storyCount: max(snapshot.storyCount, 1),
                hasStory: true,
                hasUnseenStory: snapshot.hasUnseenStory,
                storyViewedStatus: snapshot.storyViewedStatus,
                storyAudiences: snapshot.storyAudiences,
                isOwnStory: isOwnStory,
                colorScheme: colorScheme,
                ringSize: ringSize,
                lineWidth: 3,
                hapticsEnabled: false
            )
        )
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        .onAppear {
            resolveSnapshot()
        }
        .onChange(of: story.authorId) { _, _ in
            resolveSnapshot()
        }
    }

    private func resolveSnapshot() {
        guard let viewerId = Auth.auth().currentUser?.uid, !viewerId.isEmpty else { return }

        StoryRingResolverService.shared.resolve(
            viewerId: viewerId,
            authorId: story.authorId,
            privacyService: privacyService
        ) { resolvedSnapshot in
            snapshot = resolvedSnapshot.hasStory ? resolvedSnapshot : StoryRingSnapshot(
                hasStory: true,
                hasUnseenStory: true,
                storyCount: 1,
                storyViewedStatus: [false],
                storyAudiences: []
            )
        }
    }
}

struct MapFriendActivityPinView: View {
    let pin: MapFriendActivityPin
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 4) {
            StoryRingAvatarView(
                userId: pin.authorId,
                size: 42,
                lineWidth: 2.5,
                showBaseStroke: true,
                baseStrokeColor: Color.white.opacity(colorScheme == .dark ? 0.35 : 0.85),
                baseStrokeWidth: 2
            )

            Text(pin.username)
                .font(.custom("Poppins-SemiBold", size: 10))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}
