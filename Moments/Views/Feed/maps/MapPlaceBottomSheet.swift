import SwiftUI
import CoreLocation
import Kingfisher

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

    @State private var viewMode: MapPlaceSheetViewMode = .gallery

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    /// Modo índice: sheet agregado de la zona con varios lugares debajo.
    private var showsPlaceIndex: Bool {
        cluster.isAggregate && placeIndex.count > 1 && onPlaceTap != nil
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
            header
            if timeFilter != nil {
                timeFilterChips
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .onAppear {
            if showsPlaceIndex {
                viewMode = .list
            }
        }
        .onChange(of: cluster.id) { _, _ in
            viewMode = showsPlaceIndex ? .list : .gallery
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    // Si el lugar tiene story activa, el icono del header es el
                    // avatar con anillo (estilo página de lugar), tappable.
                    if cluster.primaryStory != nil {
                        Button {
                            onPlaceStoriesTap(cluster)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                StoryRingAvatarView(
                                    userId: cluster.primaryStory!.authorId,
                                    size: 40,
                                    lineWidth: 2.5
                                )

                                if cluster.storyCount > 1 {
                                    Text("\(cluster.storyCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(adaptiveColors.accent))
                                        .offset(x: 4, y: 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 40, height: 40)
                                .liquidGlass(in: Circle(), interactive: false)

                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }

                    Text(cluster.displayName)
                        .font(.custom("Poppins-Bold", size: 18))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(1)

                    if let weather {
                        weatherChip(weather)
                    }

                    Spacer()

                    if !cluster.moments.isEmpty {
                        viewModeToggle
                    }
                }

                HStack(spacing: 10) {
                    Text(statsText)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(adaptiveColors.secondary)
                        .lineLimit(1)

                    Spacer()

                    if !cluster.friends.isEmpty {
                        friendAvatarStack
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
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
                        .font(.custom("Poppins-SemiBold", size: 11))
                        .foregroundColor(
                            timeFilter?.wrappedValue == filter ? .white : adaptiveColors.secondary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if timeFilter?.wrappedValue == filter {
                                Capsule().fill(adaptiveColors.accent)
                            } else {
                                Color.clear.liquidGlass(in: Capsule(), interactive: true)
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
        HStack(spacing: 4) {
            Image(systemName: weather.condition.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(adaptiveColors.accent)
            Text(weather.temperatureFormatted)
                .font(.custom("Poppins-SemiBold", size: 11))
                .foregroundColor(adaptiveColors.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.clear.liquidGlass(in: Capsule(), interactive: false))
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
                        .foregroundColor(viewMode == mode ? .white : adaptiveColors.tertiary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    viewMode == mode ?
                                    LinearGradient(
                                        colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
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
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        } else if !hasContent {
            emptyView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsPlaceIndex && viewMode == .list {
                        placeIndexSection
                    } else if !cluster.moments.isEmpty {
                        if viewMode == .gallery {
                            galleryGrid
                        } else {
                            listSection
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var placeIndexSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("maps.zoneSheet.places", comment: "Places section title"))
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(adaptiveColors.primary)
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
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
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
            ForEach(cluster.moments) { moment in
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
        VStack(spacing: 16) {
            ProgressView().tint(adaptiveColors.accent)
            Text(NSLocalizedString("maps.bottomSheet.loading.moments", comment: ""))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.secondary)
        }
        .frame(height: 220)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("maps.bottomSheet.empty.title", comment: ""))
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(adaptiveColors.primary)
            Text(NSLocalizedString("maps.bottomSheet.empty.subtitle", comment: ""))
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(adaptiveColors.secondary)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(place.displayName)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(1)

                    if place.hasFreshStory {
                        Circle()
                            .fill(adaptiveColors.accent)
                            .frame(width: 7, height: 7)
                    }
                }

                Text(metadataText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.secondary)
                    .lineLimit(1)

                if place.storyCount > 0 {
                    Text(
                        String(
                            format: NSLocalizedString("maps.zoneSheet.storiesCount", comment: "Stories count in place row"),
                            place.storyCount
                        )
                    )
                    .font(.custom("Poppins-Medium", size: 11))
                    .foregroundColor(adaptiveColors.accent)
                }
            }

            Spacer(minLength: 8)

            previewStrip
        }
        .padding(12)
        .background(
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
        )
    }

    private var previewStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(place.moments.prefix(3).enumerated()), id: \.element.id) { _, moment in
                KFImage(URL(string: moment.mapPreferredImageURL ?? ""))
                    .placeholder {
                        Rectangle()
                            .fill(Color.gray.opacity(0.18))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if place.momentCount > 3 {
                Text("+\(place.momentCount - 3)")
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .foregroundColor(adaptiveColors.secondary)
                    .frame(width: 30, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.gray.opacity(0.12))
                    )
            }
        }
    }
}
