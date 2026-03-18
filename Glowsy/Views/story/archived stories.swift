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
    @State private var selectedDisplayMode: ArchiveDisplayMode = .stories
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20.0, longitude: 0.0),
        span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100)
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

    init(embedInNavigation: Bool = true, showsCustomDismiss: Bool = true) {
        self.embedInNavigation = embedInNavigation
        self.showsCustomDismiss = showsCustomDismiss
    }
    
    var body: some View {
        Group {
            if embedInNavigation {
                NavigationView {
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
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)

                    Text("archivedStories.loading")
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray)
                }
            } else if viewModel.groupedStories.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))

                    VStack(spacing: 8) {
                        Text("archivedStories.empty.title")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("archivedStories.empty.description")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    switch selectedDisplayMode {
                    case .stories:
                        if storiesForGrid.isEmpty {
                            archiveEmptyView(
                                icon: "tray",
                                text: NSLocalizedString("archivedStories.empty.description", comment: "No archived stories")
                            )
                        } else {
                            ScrollView {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                                    ForEach(storiesForGrid) { story in
                                        ArchiveStorySquareCard(
                                            story: story,
                                            onTap: {
                                                storyViewerPresentation = StoryViewerPresentation(
                                                    stories: [story],
                                                    initialIndex: 0
                                                )
                                            },
                                            onStatsTap: {
                                                storyStatsPresentation = StoryStatsPresentation(story: story)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, sectionHorizontalPadding)
                                .padding(.top, 8)
                                .padding(.bottom, 20)
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
        .toolbar {
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
                            .font(.custom("Poppins-SemiBold", size: 17))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }

            if showsCustomDismiss {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
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
                            .foregroundColor(selectedDisplayMode == .calendar ? Color(hex: "0A84FF") : (colorScheme == .dark ? .white : .black))
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
                            .foregroundColor(selectedDisplayMode == .map ? Color(hex: "0A84FF") : (colorScheme == .dark ? .white : .black))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(NSLocalizedString("archivedStories.mode.map", comment: "Map mode")))
                }
            }
        }
        .onAppear {
            viewModel.loadArchivedStories()
        }
        .onChange(of: mapPins.map(\.id)) { _ in
            if selectedDisplayMode == .map {
                fitMapToPins()
            }
        }
        .onChange(of: allStories.count) { _ in
            if selectedDisplayMode == .map {
                resolveMissingMapCoordinates()
            }
        }
        .onChange(of: selectedDisplayMode) { mode in
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
        .sheet(item: $storyStatsPresentation) { presentation in
            StoryStatsView(story: presentation.story)
        }
        .background(
            NavigationLink(
                destination: ArchivedMomentsView(),
                isActive: $navigateToArchivedMoments
            ) {
                EmptyView()
            }
            .hidden()
        )
    }

    private func archiveEmptyView(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.gray.opacity(0.75))
            Text(text)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var archiveCalendarView: some View {
        Group {
            if calendarMonthSections.isEmpty {
                archiveEmptyView(
                    icon: "calendar.badge.exclamationmark",
                    text: NSLocalizedString("archivedStories.calendar.empty", comment: "No stories for selected date")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(calendarMonthSections) { monthSection in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(calendarMonthTitle(monthSection.monthStart))
                                    .font(.custom("Poppins-SemiBold", size: 17))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.horizontal, sectionHorizontalPadding)

                                HStack(spacing: 0) {
                                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                                        Text(symbol)
                                            .font(.custom("Poppins-Medium", size: 11))
                                            .foregroundColor(.gray)
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
                                                        .font(.custom("Poppins-SemiBold", size: 12))
                                                        .foregroundColor(cell.bucket == nil ? (colorScheme == .dark ? .white : .black) : .white)
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
            }
        }
    }

    private var archiveMapView: some View {
        ZStack {
            Map(coordinateRegion: $mapRegion, annotationItems: mapPins) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
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
                                    .foregroundColor(Color(hex: "0A84FF"))
                            }

                            if pin.stories.count > 1 {
                                Text("\(pin.stories.count)")
                                    .font(.custom("Poppins-Bold", size: 10))
                                    .foregroundColor(.white)
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
            .mapStyle(.standard(elevation: .realistic))

            if mapPins.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("archivedStories.map.empty", comment: "No geolocated stories"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(.gray)
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
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
            mapRegion = MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
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
        mapRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
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
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
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
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "es")
            
            if Calendar.current.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            } else if Calendar.current.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
                displayFormatter.dateFormat = "d 'de' MMMM"
                return displayFormatter.string(from: date)
            } else {
                displayFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"
                return displayFormatter.string(from: date)
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
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("archivedStories.count", comment: "Story count"), stories.count))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(stories) { story in
                    ArchiveStorySquareCard(
                        story: story,
                        onTap: { onStoryTap(story) },
                        onStatsTap: { onStatsTap(story) }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }
    
    private func formatDateKey(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateKey) {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = Locale(identifier: "es")
            
            if Calendar.current.isDateInToday(date) {
                return NSLocalizedString("archivedStories.today", comment: "Today")
            } else if Calendar.current.isDateInYesterday(date) {
                return NSLocalizedString("archivedStories.yesterday", comment: "Yesterday")
            } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
                displayFormatter.dateFormat = "d 'de' MMMM"
                return displayFormatter.string(from: date)
            } else {
                displayFormatter.dateFormat = "d 'de' MMMM 'de' yyyy"
                return displayFormatter.string(from: date)
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
                                            .foregroundColor(.gray.opacity(0.5))
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
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))
                            )
                    }
                    
                    // Video indicator
                    if story.mediaItem.type == .video {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.white)
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
                                .font(.custom("Poppins-Bold", size: 10))
                                .foregroundColor(.white)
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
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        Text(story.username)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatTime(story.timestamp))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.8))
                        
                        Text(formatRelativeDate(story.timestamp))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    // Story type and stats
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "007AFF"))
                            
                            Text(story.mediaItem.type == .video ? NSLocalizedString("archivedStories.video", comment: "Video") : NSLocalizedString("archivedStories.photo", comment: "Photo"))
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        // Stats button
                        Button(action: onStatsTap) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue.opacity(0.8))
                                
                                Text("archivedStories.viewActivity")
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(.blue.opacity(0.8))
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
                    .foregroundColor(.gray.opacity(0.6))
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        return "\(seconds)s"
    }
}

// MARK: - Archive Story SQUARE Card
struct ArchiveStorySquareCard: View {
    let story: Story
    let onTap: () -> Void
    let onStatsTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack {
                    if let url = URL(string: story.mediaItem.url) {
                        KFImage(url)
                            .placeholder {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.24))
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.26))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    if story.mediaItem.type == .video {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 15))
                                    .shadow(radius: 2)
                            }
                            Spacer()
                        }
                        .padding(7)
                    }

                    VStack {
                        HStack {
                            Text(formatShortDate(story.timestamp))
                                .font(.custom("Poppins-SemiBold", size: 9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.14), lineWidth: 0.5)
            )
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
    
    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
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
                GlassmorphicStoryViewer(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: currentIndex,
                    screenSize: UIScreen.main.bounds.size,
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
            hydrateStoryViewerContext()
        }
    }

    private var currentStory: Story? {
        guard stories.indices.contains(currentIndex) else { return nil }
        return stories[currentIndex]
    }

    private func hydrateStoryViewerContext() {
        guard let authorId = stories.first?.authorId else { return }
        // GlassmorphicStoryViewer usa storyViewModel.stories[authorId] para colorear
        // la barra por audiencia en cada segmento.
        storyViewModel.stories[authorId] = stories
    }
}

// MARK: - Story Stats View
struct StoryStatsView: View {
    let story: Story
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = StoryStatsViewModel()
    @State private var selectedSection: StatsSection = .viewers
    
    enum StatsSection: String, CaseIterable, Identifiable {
        case viewers
        case reactions
        
        var id: String { rawValue }
        
        var titleKey: String {
            switch self {
            case .viewers: return "archivedStories.whoViewed"
            case .reactions: return "archivedStories.reactions"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.2)
                        
                        Text(NSLocalizedString("archivedStories.loadingStats", comment: "Loading statistics"))
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                if let url = URL(string: story.mediaItem.url) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 196)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(format: NSLocalizedString("archivedStories.storyFrom", comment: "Story from date"), formatStoryDate(story.timestamp)))
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text(String(format: NSLocalizedString("archivedStories.publishedAt", comment: "Published at time"), formatStoryTime(story.timestamp)))
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                    
                                    pill(text: story.mediaItem.type == .video
                                         ? NSLocalizedString("archivedStories.video", comment: "Video")
                                         : NSLocalizedString("archivedStories.photo", comment: "Photo"))
                                }
                                Spacer(minLength: 0)
                            }
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                StatsCard(
                                    icon: "eye.fill",
                                    title: NSLocalizedString("archivedStories.stats.views", comment: "Views"),
                                    value: "\(viewModel.viewCount)",
                                    color: .blue
                                )
                                
                                StatsCard(
                                    icon: "heart.fill",
                                    title: NSLocalizedString("archivedStories.stats.reactions", comment: "Reactions"),
                                    value: "\(viewModel.reactionCount)",
                                    color: .red
                                )
                                
                                StatsCard(
                                    icon: "paperplane.fill",
                                    title: NSLocalizedString("archivedStories.stats.shares", comment: "Shares"),
                                    value: "\(viewModel.shareCount)",
                                    color: Color(hex: "007AFF")
                                )
                                
                                StatsCard(
                                    icon: "person.2.fill",
                                    title: NSLocalizedString("archivedStories.stats.reach", comment: "Reach"),
                                    value: "\(viewModel.reachCount)",
                                    color: .purple
                                )
                            }
                            
                            HStack(spacing: 8) {
                                ForEach(StatsSection.allCases) { section in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            selectedSection = section
                                        }
                                    } label: {
                                        Text(NSLocalizedString(section.titleKey, comment: "Story stats section"))
                                            .font(.custom("Poppins-SemiBold", size: 12))
                                            .foregroundColor(selectedSection == section ? .white : (colorScheme == .dark ? .white : .black))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(
                                                        selectedSection == section
                                                        ? Color(hex: "007AFF")
                                                        : Color(colorScheme == .dark ? .white : .black).opacity(0.08)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            if selectedSection == .viewers {
                                VStack(alignment: .leading, spacing: 10) {
                                    sectionHeader(
                                        title: NSLocalizedString("archivedStories.whoViewed", comment: "Who viewed it"),
                                        countText: String(format: NSLocalizedString("archivedStories.peopleCount", comment: "People count"), viewModel.viewers.count)
                                    )
                                    
                                    if viewModel.viewers.isEmpty {
                                        emptySection(
                                            icon: "eye.slash",
                                            text: NSLocalizedString("archivedStories.stats.empty.viewers", comment: "No story viewers yet")
                                        )
                                    } else {
                                        LazyVStack(spacing: 8) {
                                            ForEach(viewModel.viewers, id: \.id) { viewer in
                                                ViewerRow(viewer: viewer)
                                            }
                                        }
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    sectionHeader(
                                        title: NSLocalizedString("archivedStories.reactions", comment: "Reactions"),
                                        countText: "\(viewModel.reactions.count)"
                                    )
                                    
                                    if viewModel.reactions.isEmpty {
                                        emptySection(
                                            icon: "heart.slash",
                                            text: NSLocalizedString("archivedStories.stats.empty.reactions", comment: "No story reactions yet")
                                        )
                                    } else {
                                        LazyVStack(spacing: 8) {
                                            ForEach(viewModel.reactions, id: \.id) { reaction in
                                                ReactionRow(reaction: reaction)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("archivedStories.stats.title", comment: "Statistics title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("archivedStories.close", comment: "Close")) {
                        dismiss()
                    }
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(Color(hex: "00A896"))
                }
            }
        }
        .onAppear {
            viewModel.loadStats(for: story)
        }
    }
    
    private func pill(text: String) -> some View {
        Text(text)
            .font(.custom("Poppins-SemiBold", size: 10))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08))
            )
    }
    
    private func sectionHeader(title: String, countText: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Spacer()
            Text(countText)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
        }
    }
    
    private func emptySection(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.gray.opacity(0.75))
            Text(text)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
    }
    
    private func formatStoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatStoryTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Stats Card
struct StatsCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(title)
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
    }
}

// MARK: - Stats Card
struct ViewerRow: View {
    let viewer: StoryViewer
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            StoryRingAvatarView(
                userId: viewer.userId,
                size: 44,
                lineWidth: 2.3
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewer.username ?? NSLocalizedString("archivedStories.user", comment: "User"))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(timeAgo(from: viewer.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.04))
        )
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ReactionRow: View {
    let reaction: StoryReaction
    @Environment(\.colorScheme) var colorScheme
    @State private var username: String = NSLocalizedString("archivedStories.user", comment: "User")
    
    var body: some View {
        HStack(spacing: 12) {
            StoryRingAvatarView(
                userId: reaction.userId,
                size: 44,
                lineWidth: 2.3
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(timeAgo(from: reaction.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(reaction.reaction)
                .font(.system(size: 28))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.04))
        )
        .onAppear {
            fetchUsername()
        }
    }
    
    private func fetchUsername() {
        FirestoreService().fetchUserProfile(userId: reaction.userId) { result in
            switch result {
            case .success(let user):
                self.username = user.username
            case .failure(_):
                self.username = NSLocalizedString("archivedStories.user", comment: "User")
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
                    
                    if let error = error {
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
                
                if let error = error {
                    return
                }
                
                let viewers = snapshot?.documents.compactMap { doc -> StoryViewer? in
                    let data = doc.data()
                    guard let userId = data["userId"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }
                    let username = data["username"] as? String
                    let profileImagePath = data["profileImagePath"] as? String
                    return StoryViewer(
                        id: doc.documentID,
                        userId: userId,
                        username: username,
                        profileImagePath: profileImagePath,
                        timestamp: timestamp
                    )
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
                
                if let error = error {
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
                
                DispatchQueue.main.async {
                    self?.reactions = reactions
                    self?.reactionCount = reactions.count
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
        NavigationView {
            ArchiveView()
        }
        .preferredColorScheme(.light)
        
        NavigationView {
            ArchiveView()
        }
        .preferredColorScheme(.dark)
    }
}
