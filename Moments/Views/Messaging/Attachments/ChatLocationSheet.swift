import SwiftUI
import MapKit
import CoreLocation

// MARK: - Modelo de lugar (cercano / búsqueda)

struct ChatLocationPlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: ChatLocationPlace, rhs: ChatLocationPlace) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sheet content

struct ChatLocationSheetContent: View {
    let accentColor: Color
    let onSendStatic: (CLLocationCoordinate2D, String?, String?) -> Void
    let onStartLive: (LiveLocationDuration) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationUtilities.shared
    @StateObject private var locationGate = LocationPermissionGate()

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    ))
    @State private var currentCoordinate = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
    @State private var accuracy: CLLocationAccuracy = -1
    @State private var currentPlaceName: String?
    @State private var currentPlaceAddress: String?

    @State private var searchText = ""
    @State private var nearbyPlaces: [ChatLocationPlace] = []
    @State private var searchResults: [ChatLocationPlace] = []
    @State private var isSearching = false
    @State private var hasCenteredOnUser = false
    @State private var searchTask: Task<Void, Never>?

    @State private var showLiveDurationDialog = false

    private var isShowingSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var listedPlaces: [ChatLocationPlace] {
        isShowingSearch ? searchResults : nearbyPlaces
    }

    var body: some View {
        ChatAttachmentScrollUnderSearchLayout {
            searchField
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(query: newValue)
                }
        } content: {
            VStack(spacing: 0) {
                if !isShowingSearch {
                    mapPreview
                    sendCurrentRow
                    shareLiveRow
                    sectionHeader("chat.location.nearby")
                } else {
                    sectionHeader("chat.location.searchResults")
                }

                if isSearching {
                    ProgressView()
                        .tint(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if listedPlaces.isEmpty {
                    Text(LocalizedStringKey(isShowingSearch ? "chat.location.noResults" : "chat.location.noNearby"))
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(listedPlaces) { place in
                        placeRow(place)
                        if place.id != listedPlaces.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            Text(LocalizedStringKey("chat.location.shareLive")),
            isPresented: $showLiveDurationDialog,
            titleVisibility: .visible
        ) {
            ForEach(LiveLocationDuration.allCases) { duration in
                Button(NSLocalizedString(duration.localizedTitleKey, comment: "")) {
                    locationGate.requestAccess(level: .always) {
                        onStartLive(duration)
                    }
                }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("chat.location.livePermissionInfo"))
        }
        .onAppear {
            if locationManager.authorizationStatus == .authorizedWhenInUse
                || locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocationPermission()
            }
            centerOnUserIfPossible()
        }
        .locationPermissionGate(locationGate)
        .onChange(of: locationManager.currentLocation) { _, _ in
            centerOnUserIfPossible()
        }
    }

    // MARK: - Search

    private var searchField: some View {
        ChatAttachmentSearchField(
            placeholderKey: "chat.location.searchPlaces",
            text: $searchText,
            onClear: {
                searchResults = []
            }
        )
    }

    // MARK: - Map preview

    private var mapPreview: some View {
        ZStack {
            Map(position: $position, interactionModes: [])
            // Pin del usuario (centro)
            Image(systemName: "location.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white, accentColor)
                .shadow(radius: 2)
                .allowsHitTesting(false)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Filas principales

    private var sendCurrentRow: some View {
        Button {
            onSendStatic(currentCoordinate, currentPlaceName, currentPlaceAddress)
        } label: {
            HStack(spacing: 14) {
                rowIcon(icon: .location, tint: accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("chat.location.sendCurrent"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(primaryText)
                    Text(accuracyText)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shareLiveRow: some View {
        Button {
            showLiveDurationDialog = true
        } label: {
            HStack(spacing: 14) {
                rowIcon(icon: .liveLocation, tint: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("chat.location.shareLive"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(primaryText)
                    Text(LocalizedStringKey("chat.location.liveSubtitle"))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeRow(_ place: ChatLocationPlace) -> some View {
        Button {
            onSendStatic(place.coordinate, place.name, place.address)
        } label: {
            HStack(spacing: 14) {
                rowIcon(icon: .location, tint: .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                    if let address = place.address {
                        Text(address)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ key: String) -> some View {
        HStack {
            Text(LocalizedStringKey(key))
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundStyle(secondaryText)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func rowIcon(icon: AttachmentIcon, tint: Color) -> some View {
        AttachmentIconView(icon: icon, preset: .locationSheetRow, tintColor: tint)
            .frame(width: 30, alignment: .center)
    }

    private func rowIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, alignment: .center)
    }

    // MARK: - Colores

    private var primaryText: Color { colorScheme == .dark ? .white : .black }
    private var secondaryText: Color { colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5) }

    private var accuracyText: String {
        if accuracy > 0 {
            return String(format: NSLocalizedString("chat.location.accuracy", comment: ""), Int(accuracy.rounded()))
        }
        return currentPlaceAddress ?? NSLocalizedString("chat.location.sendCurrentSubtitle", comment: "")
    }

    // MARK: - Ubicación / cercanos

    private func centerOnUserIfPossible() {
        guard !hasCenteredOnUser, let location = locationManager.currentLocation else { return }
        hasCenteredOnUser = true
        let coord = location.coordinate
        currentCoordinate = coord
        accuracy = location.horizontalAccuracy
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
        reverseGeocodeCurrent(coordinate: coord)
        loadNearbyPlaces(around: coord)
    }

    private func reverseGeocodeCurrent(coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            DispatchQueue.main.async {
                guard let placemark = placemarks?.first else { return }
                currentPlaceName = placemark.name ?? placemark.locality
                var parts: [String] = []
                if let thoroughfare = placemark.thoroughfare { parts.append(thoroughfare) }
                if let locality = placemark.locality { parts.append(locality) }
                currentPlaceAddress = parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
        }
    }

    private func loadNearbyPlaces(around coordinate: CLLocationCoordinate2D) {
        let request = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: 1000
        )
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let items = response?.mapItems else { return }
            DispatchQueue.main.async {
                nearbyPlaces = items.prefix(20).map { item in
                    ChatLocationPlace(
                        name: item.name ?? NSLocalizedString("common.location", comment: ""),
                        address: Self.shortAddress(from: item.placemark),
                        coordinate: item.placemark.coordinate
                    )
                }
            }
        }
    }

    private func scheduleSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !trimmed.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await runSearch(query: trimmed)
        }
    }

    @MainActor
    private func runSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: currentCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            if Task.isCancelled { return }
            searchResults = response.mapItems.prefix(25).map { item in
                ChatLocationPlace(
                    name: item.name ?? NSLocalizedString("common.location", comment: ""),
                    address: Self.shortAddress(from: item.placemark),
                    coordinate: item.placemark.coordinate
                )
            }
            isSearching = false
        } catch {
            if Task.isCancelled { return }
            searchResults = []
            isSearching = false
        }
    }

    private static func shortAddress(from placemark: MKPlacemark) -> String? {
        var parts: [String] = []
        if let thoroughfare = placemark.thoroughfare { parts.append(thoroughfare) }
        if let locality = placemark.locality { parts.append(locality) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
