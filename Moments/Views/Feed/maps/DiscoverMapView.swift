import SwiftUI
import MapKit
import Kingfisher
import FirebaseAuth
import FirebaseFirestore

struct DiscoverMapView: View {
    @Binding var isPresented: Bool
    var initialLocationName: String? = nil
    var initialCoordinate: CLLocationCoordinate2D? = nil
    var originMoment: Moment? = nil
    @State private var hasBootstrapped = false
    // Post entry searches the viewer's following graph; See more opts into
    // discovery. Browsing a zone/place does not itself change that scope.
    @State private var isSocialMap = false
    @State private var isBrowsingPlaces = false
    @State private var zoneRegion: MKCoordinateRegion?
    @State private var originPinCoordinate: CLLocationCoordinate2D?
    @State private var originDetailToken = UUID()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationManager = LocationUtilities.shared
    @StateObject private var locationGate = LocationPermissionGate()
    @State private var mapPosition = MapCameraPosition.region(MapRegionStore.initialRegion())
    @State private var region = MapRegionStore.initialRegion()

    @State private var moments: [Moment] = []
    @State private var stories: [MapStoryPreview] = []
    @State private var friendPins: [MapFriendActivityPin] = []
    @State private var followingIds: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasRecoverableError = false
    @State private var showingBottomSheet = false
    @State private var mapSheetDetent: PresentationDetent = MapLocationSystemSheetModifier.collapsedDetent
    @State private var mapPanelHeight: CGFloat = 80
    @Namespace private var zoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var zoomMapMomentsPool: [Moment] = []
    @State private var isMapDetailPresented = false
    @State private var pendingStoryPresentation: MapStoryViewerPresentation?
    @State private var resumeBottomSheetAfterDetail = false
    @State private var selectedPlaceCluster: MapPlaceCluster?
    @State private var selectedMomentIndex = 0
    @State private var storyViewerPresentation: MapStoryViewerPresentation?
    @State private var isOpeningStory = false
    @State private var hasPerformedInitialSearch = false
    @State private var timeFilter: MapDiscoverTimeFilter = .all
    @State private var zoneName: String?
    @State private var discoverWeather: WeatherData?
    @State private var weatherEffectsEnabled = false
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var searchFieldFocused: Bool
    @State private var isViewActive = true
    @State private var lastSearchedRegionKey = ""
    @State private var regionSearchToken = UUID()
    @State private var zonePaginationState: ZonePaginationState?
    private struct ZonePaginationState {
        let region: MKCoordinateRegion?
        let momentsCursor: String?
        let storiesCursor: String?
    }
    @State private var paginationToken = UUID()
    @State private var paginationRegion: MKCoordinateRegion?
    @State private var paginationLocationName: String?
    @State private var paginationFollowingOnly = false
    @State private var momentsCursor: String?
    @State private var storiesCursor: String?
    @State private var isLoadingNextPage = false
    @State private var lastSearchDate = Date.distantPast
    @State private var needsLocationSelection = false

    private struct MapStoryViewerPresentation: Identifiable {
        let id = UUID()
        let previews: [MapStoryPreview]
        let initialPreviewId: String?
    }

    private var mapPlaceLayout: MapPlaceLayout {
        MapPlaceClusterEngine.build(
            moments: filteredMoments,
            stories: filteredStories,
            friendPins: [],
            filter: .all,
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
        var result = moments
        if let cutoff = timeFilter.cutoffDate {
            result = result.filter { $0.timestamp >= cutoff }
        }
        return result
    }

    private var filteredStories: [MapStoryPreview] {
        var result = stories
        if let cutoff = timeFilter.cutoffDate {
            result = result.filter { $0.timestamp >= cutoff }
        }
        return result
    }

    private var showsWeatherEffects: Bool {
        weatherEffectsEnabled && discoverWeather != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
            Map(position: $mapPosition) {
                if !isSocialMap, let originMoment, let coordinate = originPinCoordinate {
                    Annotation(initialLocationName ?? originMoment.location ?? "", coordinate: coordinate) {
                        VStack(spacing: 6) {
                            Button {
                                openMomentDetail(at: 0, in: [originMoment], title: initialLocationName ?? originMoment.location ?? "")
                            } label: {
                                MapMomentPin(moment: originMoment, colorScheme: colorScheme, count: 1)
                                    .scaleEffect(originPinScale)
                            }
                            .buttonStyle(.plain)
                            Button(action: openOriginPlace) {
                                VStack(spacing: 3) {
                                    Text(initialLocationName ?? originMoment.location ?? "").lineLimit(1)
                                    Text(NSLocalizedString("global.seeMore", comment: "")).fontWeight(.semibold)
                                }
                                .font(.caption)
                                .padding(8)
                                .background(adaptiveColors.surfaceBackground, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(mapPlaceLayout.placeClusters.filter { cluster in
                    isSocialMap || originMoment == nil || !cluster.moments.contains { $0.mapAvailabilityKey == originMoment?.mapAvailabilityKey }
                }) { cluster in
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
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve the panel footprint so MapKit positions its own logo/legal controls above it.
                Color.clear
                    .frame(height: showingBottomSheet ? mapPanelHeight + 12 : 0)
                    .allowsHitTesting(false)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                MapRegionStore.save(region: context.region)
                // Camera movement only reveals the explicit area-search action.
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

            MapImmersiveChrome(
                title: needsLocationSelection ? NSLocalizedString("maps.chrome.chooseCity", comment: "") : (zoneName ?? NSLocalizedString("maps.chrome.nearby", comment: "")),
                subtitle: headerSubtitle,
                isLoading: isLoading,
                searchText: $searchText,
                onClose: closeDiscoverMap,
                onSearch: performPlaceSearch,
                onRecenter: recenterOnUser,
                onOpenContent: {},
                showsSearchArea: !isLoading && hasPerformedInitialSearch && (!isBrowsingPlaces || MapViewportQuery.key(for: region) != lastSearchedRegionKey),
                onSearchArea: browseCurrentArea,
                showsDock: false,
                panelHeight: mapPanelHeight
            )
            .zIndex(20)
            if let errorMessage {
                VStack {
                    discoverErrorBanner(message: errorMessage)
                        .padding(.horizontal, 16)
                        .padding(.top, 68)
                    Spacer()
                }
                .zIndex(21)
            }
            }
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace,
                    mapDetailPresented: $isMapDetailPresented
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .momentZoomNavigationSurface(colorScheme: colorScheme)
        .momentsFloatingTabBarHidden()
        .sheet(isPresented: $showingBottomSheet) {
            MapImmersivePanel(
                title: needsLocationSelection ? NSLocalizedString("maps.chrome.chooseCity", comment: "") : (selectedPlaceCluster?.displayName ?? (!isBrowsingPlaces ? initialLocationName : nil) ?? zoneName ?? NSLocalizedString("maps.chrome.nearby", comment: "")),
                subtitle: selectedPlaceSubtitle,
                isLoading: isLoading,
                detent: $mapSheetDetent,
                onBack: selectedPlaceCluster != nil ? returnToZone : nil,
                storyCover: sheetCluster.primaryStory,
                locationMoment: sheetCluster.primaryMoment,
                onStoriesTap: { openPlaceStories(sheetCluster) }
            ) {
            MapPlaceBottomSheet(
                cluster: sheetCluster,
                momentAvailability: [:],
                isLoading: isLoading,
                colorScheme: colorScheme,
                zoomNamespace: zoomNamespace,
                onMomentTap: { moment in
                    guard let index = sheetCluster.moments.firstIndex(where: { $0.id == moment.id }) else { return }
                    openMomentDetail(at: index, in: sheetCluster.moments, title: sheetCluster.displayName)
                },
                onPlaceStoriesTap: { cluster in
                    openPlaceStories(cluster)
                },
                weather: discoverWeather,
                userLocation: locationManager.usableCurrentLocation?.coordinate,
                placeIndex: isBrowsingPlaces && selectedPlaceCluster == nil ? mapPlaceLayout.placeClusters : [],
                onPlaceTap: { place in
                    selectPlaceFromIndex(place)
                },
                socialMode: !isBrowsingPlaces && selectedPlaceCluster == nil,
                showsStoryStrip: false,
                showsHeader: false,
                hasMoreContent: momentsCursor != nil || storiesCursor != nil,
                paginationKey: "\(momentsCursor ?? "")|\(storiesCursor ?? "")",
                isLoadingMore: isLoadingNextPage,
                onLoadMore: loadNextContentPage
            )
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                mapPanelHeight = height
            }
            .mapLocationSystemSheet(detent: $mapSheetDetent)
        }
        .onChange(of: showingBottomSheet) { _, isShowing in
            if !isShowing { presentDeferredMapContent() }
        }
        .onAppear {
            isViewActive = true
            guard !hasBootstrapped else { restoreBottomSheetIfNeeded(); return }
            hasBootstrapped = true
            showingBottomSheet = true
            isSocialMap = originMoment == nil
            if isSocialMap { isBrowsingPlaces = true }
            if let initialLocationName {
                if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.requestLocationPermission()
                }
                bootstrapOriginPlace(name: initialLocationName)
            } else {
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.requestLocationPermission()
                bootstrapMapCenter()
            case .notDetermined:
                applyFallbackRegion(andSearch: true)
                locationGate.requestAccess {
                    locationManager.requestLocationPermission()
                    bootstrapMapCenter()
                }
            default:
                applyFallbackRegion(andSearch: true)
            }
            }
        }
        .locationPermissionGate(locationGate)
        .onDisappear {
            isViewActive = false
        }
        .onChange(of: zoomDestination) { _, newValue in
            if newValue == nil {
                zoomMapMomentsPool = []
                restoreBottomSheetIfNeeded()
            }
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

    private func closeDiscoverMap() {
        isViewActive = false
        searchFieldFocused = false
        showingBottomSheet = false
        zoomDestination = nil
        storyViewerPresentation = nil
        pendingStoryPresentation = nil
        isPresented = false
        dismiss()
    }

    private func clusterAccessibilityLabel(for cluster: MapPlaceCluster) -> String {
        String(
            format: NSLocalizedString("maps.pin.accessibility", comment: "Map pin accessibility label"),
            cluster.displayName,
            cluster.totalCount
        )
    }

    private var selectedPlaceSubtitle: String {
        let stats = String(format: NSLocalizedString("maps.placeSheet.stats", comment: ""), sheetCluster.momentCount, sheetCluster.storyCount)
        guard let coordinate = selectedPlaceCluster?.coordinate ?? (!isSocialMap ? originPinCoordinate : nil),
              let distance = MapDistanceFormatter.string(from: locationManager.usableCurrentLocation?.coordinate, to: coordinate) else { return stats }
        return "\(distance) · \(stats)"
    }

    private func bootstrapOriginPlace(name: String) {
        if let originMoment {
            moments = [originMoment]
            hasPerformedInitialSearch = true
        }
        if let coordinate = initialCoordinate ?? originMoment?.locationCoordinate?.toCLLocationCoordinate2D {
            originPinCoordinate = coordinate
            focus(on: coordinate, autoSearch: originMoment == nil)
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            MKLocalSearch(request: request).start { response, _ in
                DispatchQueue.main.async {
                    guard isViewActive else { return }
                    guard let coordinate = response?.mapItems.first?.placemark.coordinate else {
                        applyFallbackRegion(andSearch: originMoment == nil)
                        return
                    }
                    originPinCoordinate = coordinate
                    focus(on: coordinate, autoSearch: originMoment == nil)
                }
            }
        }
    }

    private func browseCurrentArea() {
        originDetailToken = UUID()
        selectedPlaceCluster = nil
        isBrowsingPlaces = true
        zoneRegion = region
        mapSheetDetent = MapLocationSystemSheetModifier.middleDetent
        showingBottomSheet = true
        performRegionSearch(force: true)
    }

    private func returnToZone() {
        originDetailToken = UUID()
        selectedPlaceCluster = nil
        isBrowsingPlaces = true
        paginationToken = UUID()
        paginationLocationName = nil
        paginationFollowingOnly = !isSocialMap
        paginationRegion = zonePaginationState?.region
        momentsCursor = zonePaginationState?.momentsCursor
        storiesCursor = zonePaginationState?.storiesCursor
        isLoadingNextPage = false
        isBrowsingPlaces = zonePaginationState != nil || originMoment == nil
        if let zoneRegion {
            region = zoneRegion
            mapPosition = .region(zoneRegion)
        }
        mapSheetDetent = MapLocationSystemSheetModifier.middleDetent
    }

    private var originPinScale: CGFloat {
        CGFloat(min(1.18, max(0.72, pow(0.06 / max(region.span.latitudeDelta, 0.00001), 0.12))))
    }

    private func openOriginPlace() {
        isSocialMap = true
        browseCurrentArea()
    }

    private func bootstrapMapCenter() {
        if let coordinate = locationManager.usableCurrentLocation?.coordinate {
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
                needsLocationSelection = true
                region = fallbackRegion
                mapPosition = .region(fallbackRegion)
                if andSearch {
                    performRegionSearch()
                }
            }
        }
    }

    private func recenterOnUser() {
        guard locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse else {
            locationGate.requestAccess { bootstrapMapCenter() }
            return
        }
        if let coordinate = locationManager.usableCurrentLocation?.coordinate {
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
        needsLocationSelection = false
        region = nextRegion
        mapPosition = .region(nextRegion)
        MapRegionStore.save(region: nextRegion)
        if autoSearch {
            performRegionSearch()
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
        originDetailToken = UUID()
        isBrowsingPlaces = true
        if zoneRegion == nil { zoneRegion = region }
        selectedPlaceCluster = place
        startPlacePagination(name: place.displayName)
        mapSheetDetent = MapLocationSystemSheetModifier.middleDetent
        let nextRegion = MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .region(nextRegion)
        }
    }

    private func refreshZoneContext() {
        let token = regionSearchToken
        MapZoneContextService.shared.zoneName(for: region.center) { name in
            guard isViewActive, regionSearchToken == token else { return }
            zoneName = name
        }

        let center = region.center
        Task {
            let weather = await WeatherService.shared.getWeatherSafely(for: center)
            await MainActor.run {
                guard isViewActive, regionSearchToken == token else { return }
                discoverWeather = weather
            }
        }
    }

    private func performRegionSearch(force: Bool = false) {
        guard originMoment == nil || isBrowsingPlaces else { return }
        let key = MapViewportQuery.key(for: region)
        guard force || key != lastSearchedRegionKey || (!isLoading && Date().timeIntervalSince(lastSearchDate) > 30) else { return }
        let token = UUID()
        let queriedRegion = region
        let selectionToken = originDetailToken
        regionSearchToken = token
        lastSearchedRegionKey = key
        lastSearchDate = Date()
        paginationToken = token
        paginationRegion = queriedRegion
        zonePaginationState = nil
        paginationLocationName = nil
        paginationFollowingOnly = !isSocialMap
        momentsCursor = nil
        storiesCursor = nil
        isLoadingNextPage = false
        isLoading = true
        errorMessage = nil
        hasRecoverableError = false
        refreshZoneContext()

        LocationSearchService.shared.searchContentPage(region: paginationRegion, followingOnly: paginationFollowingOnly) { payload in
            guard isViewActive, regionSearchToken == token else { return }
            if payload.isCompleteFailure { lastSearchedRegionKey = "" }
            if paginationToken == token {
                momentsCursor = payload.momentsCursor
                storiesCursor = payload.storiesCursor
            } else if zonePaginationState != nil {
                zonePaginationState = ZonePaginationState(region: queriedRegion,
                    momentsCursor: payload.momentsCursor, storiesCursor: payload.storiesCursor)
            }
            if !payload.isCompleteFailure {
                moments = payload.moments
                stories = payload.stories
                friendPins = LocationSearchService.shared.buildFriendActivityPins(
                    moments: payload.moments,
                    stories: payload.stories,
                    followingIds: followingIds
                )
            }
            isLoading = false
            hasPerformedInitialSearch = true
            if payload.isCompleteFailure {
                errorMessage = NSLocalizedString("maps.error.mapUnavailable", comment: "Map content unavailable")
                hasRecoverableError = true
                if selectedPlaceCluster == nil { mapSheetDetent = MapLocationSystemSheetModifier.collapsedDetent }
            } else if payload.moments.isEmpty && payload.stories.isEmpty && momentsCursor == nil && storiesCursor == nil {
                errorMessage = NSLocalizedString("maps.discover.empty", comment: "Discover map empty state")
                hasRecoverableError = false
                if selectedPlaceCluster == nil { mapSheetDetent = MapLocationSystemSheetModifier.collapsedDetent }
            } else if payload.hasPartialFailure {
                errorMessage = NSLocalizedString("maps.error.mapPartialContent", comment: "Map partial content warning")
                hasRecoverableError = false
                if originDetailToken == selectionToken {
                    selectedPlaceCluster = nil
                    updateBottomSheetForCurrentFilter()
                }
            } else {
                errorMessage = nil
                hasRecoverableError = false
                if originDetailToken == selectionToken {
                    selectedPlaceCluster = nil
                    updateBottomSheetForCurrentFilter()
                }
            }
            if !payload.hasContent && !payload.isCompleteFailure && (momentsCursor != nil || storiesCursor != nil) {
                loadNextContentPage()
            }
        }
    }

    private func startPlacePagination(name: String) {
        if paginationLocationName == nil, paginationRegion != nil {
            zonePaginationState = ZonePaginationState(region: paginationRegion,
                momentsCursor: momentsCursor, storiesCursor: storiesCursor)
        }
        paginationToken = UUID()
        paginationLocationName = name
        paginationRegion = nil
        paginationFollowingOnly = !isSocialMap
        momentsCursor = nil
        storiesCursor = nil
        isLoadingNextPage = true
        fetchContentPage(firstPage: true)
    }

    private func loadNextContentPage() {
        guard !isLoadingNextPage, momentsCursor != nil || storiesCursor != nil else { return }
        isLoadingNextPage = true
        fetchContentPage(firstPage: false)
    }

    private func fetchContentPage(firstPage: Bool) {
        let token = paginationToken
        let placeID = selectedPlaceCluster?.id
        LocationSearchService.shared.searchContentPage(
            region: paginationRegion, locationName: paginationLocationName,
            followingOnly: paginationFollowingOnly,
            momentsCursor: momentsCursor, storiesCursor: storiesCursor,
            loadMoments: firstPage || momentsCursor != nil,
            loadStories: firstPage || storiesCursor != nil
        ) { payload in
            guard isViewActive, paginationToken == token else { return }
            isLoadingNextPage = false
            if payload.momentsError == nil { momentsCursor = payload.momentsCursor }
            if payload.storiesError == nil { storiesCursor = payload.storiesCursor }
            if payload.momentsError != nil || payload.storiesError != nil {
                errorMessage = NSLocalizedString("maps.error.mapPartialContent", comment: "")
            }
            func mergedMoments(_ existing: [Moment]) -> [Moment] {
                var keys = Set<String>()
                return (existing + payload.moments).filter { keys.insert($0.mapAvailabilityKey).inserted }
                    .sorted { $0.timestamp > $1.timestamp }
            }
            func mergedStories(_ existing: [MapStoryPreview]) -> [MapStoryPreview] {
                var keys = Set<String>()
                return (existing + payload.stories).filter { keys.insert("\($0.authorId)|\($0.id)").inserted }
                    .sorted { $0.timestamp > $1.timestamp }
            }
            if let place = selectedPlaceCluster, place.id == placeID {
                selectedPlaceCluster = MapPlaceCluster(id: place.id, coordinate: place.coordinate,
                    displayName: place.displayName, moments: mergedMoments(place.moments),
                    stories: mergedStories(place.stories), friends: place.friends)
            } else if placeID == nil {
                moments = mergedMoments(moments)
                stories = mergedStories(stories)
                friendPins = LocationSearchService.shared.buildFriendActivityPins(
                    moments: moments, stories: stories, followingIds: followingIds)
            }
            if payload.momentsError == nil && payload.storiesError == nil && sheetCluster.totalCount == 0 {
                loadNextContentPage()
            }
        }
    }

    private func retryCurrentMapQuery() {
        errorMessage = nil
        if let name = paginationLocationName {
            if momentsCursor == nil && storiesCursor == nil {
                startPlacePagination(name: name)
            } else {
                loadNextContentPage()
            }
        } else {
            performRegionSearch(force: true)
        }
    }

    private func discoverErrorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(adaptiveColors.primary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                retryCurrentMapQuery()
            } label: {
                Text(NSLocalizedString("maps.error.retry", comment: "Retry button text"))
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
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
                .foregroundStyle(adaptiveColors.primary)

            Text(message)
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(adaptiveColors.primary)
                .multilineTextAlignment(.center)

            Button {
                retryCurrentMapQuery()
            } label: {
                Text(NSLocalizedString("maps.error.retry", comment: "Retry button text"))
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(adaptiveColors.primary)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func updateBottomSheetForCurrentFilter() {
        if filteredMoments.isEmpty && filteredStories.isEmpty && momentsCursor == nil && storiesCursor == nil {
            mapSheetDetent = MapLocationSystemSheetModifier.collapsedDetent
        }
    }

    private func openPlaceCluster(_ cluster: MapPlaceCluster) {
        originDetailToken = UUID()
        isBrowsingPlaces = true
        if zoneRegion == nil { zoneRegion = region }
        selectedPlaceCluster = cluster
        startPlacePagination(name: cluster.displayName)
        mapSheetDetent = MapLocationSystemSheetModifier.middleDetent
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

        zonePaginationState = ZonePaginationState(region: paginationRegion,
            momentsCursor: momentsCursor, storiesCursor: storiesCursor)
        paginationToken = UUID()
        paginationRegion = nil
        paginationLocationName = nil
        momentsCursor = nil
        storiesCursor = nil
        isLoadingNextPage = false
        selectedPlaceCluster = cluster
        mapSheetDetent = MapLocationSystemSheetModifier.middleDetent
        showingBottomSheet = true
    }

    private func openMomentDetail(at index: Int, in moments: [Moment], title: String) {
        selectedMomentIndex = index
        guard moments.indices.contains(index) else { return }
        let moment = moments[index]
        isMapDetailPresented = true
        if showingBottomSheet {
            resumeBottomSheetAfterDetail = true
            showingBottomSheet = false
        }
        zoomMapMomentsPool = moments
        MomentZoomOpener.open(
            moment: moment,
            moments: moments,
            initialIndex: index,
            presentation: .map(locationName: title),
            destination: &zoomDestination,
            zoomIDPrefix: "discover-map"
        )
    }

    private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
        MomentZoomOpener.resolvedMoments(for: destination, in: zoomMapMomentsPool)
    }

    private func presentDeferredMapContent() {
        guard pendingStoryPresentation != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + MapSheetPresentationDelay.dismissBeforeNextPresentation) {
            guard isViewActive else { return }

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
            initialPreviewId: preview?.id
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
                guard let snapshot else { return }
                let ids = Set(snapshot.documents.map { document in
                    let storedUserId = document.data()["userId"] as? String
                    return storedUserId ?? document.documentID
                })
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
                            .foregroundStyle(.white)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AdaptiveColors(colorScheme: colorScheme).primary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground)
                .clipShape(Capsule())
        }
    }
}
