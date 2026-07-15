import SwiftUI
import FirebaseAuth
import Kingfisher
import FirebaseFirestore
import MapKit
import CoreLocation

struct ArchiveView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ArchiveViewModel()
    @State private var storyViewerPresentation: StoryViewerPresentation?
    @State private var storyStatsPresentation: StoryStatsPresentation?
    @State private var highlightedActivityStoryId: String?
    @State private var archiveStoryCardFrames: [String: CGRect] = [:]
    @State private var selectedDisplayMode: ArchiveDisplayMode = .stories
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20.0, longitude: 0.0),
            span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100)
        )
    )
    @State private var geocodedCoordinatesByStoryId: [String: CLLocationCoordinate2D] = [:]
    @State private var isResolvingMapCoordinates = false
    @State private var navigateToArchivedMoments = false
    private let embedInNavigation: Bool
    private let showsCustomDismiss: Bool
    private let sectionHorizontalPadding: CGFloat = 12

    private struct StoryViewerPresentation: Identifiable {
        let id = UUID()
        let stories: [Story]
        let initialIndex: Int
    }

    private struct StoryStatsPresentation: Identifiable {
        let id = UUID()
        let story: Story
    }
    
    enum ArchiveDisplayMode: String, CaseIterable, Identifiable {
        case stories
        case calendar
        case map

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .stories: return "archivedStories.mode.stories"
            case .calendar: return "archivedStories.mode.calendar"
            case .map: return "archivedStories.mode.map"
            }
        }
    }

    init(embedInNavigation: Bool = false, showsCustomDismiss: Bool = true) {
        self.embedInNavigation = embedInNavigation
        self.showsCustomDismiss = showsCustomDismiss
    }
    
    var body: some View {
        Group {
            if embedInNavigation {
                NavigationStack {
                    archiveContent
                }
            } else {
                archiveContent
            }
        }
    }

    private var archiveContent: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()

            if viewModel.isLoading {
                ScrollView {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)

                        Text("archivedStories.loading")
                            .font(.system(size: legacyPoppinsSize(16)))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                }
                .momentRefresh {
                    await reloadArchivedStories()
                }
            } else if viewModel.groupedStories.isEmpty {
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 60))
                            .foregroundStyle(.gray.opacity(0.5))

                        VStack(spacing: 8) {
                            Text("archivedStories.empty.title")
                                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)

                            Text("archivedStories.empty.description")
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 400)
                }
                .momentRefresh {
                    await reloadArchivedStories()
                }
            } else {
                VStack(spacing: 0) {
                    switch selectedDisplayMode {
                    case .stories:
                        if storiesForGrid.isEmpty {
                            ScrollView {
                                archiveEmptyView(
                                    icon: "tray",
                                    text: NSLocalizedString("archivedStories.empty.description", comment: "No archived stories")
                                )
                                .frame(maxWidth: .infinity, minHeight: 400)
                            }
                            .momentRefresh {
                                await reloadArchivedStories()
                            }
                        } else {
                            ScrollView {
                                ZStack(alignment: .topLeading) {
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                                        spacing: 1
                                    ) {
                                        ForEach(storiesForGrid) { story in
                                            ArchiveStorySquareCard(
                                                story: story,
                                                isLifted: highlightedActivityStoryId == story.id,
                                                onTap: {
                                                    storyViewerPresentation = StoryViewerPresentation(
                                                        stories: [story],
                                                        initialIndex: 0
                                                    )
                                                },
                                                onStatsTap: {
                                                    presentStoryActivity(for: story)
                                                }
                                            )
                                        }
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 20)

                                    if let storyId = highlightedActivityStoryId,
                                       let frame = archiveStoryCardFrames[storyId],
                                       let story = storiesForGrid.first(where: { $0.id == storyId }) {
                                        ArchiveStoryLiftedPreview(story: story, frame: frame)
                                            .zIndex(2)
                                            .transition(.identity)
                                    }
                                }
                                .coordinateSpace(name: "archiveStoryGrid")
                            }
                            .onPreferenceChange(ArchiveStoryCardFrameKey.self) { frames in
                                archiveStoryCardFrames = frames
                            }
                            .momentRefresh {
                                await reloadArchivedStories()
                            }
                        }
                    case .calendar:
                        archiveCalendarView
                    case .map:
                        archiveMapView
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCustomDismiss)
        .navigationInteractivePopEnabled()
        .settingsSubsectionNavigationChrome(colorScheme: colorScheme)
        .toolbar {
            if embedInNavigation {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Label(NSLocalizedString("archivedStories.headerTitle", comment: "Archive Stories header title"), systemImage: "checkmark")

                        Button {
                            navigateToArchivedMoments = true
                        } label: {
                            Text(NSLocalizedString("userActivity.simple.item.archived.headerTitle", comment: "Archived moments header title"))
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(NSLocalizedString("archivedStories.headerTitle", comment: "Archive Stories header title"))
                                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                }
            }

            if showsCustomDismiss {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDisplayMode = (selectedDisplayMode == .calendar) ? .stories : .calendar
                        }
                    } label: {
                        Image(systemName: selectedDisplayMode == .calendar ? "calendar.circle.fill" : "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selectedDisplayMode == .calendar ? Color(hex: "0A84FF") : (colorScheme == .dark ? .white : .black))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("archivedStories.mode.calendar", comment: "Calendar mode")))

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDisplayMode = (selectedDisplayMode == .map) ? .stories : .map
                        }
                    } label: {
                        Image(systemName: selectedDisplayMode == .map ? "map.circle.fill" : "map")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selectedDisplayMode == .map ? Color(hex: "0A84FF") : (colorScheme == .dark ? .white : .black))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("archivedStories.mode.map", comment: "Map mode")))
                }
            }
        }
        .onAppear {
            viewModel.loadArchivedStories()
        }
        .onChange(of: mapPins.map(\.id)) { _, _ in
            if selectedDisplayMode == .map {
                fitMapToPins()
            }
        }
        .onChange(of: allStories.count) { _, _ in
            if selectedDisplayMode == .map {
                resolveMissingMapCoordinates()
            }
        }
        .onChange(of: selectedDisplayMode) { _, mode in
            if mode == .map {
                fitMapToPins()
                resolveMissingMapCoordinates()
            }
        }
        .fullScreenCover(item: $storyViewerPresentation) { presentation in
            ArchiveDayStoriesViewer(
                stories: presentation.stories,
                initialIndex: presentation.initialIndex
            )
        }
        .sheet(item: $storyStatsPresentation, onDismiss: {
            highlightedActivityStoryId = nil
        }) { presentation in
            StoryStatsView(story: presentation.story)
        }
        .navigationDestination(isPresented: $navigateToArchivedMoments) {
            ActivityInteractionDetailView(category: .archived)
        }
    }

    private func presentStoryActivity(for story: Story) {
        highlightedActivityStoryId = story.id
        storyStatsPresentation = StoryStatsPresentation(story: story)
    }

    private func archiveEmptyView(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.gray.opacity(0.75))
            Text(text)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func reloadArchivedStories() async {
        viewModel.loadArchivedStories()
        while viewModel.isLoading {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private var archiveCalendarView: some View {
        Group {
            if calendarMonthSections.isEmpty {
                ScrollView {
                    archiveEmptyView(
                        icon: "calendar.badge.exclamationmark",
                        text: NSLocalizedString("archivedStories.calendar.empty", comment: "No stories for selected date")
                    )
                    .frame(maxWidth: .infinity, minHeight: 400)
                }
                .momentRefresh {
                    await reloadArchivedStories()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(calendarMonthSections) { monthSection in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(calendarMonthTitle(monthSection.monthStart))
                                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .padding(.horizontal, sectionHorizontalPadding)

                                HStack(spacing: 0) {
                                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                                        Text(symbol)
                                            .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                                            .foregroundStyle(.gray)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(.horizontal, sectionHorizontalPadding)

                                let monthCells = calendarCells(for: monthSection)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                                    ForEach(monthCells) { cell in
                                        if let dayNumber = cell.dayNumber {
                                            Button {
                                                if let bucket = cell.bucket {
                                                    openCalendarStories(bucket.stories)
                                                }
                                            } label: {
                                                ZStack {
                                                    if let bucket = cell.bucket {
                                                        if let url = URL(string: bucket.thumbnailURL) {
                                                            KFImage(url)
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: 40, height: 40)
                                                                .clipShape(Circle())
                                                                .overlay(
                                                                    Circle()
                                                                        .fill(Color.black.opacity(0.28))
                                                                )
                                                        } else {
                                                            Circle()
                                                                .fill(Color.gray.opacity(0.22))
                                                                .frame(width: 40, height: 40)
                                                        }
                                                    }

                                                    Text("\(dayNumber)")
                                                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                                                        .foregroundStyle(cell.bucket == nil ? (colorScheme == .dark ? .white : .black) : .white)
                                                }
                                                .frame(height: 42)
                                                .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            Color.clear
                                                .frame(height: 42)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                .padding(.horizontal, sectionHorizontalPadding)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .momentRefresh {
                    await reloadArchivedStories()
                }
            }
        }
    }

    private var archiveMapView: some View {
        ZStack {
            Map(position: $mapPosition) {
                ForEach(mapPins) { pin in
                    Annotation("", coordinate: pin.coordinate) {
                        Button {
                            openCalendarStories(pin.stories)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                if let story = pin.stories.first, let url = URL(string: mapPreviewURL(for: story)) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white.opacity(0.95), lineWidth: 2)
                                        )
                                } else {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(Color(hex: "0A84FF"))
                                }

                                if pin.stories.count > 1 {
                                    Text("\(pin.stories.count)")
                                        .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(hex: "0A84FF")))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))

            if mapPins.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.gray)
                    Text(NSLocalizedString("archivedStories.map.empty", comment: "No geolocated stories"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var allStories: [Story] {
        viewModel.groupedStories.values.flatMap { $0 }
    }

    private var storiesForGrid: [Story] {
        allStories.sorted { $0.timestamp > $1.timestamp }
    }

    private func openCalendarStories(_ stories: [Story]) {
        guard !stories.isEmpty else { return }
        storyViewerPresentation = StoryViewerPresentation(
            stories: stories,
            initialIndex: 0
        )
    }

    private var calendarDayBuckets: [ArchiveCalendarDayBucket] {
        var grouped: [Date: [Story]] = [:]
        let calendar = Calendar.current
        for story in allStories {
            let day = calendar.startOfDay(for: story.timestamp)
            grouped[day, default: []].append(story)
        }

        return grouped.map { date, stories in
            let sortedStories = stories.sorted { $0.timestamp > $1.timestamp }
            let previewURL = calendarPreviewURL(for: sortedStories[0])
            return ArchiveCalendarDayBucket(date: date, stories: sortedStories, thumbnailURL: previewURL)
        }
        .sorted { $0.date < $1.date }
    }

    private func calendarPreviewURL(for story: Story) -> String {
        if story.mediaItem.type == .video {
            return story.mediaItem.thumbnailUrl ?? story.mediaItem.url
        }
        return story.mediaItem.url
    }

    private func mapPreviewURL(for story: Story) -> String {
        calendarPreviewURL(for: story)
    }

    private var calendarMonthSections: [ArchiveCalendarMonthSection] {
        let calendar = Calendar.current
        var grouped: [Date: [ArchiveCalendarDayBucket]] = [:]

        for day in calendarDayBuckets {
            let components = calendar.dateComponents([.year, .month], from: day.date)
            guard let monthDate = calendar.date(from: components) else { continue }
            grouped[monthDate, default: []].append(day)
        }

        return grouped.map { monthDate, days in
            ArchiveCalendarMonthSection(
                monthStart: monthDate,
                days: days.sorted { $0.date < $1.date }
            )
        }
        .sorted { $0.monthStart < $1.monthStart }
    }

    private func calendarMonthTitle(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .monthYearLabel)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        if symbols.count != 7 {
            symbols = calendar.shortWeekdaySymbols
        }
        let firstWeekdayIndex = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

    private func calendarCells(for monthSection: ArchiveCalendarMonthSection) -> [ArchiveCalendarDayCell] {
        let calendar = Calendar.current
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthSection.monthStart),
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthSection.monthStart))
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var bucketsByDay: [Int: ArchiveCalendarDayBucket] = [:]
        for bucket in monthSection.days {
            let day = calendar.component(.day, from: bucket.date)
            bucketsByDay[day] = bucket
        }

        var cells: [ArchiveCalendarDayCell] = []
        cells.append(contentsOf: (0..<leadingBlanks).map { _ in ArchiveCalendarDayCell(dayNumber: nil, bucket: nil) })

        for day in dayRange {
            cells.append(ArchiveCalendarDayCell(dayNumber: day, bucket: bucketsByDay[day]))
        }

        while cells.count % 7 != 0 {
            cells.append(ArchiveCalendarDayCell(dayNumber: nil, bucket: nil))
        }
        return cells
    }

    private var mapPins: [ArchiveStoryPin] {
        var grouped: [String: (coordinate: CLLocationCoordinate2D, stories: [Story])] = [:]

        for story in allStories {
            guard let coordinate = storyCoordinate(story) else { continue }
            let key = "\(round(coordinate.latitude * 1000) / 1000)|\(round(coordinate.longitude * 1000) / 1000)"
            if grouped[key] == nil {
                grouped[key] = (coordinate, [story])
            } else {
                grouped[key]?.stories.append(story)
            }
        }

        return grouped.map { key, value in
            let sortedStories = value.stories.sorted { $0.timestamp > $1.timestamp }
            return ArchiveStoryPin(id: key, coordinate: value.coordinate, stories: sortedStories)
        }
    }

    private func storyCoordinate(_ story: Story) -> CLLocationCoordinate2D? {
        if let direct = storyCoordinateFromStickers(story) {
            return direct
        }
        if let storyId = story.id, let cached = geocodedCoordinatesByStoryId[storyId] {
            return cached
        }
        return nil
    }

    private func storyCoordinateFromStickers(_ story: Story) -> CLLocationCoordinate2D? {
        guard let stickers = story.stickers else { return nil }
        for sticker in stickers {
            if let latitude = sticker.latitude, let longitude = sticker.longitude {
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        return nil
    }

    private func firstLocationName(for story: Story) -> String? {
        guard let stickers = story.stickers else { return nil }
        return stickers
            .compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func resolveMissingMapCoordinates() {
        guard !isResolvingMapCoordinates else { return }

        let candidates: [(storyId: String, location: String)] = allStories.compactMap { story in
            guard storyCoordinateFromStickers(story) == nil,
                  let storyId = story.id,
                  geocodedCoordinatesByStoryId[storyId] == nil,
                  let locationName = firstLocationName(for: story) else {
                return nil
            }
            return (storyId, locationName)
        }

        guard !candidates.isEmpty else { return }
        isResolvingMapCoordinates = true

        Task {
            var resolved = geocodedCoordinatesByStoryId
            for candidate in candidates.prefix(30) {
                if let coordinate = await geocode(locationName: candidate.location) {
                    resolved[candidate.storyId] = coordinate
                }
            }
            await MainActor.run {
                geocodedCoordinatesByStoryId = resolved
                isResolvingMapCoordinates = false
                if selectedDisplayMode == .map {
                    fitMapToPins()
                }
            }
        }
    }

    private func geocode(locationName: String) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(locationName) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }
    }

    private func fitMapToPins() {
        guard !mapPins.isEmpty else { return }

        if mapPins.count == 1, let first = mapPins.first {
            mapPosition = .region(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
            return
        }

        let lats = mapPins.map { $0.coordinate.latitude }
        let lons = mapPins.map { $0.coordinate.longitude }
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.5, 0.08)
        let lonDelta = max((maxLon - minLon) * 1.5, 0.08)
        mapPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }

}

private struct ArchiveStoryPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let stories: [Story]
}

private struct ArchiveCalendarDayBucket: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let stories: [Story]
    let thumbnailURL: String
    init(date: Date, stories: [Story], thumbnailURL: String) {
        self.date = date
        self.stories = stories
        self.thumbnailURL = thumbnailURL
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayKey = formatter.string(from: date)
    }
}

private struct ArchiveCalendarMonthSection: Identifiable {
    var id: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: monthStart)
    }
    let monthStart: Date
    let days: [ArchiveCalendarDayBucket]
}

private struct ArchiveCalendarDayCell: Identifiable {
    let id = UUID()
    let dayNumber: Int?
    let bucket: ArchiveCalendarDayBucket?
}

// MARK: - Archive Date Section VERTICAL
struct ArchiveDateSectionVertical: View {
    @Environment(\.colorScheme) var colorScheme
    let dateKey: String
    let stories: [Story]
    let onStoryTap: (Story) -> Void
    let onStatsTap: (Story) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date header
            HStack {
                Text(formatDateKey(dateKey))
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Stories in vertical format
            LazyVStack(spacing: 12) {
                ForEach(stories) { story in
                    ArchiveStoryVerticalCard(
                        story: story,
                        onTap: { onStoryTap(story) },
                        onStatsTap: { onStatsTap(story) }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            // Separator
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 12)
        }
    }
    
    private func formatDateKey(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateKey) {
            if Calendar.current.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            } else if Calendar.current.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            } else {
                return MomentsFormat.smartDate(from: date, context: .storyArchive)
            }
        }
        
        return dateKey
    }
}

// MARK: - Archive Date Section GRID
struct ArchiveDateSectionGrid: View {
    @Environment(\.colorScheme) var colorScheme
    let dateKey: String
    let stories: [Story]
    let onStoryTap: (Story) -> Void
    let onStatsTap: (Story) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(formatDateKey(dateKey))
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                spacing: 1
            ) {
                ForEach(stories) { story in
                    ArchiveStorySquareCard(
                        story: story,
                        onTap: { onStoryTap(story) },
                        onStatsTap: { onStatsTap(story) }
                    )
                }
            }
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }
    
    private func formatDateKey(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateKey) {
            if Calendar.current.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            } else if Calendar.current.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            } else {
                return MomentsFormat.smartDate(from: date, context: .storyArchive)
            }
        }
        
        return dateKey
    }
}

// MARK: - Archive Story VERTICAL Card
struct ArchiveStoryVerticalCard: View {
    @Environment(\.colorScheme) var colorScheme
    let story: Story
    let onTap: () -> Void
    let onStatsTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Story thumbnail
                ZStack {
                    if let url = URL(string: story.mediaItem.url) {
                        KFImage(url)
                            .placeholder {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 70, height: 124)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(.gray.opacity(0.5))
                                            .font(.system(size: 20))
                                    )
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 70, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 124)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.gray)
                                    .font(.system(size: 20))
                            )
                    }
                    
                    // Video indicator
                    if story.mediaItem.type == .video {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 18))
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.6))
                                            .frame(width: 28, height: 28)
                                    )
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                    
                    // Duration indicator
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(story.duration))
                                .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                        }
                    }
                    .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "007AFF").opacity(0.6),
                                    Color(hex: "02C39A").opacity(0.4)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                
                // Story info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Profile image
                        if let profileImagePath = story.profileImagePath,
                           let url = URL(string: profileImagePath) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.gray)
                                )
                        }
                        
                        Text(story.username)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatTime(story.timestamp))
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                        
                        Text(formatRelativeDate(story.timestamp))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
                    }
                    
                    // Story type and stats
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "007AFF"))
                            
                            Text(story.mediaItem.type == .video ? NSLocalizedString("archivedStories.video", comment: "Video") : NSLocalizedString("archivedStories.photo", comment: "Photo"))
                                .font(.system(size: legacyPoppinsSize(11)))
                                .foregroundStyle(.gray)
                        }
                        
                        // Stats button
                        Button(action: onStatsTap) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue.opacity(0.8))
                                
                                Text("archivedStories.viewActivity")
                                    .font(.system(size: legacyPoppinsSize(11)))
                                    .foregroundStyle(.blue.opacity(0.8))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
                
                Spacer()
                
                // Archive indicator
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.gray.opacity(0.6))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(colorScheme == .dark ? .black : .white).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatTime(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .timeOnly)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        return "\(seconds)s"
    }
}

private struct ArchiveStoryCardFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ArchiveStoryCardVisual: View {
    let story: Story
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url = previewURL {
                    KFImage(url)
                        .placeholder {
                            Rectangle()
                                .fill(Color.gray.opacity(0.24))
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.26))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.gray)
                        )
                }

                VStack {
                    HStack {
                        HighlightStoryDateBadge(date: story.timestamp)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)

                if story.mediaItem.type == .video, story.duration > 0 {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            Text(HighlightArchiveStoryCardVisual.formatVideoDuration(story.duration))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        }
                    }
                    .padding(7)
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var previewURL: URL? {
        let urlString = story.mediaItem.thumbnailUrl ?? story.mediaItem.url
        return URL(string: urlString)
    }
}

private struct ArchiveStoryLiftedPreview: View {
    let story: Story
    let frame: CGRect

    var body: some View {
        ArchiveStoryCardVisual(story: story, cornerRadius: 0)
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(1.14)
            .shadow(color: Color.black.opacity(0.38), radius: 22, y: 10)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }
}

// MARK: - Archive Story SQUARE Card
struct ArchiveStorySquareCard: View {
    let story: Story
    var isLifted: Bool = false
    let onTap: () -> Void
    let onStatsTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                ArchiveStoryCardVisual(story: story, cornerRadius: 0)
                    .opacity(isLifted ? 0 : 1)

                if isLifted {
                    Rectangle()
                        .fill(Color.gray.opacity(0.24))
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ArchiveStoryCardFrameKey.self,
                        value: story.id.map { [$0: proxy.frame(in: .named("archiveStoryGrid"))] } ?? [:]
                    )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                onStatsTap()
            } label: {
                Label("archivedStories.viewActivity", systemImage: "chart.bar.fill")
            }
        }
    }
}

// MARK: - Archive Day Stories Viewer
struct ArchiveDayStoriesViewer: View {
    let stories: [Story]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var storyViewModel = StoryViewModel()
    @State private var currentIndex: Int
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false

    init(stories: [Story], initialIndex: Int = 0) {
        self.stories = stories
        let maxIndex = max(stories.count - 1, 0)
        let clamped = min(max(initialIndex, 0), maxIndex)
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            if let story = currentStory {
                StoryViewerScreen(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: currentIndex,
                    screenSize: UIApplication.shared.activeWindowSize,
                    storyViewModel: storyViewModel,
                    showingReportSheet: $showingReportSheet,
                    showingBlockConfirmation: $showingBlockConfirmation,
                    onReportStory: {
                        showingReportSheet = false
                    },
                    onBlockUser: {
                        showingBlockConfirmation = false
                    },
                    onNext: {
                        if currentIndex < stories.count - 1 {
                            currentIndex += 1
                        } else {
                            dismiss()
                        }
                    },
                    onPrevious: {
                        if currentIndex > 0 {
                            currentIndex -= 1
                        } else {
                            dismiss()
                        }
                    },
                    onClose: {
                        dismiss()
                    },
                    onProfileTap: {}
                )
            } else {
                GlassmorphicEmptyState(
                    icon: "exclamationmark.triangle",
                    message: NSLocalizedString("stories.errorLoadingStory", comment: "Error loading story"),
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .all)
        .ignoresSafeArea(.container, edges: .all)
        .statusBar(hidden: false)
        .onAppear {
            GlobalVideoManager.shared.pauseAllVideos()
            hydrateStoryViewerContext()
        }
    }

    private var currentStory: Story? {
        guard stories.indices.contains(currentIndex) else { return nil }
        return stories[currentIndex]
    }

    private func hydrateStoryViewerContext() {
        guard let authorId = stories.first?.authorId else { return }
        // StoryViewerScreen usa storyViewModel.stories[authorId] para colorear
        // la barra por audiencia en cada segmento.
        storyViewModel.stories[authorId] = stories
    }
}

// MARK: - Story Stats View
struct StoryStatsView: View {
    let story: Story
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = StoryStatsViewModel()
    @State private var selectedTab = 0
    @State private var viewerSearchText = ""
    @State private var reactionSearchText = ""
    @State private var reactionUsersById: [String: AppUser] = [:]

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54)
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(primaryText)

                    Text(NSLocalizedString("archivedStories.loadingStats", comment: "Loading statistics"))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(secondaryText)
                }
            } else {
                VStack(spacing: 0) {
                    statsHeader
                        .padding(.horizontal, 22)
                        .padding(.top, 12)

                    storyMetaSection
                        .padding(.horizontal, 22)
                        .padding(.top, 16)

                    statsMetricsRow
                        .padding(.horizontal, 22)
                        .padding(.top, 18)

                    GlassmorphicTabSelector(
                        tabs: [
                            String(format: NSLocalizedString("stories.activity.viewersTab", comment: ""), viewModel.viewers.count),
                            String(format: NSLocalizedString("stories.activity.reactionsTab", comment: ""), viewModel.reactions.count)
                        ],
                        selectedIndex: $selectedTab
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                    TabView(selection: $selectedTab) {
                        viewersTab.tag(0)
                        reactionsTab.tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .onAppear {
            viewModel.loadStats(for: story)
            loadReactionUsersIfNeeded()
        }
        .onChange(of: viewModel.reactions.map(\.userId)) { _, _ in
            loadReactionUsersIfNeeded()
        }
    }

    private var statsHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text(NSLocalizedString("archivedStories.stats.title", comment: "Statistics title"))
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundStyle(primaryText)
                .padding(.top, 2)
        }
    }

    private var storyMetaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: NSLocalizedString("archivedStories.storyFrom", comment: "Story from date"), formatStoryDate(story.timestamp)))
                .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                .foregroundStyle(primaryText)

            Text(String(format: NSLocalizedString("archivedStories.publishedAt", comment: "Published at time"), formatStoryTime(story.timestamp)))
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundStyle(secondaryText)

            Text(story.mediaItem.type == .video
                 ? NSLocalizedString("archivedStories.video", comment: "Video")
                 : NSLocalizedString("archivedStories.photo", comment: "Photo"))
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsMetricsRow: some View {
        HStack(spacing: 0) {
            ArchivedStoryStatMetric(
                value: "\(viewModel.viewCount)",
                title: NSLocalizedString("archivedStories.stats.views", comment: "Views")
            )

            metricDivider

            ArchivedStoryStatMetric(
                value: "\(viewModel.reactionCount)",
                title: NSLocalizedString("archivedStories.stats.reactions", comment: "Reactions")
            )

            metricDivider

            ArchivedStoryStatMetric(
                value: "\(viewModel.shareCount)",
                title: NSLocalizedString("archivedStories.stats.shares", comment: "Shares")
            )

            metricDivider

            ArchivedStoryStatMetric(
                value: "\(viewModel.reachCount)",
                title: NSLocalizedString("archivedStories.stats.reach", comment: "Reach")
            )
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .frame(width: 1, height: 28)
    }

    private var viewersTab: some View {
        ZStack {
            if viewModel.viewers.isEmpty {
                GlassmorphicEmptyState(
                    icon: "eye.slash",
                    message: NSLocalizedString("archivedStories.stats.empty.viewers", comment: "No story viewers yet")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        archivedSearchBar(text: $viewerSearchText)

                        if filteredViewers.isEmpty {
                            GlassmorphicEmptyState(
                                icon: "magnifyingglass",
                                message: NSLocalizedString(
                                    "stories.activity.search.empty",
                                    value: "No hay viewers que coincidan con tu busqueda.",
                                    comment: "No matching viewers for search"
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredViewers, id: \.id) { viewer in
                                    ArchivedStoryViewerRow(viewer: viewer)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var reactionsTab: some View {
        ZStack {
            if viewModel.reactions.isEmpty {
                GlassmorphicEmptyState(
                    icon: "heart.slash",
                    message: NSLocalizedString("archivedStories.stats.empty.reactions", comment: "No story reactions yet")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        archivedSearchBar(text: $reactionSearchText)

                        if filteredReactions.isEmpty {
                            GlassmorphicEmptyState(
                                icon: "magnifyingglass",
                                message: NSLocalizedString(
                                    "stories.activity.search.empty",
                                    value: "No hay viewers que coincidan con tu busqueda.",
                                    comment: "No matching viewers for search"
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredReactions, id: \.id) { reaction in
                                    ArchivedStoryReactionRow(
                                        reaction: reaction,
                                        user: reactionUsersById[reaction.userId]
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private func archivedSearchBar(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                .font(.system(size: 15, weight: .medium))

            TextField(NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"), text: text)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(primaryText)
                .textFieldStyle(.plain)

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.001))
        .momentsChromeGlass(in: Capsule())
    }

    private var filteredViewers: [StoryViewer] {
        let query = viewerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.viewers }
        return viewModel.viewers.filter { viewer in
            (viewer.username ?? NSLocalizedString("archivedStories.user", comment: "User"))
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredReactions: [StoryReaction] {
        let query = reactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.reactions }
        return viewModel.reactions.filter { reaction in
            let username = reactionUsersById[reaction.userId]?.username
                ?? NSLocalizedString("archivedStories.user", comment: "User")
            return username.localizedCaseInsensitiveContains(query)
        }
    }

    private func loadReactionUsersIfNeeded() {
        let missingIds = Array(Set(viewModel.reactions.map(\.userId))).filter { reactionUsersById[$0] == nil }
        guard !missingIds.isEmpty else { return }

        FirestoreService.shared.fetchUsers(userIds: missingIds) { result in
            guard case .success(let users) = result else { return }
            DispatchQueue.main.async {
                for user in users {
                    reactionUsersById[user.id] = user
                }
            }
        }
    }

    private func formatStoryDate(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .mediumDate)
    }

    private func formatStoryTime(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .timeOnly)
    }
}

private struct ArchivedStoryStatMetric: View {
    let value: String
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: legacyPoppinsSize(17), weight: .bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.system(size: legacyPoppinsSize(10)))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ArchivedStoryViewerRow: View {
    let viewer: StoryViewer
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            StoryRingAvatarView(
                userId: viewer.userId,
                size: 48,
                lineWidth: 2.3
            )

            HStack(spacing: 6) {
                Text(viewer.username ?? NSLocalizedString("archivedStories.user", comment: "User"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(primaryText)

                if let badgeText = viewer.rewatchBadgeText {
                    Text(badgeText)
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(primaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
    }
}

private struct ArchivedStoryReactionRow: View {
    let reaction: StoryReaction
    let user: AppUser?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            if let user {
                StoryRingAvatarView(
                    userId: user.id,
                    size: 48,
                    lineWidth: 2.3
                )
            } else {
                StoryRingAvatarView(
                    userId: reaction.userId,
                    size: 48,
                    lineWidth: 2.3
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(user?.username ?? NSLocalizedString("archivedStories.user", comment: "User"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(primaryText)

                Text(timeAgo(from: reaction.timestamp))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 0)

            Text(reaction.reaction)
                .font(.system(size: 28))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
    }

    private func timeAgo(from date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
    }
}

// MARK: - Archive ViewModel
class ArchiveViewModel: ObservableObject {
    @Published var groupedStories: [String: [Story]] = [:]
    @Published var isLoading = false
    
    private let firestoreService = FirestoreService()
    
    func loadArchivedStories() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        firestoreService.db.collection("users").document(userId).collection("stories")
            .whereField("expirationDate", isLessThan: Date())
            .order(by: "timestamp", descending: true)
            .limit(to: 100)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if error != nil {
                        return
                    }
                    
                    let stories = snapshot?.documents.compactMap { doc -> Story? in
                        var data = doc.data()
                        data["id"] = doc.documentID
                        return try? Firestore.Decoder().decode(Story.self, from: data)
                    } ?? []
                    
                    self?.groupStoriesByDate(stories)
                    self?.prefetchRecentImages(stories: stories)
                }
            }
    }
    
    private func groupStoriesByDate(_ stories: [Story]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let grouped = Dictionary(grouping: stories) { story in
            formatter.string(from: story.timestamp)
        }
        
        self.groupedStories = grouped
    }
    
    private func prefetchRecentImages(stories: [Story]) {
        let imageStories = stories.filter { $0.mediaItem.type == .image }
        let recentImageUrls = Array(imageStories.prefix(10)).compactMap { URL(string: $0.mediaItem.url) }
        
        if !recentImageUrls.isEmpty {
            ImagePrefetchManager.shared.prefetch(urls: recentImageUrls)
        }
    }
}

// MARK: - Story Stats ViewModel
class StoryStatsViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var viewCount = 0
    @Published var reactionCount = 0
    @Published var shareCount = 0
    @Published var reachCount = 0
    @Published var viewers: [StoryViewer] = []
    @Published var reactions: [StoryReaction] = []
    
    private let firestoreService = FirestoreService()
    
    func loadStats(for story: Story) {
        guard let storyId = story.id else { return }
        
        isLoading = true
        
        let group = DispatchGroup()
        
        // Load viewers
        group.enter()
        firestoreService.db.collection("users").document(story.authorId).collection("stories").document(storyId)
            .collection("viewers")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                defer { group.leave() }
                
                if error != nil {
                    return
                }
                
                let viewers = snapshot?.documents.compactMap { doc in
                    StoryViewer.from(documentId: doc.documentID, data: doc.data())
                } ?? []
                
                DispatchQueue.main.async {
                    self?.viewers = viewers
                    self?.viewCount = viewers.count
                    self?.reachCount = Set(viewers.map { $0.userId }).count
                }
            }
        
        // Load reactions
        group.enter()
        firestoreService.db.collection("users").document(story.authorId).collection("stories").document(storyId)
            .collection("reactions")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                defer { group.leave() }
                
                if error != nil {
                    return
                }
                
                let reactions = snapshot?.documents.compactMap { doc -> StoryReaction? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let reaction = data["reaction"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    return StoryReaction(id: doc.documentID, userId: userId, reaction: reaction, timestamp: timestamp)
                } ?? []
                
                let uniqueReactions = reactions.latestPerUser()
                DispatchQueue.main.async {
                    self?.reactions = uniqueReactions
                    self?.reactionCount = uniqueReactions.count
                }
            }
        
        group.notify(queue: .main) {
            self.isLoading = false
            self.shareCount = Int.random(in: 0...max(1, self.viewCount / 10))
        }
    }
}

// MARK: - Preview
struct ArchiveView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ArchiveView()
        }
        .preferredColorScheme(.light)
        
        NavigationStack {
            ArchiveView()
        }
        .preferredColorScheme(.dark)
    }
}
