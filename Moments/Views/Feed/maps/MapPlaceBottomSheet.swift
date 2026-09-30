import SwiftUI
import CoreLocation
import Kingfisher
import WeatherKit

enum MapPlaceSheetViewMode: String, CaseIterable {
    case gallery
    case list

    var icon: String {
        switch self {
        case .gallery: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct MapPlaceBottomSheet: View {
    let cluster: MapPlaceCluster
    let momentAvailability: [String: Bool]
    let isLoading: Bool
    let colorScheme: ColorScheme
    var zoomNamespace: Namespace.ID? = nil
    let onMomentTap: (Moment) -> Void
    let onPlaceStoriesTap: (MapPlaceCluster) -> Void
    var weather: WeatherData?
    var userLocation: CLLocationCoordinate2D?
    var placeIndex: [MapPlaceCluster] = []
    var onPlaceTap: ((MapPlaceCluster) -> Void)?
    var timeFilter: Binding<MapDiscoverTimeFilter>?
    var onTimeFilterChange: (() -> Void)?
    var socialMode = false
    var showsStoryStrip = true
    var showsHeader = true
    var hasMoreContent = false
    var paginationKey: String? = nil
    var isLoadingMore = false
    var onLoadMore: (() -> Void)? = nil

    @State private var viewMode: MapPlaceSheetViewMode = .gallery
    @State private var displayTitle: String = ""

    private var controlColor: Color { colorScheme == .dark ? .white : .black }
    private var selectedControlColor: Color { colorScheme == .dark ? .black : .white }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    /// Zone browsing keeps its list of places, even when only one has content.
    private var showsPlaceIndex: Bool {
        !socialMode && cluster.isAggregate && !placeIndex.isEmpty && onPlaceTap != nil
    }

    private var statsText: String {
        if showsPlaceIndex {
            return String(
                format: NSLocalizedString("maps.zoneSheet.stats", comment: "Zone sheet stats"),
                placeIndex.count,
                cluster.momentCount
            )
        }
        if cluster.storyCount > 0 {
            return String(
                format: NSLocalizedString("maps.placeSheet.stats", comment: "Place sheet stats with stories"),
                cluster.momentCount,
                cluster.storyCount
            )
        }
        return String(
            format: NSLocalizedString("maps.bottomSheet.moments", comment: "Number of moments in location"),
            cluster.momentCount
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
            } else {
                contentControls
            }
            if timeFilter != nil {
                timeFilterChips
            }
            content
        }
        .tint(controlColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            viewMode = socialMode || showsPlaceIndex ? .list : .gallery
            refreshDisplayTitle()
        }
        .onChange(of: socialMode) { _, _ in
            viewMode = socialMode || showsPlaceIndex ? .list : .gallery
        }
        .onChange(of: cluster.id) { _, _ in
            viewMode = socialMode || showsPlaceIndex ? .list : .gallery
            refreshDisplayTitle()
        }
    }

    private func refreshDisplayTitle() {
        displayTitle = cluster.displayName
        MapLocationDisplayFormatter.resolveTitle(
            place: cluster.displayName,
            coordinate: cluster.coordinate
        ) { title in
            displayTitle = title
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center, spacing: 4) {
                if cluster.primaryStory != nil {
                    Button {
                        onPlaceStoriesTap(cluster)
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            StoryRingAvatarView(
                                userId: cluster.primaryStory!.authorId,
                                size: 44,
                                lineWidth: 2.5
                            )

                            if cluster.storyCount > 1 {
                                Text("\(cluster.storyCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(selectedControlColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(controlColor))
                                    .offset(x: 4, y: 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }

                Text(displayTitle.isEmpty ? cluster.displayName : displayTitle)
                    .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(statsText)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(adaptiveColors.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            contentControls
        }
    }

    // Content shares the panel's material; these controls add no glass layer.
    private var contentControls: some View {
        HStack(spacing: 10) {
            if let weather { weatherChip(weather) }
            if !cluster.friends.isEmpty { friendAvatarStack }
            Spacer()
            if !showsPlaceIndex && !cluster.moments.isEmpty { viewModeToggle }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var timeFilterChips: some View {
        HStack(spacing: 8) {
            ForEach(MapDiscoverTimeFilter.allCases) { filter in
                Button {
                    guard let timeFilter else { return }
                    timeFilter.wrappedValue = filter
                    onTimeFilterChange?()
                } label: {
                    Text(NSLocalizedString(filter.titleKey, comment: "Map time filter"))
                        .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                        .foregroundStyle(
                            timeFilter?.wrappedValue == filter ? selectedControlColor : adaptiveColors.secondary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if timeFilter?.wrappedValue == filter {
                                Capsule().fill(controlColor)
                            } else {
                                Capsule().fill(adaptiveColors.secondary.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var hasContent: Bool {
        !cluster.moments.isEmpty || !cluster.stories.isEmpty
    }

    private func weatherChip(_ weather: WeatherData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: weather.condition.systemImageName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(controlColor)
                Text(weather.temperatureFormatted)
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                    .foregroundStyle(adaptiveColors.secondary)
            }
            MapWeatherAttributionView()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(MapPlaceSheetViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = mode
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(viewMode == mode ? selectedControlColor : adaptiveColors.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    viewMode == mode ?
                                    LinearGradient(
                                        colors: [controlColor, controlColor.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(colors: [Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(adaptiveColors.secondary.opacity(0.08))
        )
    }

    private var friendAvatarStack: some View {
        HStack(spacing: -10) {
            ForEach(cluster.friends.prefix(3)) { friend in
                StoryRingAvatarView(userId: friend.authorId, size: 30, lineWidth: 1.5)
                    .overlay(Circle().stroke(adaptiveColors.background.opacity(0.9), lineWidth: 2))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if !hasContent && !hasMoreContent {
            emptyView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if showsStoryStrip && !showsPlaceIndex && !cluster.stories.isEmpty { socialStories }
                    if showsPlaceIndex && viewMode == .list {
                        placeIndexSection
                    } else if !cluster.moments.isEmpty {
                        if viewMode == .gallery {
                            galleryGrid
                        } else {
                            listSection
                        }
                    }
                    if hasMoreContent {
                    Button(action: { onLoadMore?() }) {
                        if isLoadingMore { ProgressView() }
                        else { Text(NSLocalizedString("global.seeMore", comment: "")) }
                    }
                    .disabled(isLoadingMore)
                    .padding(.bottom, 20)
                    .id(paginationKey)
                    .frame(maxWidth: .infinity)
                    .onAppear { onLoadMore?() }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var socialStoryAuthors: [MapStoryPreview] {
        var authors = Set<String>()
        return cluster.stories.sorted { $0.timestamp > $1.timestamp }
            .filter { authors.insert($0.authorId).inserted }
    }

    private var socialStories: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(socialStoryAuthors) { story in
                    Button {
                        onPlaceStoriesTap(MapPlaceCluster(
                            id: "\(cluster.id)-\(story.authorId)",
                            coordinate: cluster.coordinate,
                            displayName: cluster.displayName,
                            moments: [],
                            stories: cluster.stories.filter { $0.authorId == story.authorId },
                            friends: []
                        ))
                    } label: {
                        VStack(spacing: 6) {
                            StoryRingAvatarView(userId: story.authorId, size: 48, lineWidth: 2)
                            LiveUsernameText(userId: story.authorId, fallbackUsername: story.username, prefix: "@")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(adaptiveColors.primary)
                        }
                        .frame(width: 80)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var placeIndexSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("maps.zoneSheet.places", comment: "Places section title"))
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
                .padding(.horizontal, 20)

            LazyVStack(spacing: 12) {
                ForEach(placeIndex) { place in
                    Button {
                        onPlaceTap?(place)
                    } label: {
                        MapPlaceIndexRow(
                            place: place,
                            userLocation: userLocation,
                            colorScheme: colorScheme
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var galleryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112, maximum: 180), spacing: 1)],
                spacing: 1
            ) {
                ForEach(Array(cluster.moments.enumerated()), id: \.element.id) { index, moment in
                    let isAvailable = momentAvailability[moment.mapAvailabilityKey] ?? true
                    Button {
                        onMomentTap(moment)
                    } label: {
                        MapBottomSheetGridCell(
                            moment: moment,
                            colorScheme: colorScheme,
                            isAvailable: isAvailable
                        )
                    }
                    .buttonStyle(.plain)
                    .modifier(ProfileMomentZoomSourceModifier(
                        namespace: zoomNamespace,
                        sourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, index: index, prefix: "map"),
                        cornerRadius: 2
                    ))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var listSection: some View {
        LazyVStack(spacing: 16) {
            ForEach(cluster.moments.sorted { $0.timestamp > $1.timestamp }) { moment in
                ModernLocationMomentRow(
                    moment: moment,
                    colorScheme: colorScheme,
                    isAvailable: momentAvailability[moment.mapAvailabilityKey] ?? true,
                    onTap: onMomentTap
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private var loadingView: some View {
        LocationMomentCardSkeletonView()
            .padding(.horizontal, 20)
            .frame(height: 220)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("maps.bottomSheet.empty.title", comment: ""))
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
            Text(NSLocalizedString("maps.bottomSheet.empty.subtitle", comment: ""))
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundStyle(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(height: 220)
    }
}

/// Fila del índice de lugares en el sheet agregado de zona.
struct MapPlaceIndexRow: View {
    let place: MapPlaceCluster
    let userLocation: CLLocationCoordinate2D?
    let colorScheme: ColorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var metadataText: String {
        var parts: [String] = []

        if let distance = MapDistanceFormatter.string(from: userLocation, to: place.coordinate) {
            parts.append(distance)
        }
        parts.append(MapRelativeTimeFormatter.string(from: place.latestTimestamp))
        parts.append(
            String(
                format: NSLocalizedString("maps.bottomSheet.moments", comment: "Number of moments"),
                place.momentCount
            )
        )

        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let story = place.primaryStory {
                    StoryRingAvatarView(userId: story.authorId, size: 40, lineWidth: 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(adaptiveColors.primary)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(adaptiveColors.secondary)
                        .lineLimit(2)
                    if place.storyCount > 0 {
                        Text(String(format: NSLocalizedString("maps.zoneSheet.storiesCount", comment: ""), place.storyCount))
                            .font(.caption)
                            .foregroundStyle((colorScheme == .dark ? Color.white : Color.black))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(adaptiveColors.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(place.moments.prefix(3)) { moment in
                    KFImage(URL(string: moment.mapPreferredImageURL ?? ""))
                        .placeholder { Color.gray.opacity(0.18) }
                        .applyingFeedCrop(moment.mapPreferredFeedCrop)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ForEach(place.stories.prefix(max(0, 3 - place.momentCount))) { story in
                    KFImage(URL(string: story.previewURL ?? ""))
                        .placeholder { Color.gray.opacity(0.18) }
                        .resizable()
                        .scaledToFill()
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Divider()
        }
        .contentShape(Rectangle())
    }
}

/// WeatherKit's legal link stays next to the data, independent of visual weather effects.
private struct MapWeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    private var fallbackURL: URL { URL(string: "https://weatherkit.apple.com/legal-attribution.html")! }

    var body: some View {
        Link(destination: attribution?.legalPageURL ?? fallbackURL) {
            HStack(spacing: 4) {
                Text(NSLocalizedString("weather.attribution.text", comment: ""))
                if let attribution {
                    AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(NSLocalizedString("weather.attribution.link", comment: ""))
                    }
                    .frame(width: 68, height: 12)
                } else {
                    Text(NSLocalizedString("weather.attribution.link", comment: ""))
                }
            }
            .font(.caption2)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        }
        .task {
            attribution = try? await WeatherKit.WeatherService.shared.attribution
        }
    }
}
