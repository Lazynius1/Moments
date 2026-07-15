import CoreLocation
import MapKit
import SwiftUI

struct SmartLocationInputView: View {
    let onSelect: (String, CLLocationCoordinate2D?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var nearbyPlaces: [LocationResult] = []
    @State private var searchResults: [LocationResult] = []
    @State private var isLoadingNearby = true
    @State private var isSearching = false
    @State private var userLocation: CLLocation?
    @FocusState private var isTextFieldFocused: Bool

    @StateObject private var locationManager = LocationManager()

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    // Modelo para resultados de ubicación
    struct LocationResult: Identifiable, Hashable, Equatable {
        let id = UUID()
        let displayName: String // ✅ NOMBRE PARA MOSTRAR EN LA UI
        let fullName: String // ✅ NOMBRE COMPLETO PARA PRECISIÓN
        let address: String
        let distance: Double? // En metros
        let category: String
        let coordinate: CLLocationCoordinate2D

        var distanceString: String {
            guard let distance = distance else { return "" }
            if distance < 1000 {
                return "\(Int(distance))m"
            } else {
                return String(format: "%.1fkm", distance / 1000)
            }
        }

        var categoryIcon: String {
            switch category.lowercased() {
            case "restaurant", "food": return "fork.knife"
            case "shopping", "store": return "bag"
            case "entertainment": return "theatermasks"
            case "gas station": return "fuelpump"
            case "hospital": return "cross.case"
            case "school": return "graduationcap"
            case "park": return "tree"
            case "gym": return "dumbbell"
            case "hotel": return "bed.double"
            default: return "mappin"
            }
        }

        // MARK: - Conformance to Equatable
        static func == (lhs: LocationResult, rhs: LocationResult) -> Bool {
            return lhs.id == rhs.id &&
                   lhs.displayName == rhs.displayName &&
                   lhs.fullName == rhs.fullName &&
                   lhs.address == rhs.address &&
                   lhs.distance == rhs.distance &&
                   lhs.category == rhs.category &&
                   lhs.coordinate.latitude == rhs.coordinate.latitude &&
                   lhs.coordinate.longitude == rhs.coordinate.longitude
        }

        // MARK: - Conformance to Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(displayName)
            hasher.combine(fullName)
            hasher.combine(address)
            hasher.combine(distance)
            hasher.combine(category)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("stickerview.location.searchTitle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.primaryText)

                        Text("stickerview.location.searchSubtitle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer()

                    if locationManager.authorizationStatus == .authorizedWhenInUse ||
                        locationManager.authorizationStatus == .authorizedAlways {
                        Button(action: {
                            refreshLocationAndPlaces()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("stickerview.location.refresh")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(palette.buttonFill)
                                    .overlay(Capsule().stroke(palette.fieldStroke, lineWidth: 1))
                            )
                        }
                        .disabled(isLoadingNearby)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: isSearching ? "magnifyingglass" : (searchText.isEmpty ? "magnifyingglass" : "location.magnifyingglass"))
                        .font(.system(size: 16))
                        .foregroundStyle(searchText.isEmpty ? palette.searchIcon : palette.searchIconActive)
                        .animation(.easeInOut(duration: 0.2), value: searchText)

                    TextField(NSLocalizedString("stickerview.location.searchPlaceholder", comment: "Location search placeholder"), text: $searchText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                            } else {
                                searchPlaces(query: newValue)
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                searchResults = []
                                isSearching = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.clearIcon)
                        }
                        .transition(MotionPolicy.Transition.enterPop)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .momentsChromeGlass(in: Capsule())
            }
            .padding(.bottom, 20)

            // Lista de ubicaciones
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Ubicaciones cercanas
                        if isLoadingNearby {
                            SectionHeader(title: NSLocalizedString("stickerview.location.searchingNearby", comment: "Searching nearby places"), icon: "location", color: .blue)

                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if nearbyPlaces.isEmpty {
                            EmptyNearbyView()
                        } else {
                            SectionHeader(
                                title: NSLocalizedString("stickerview.location.nearby", comment: "Nearby places"),
                                attachmentIcon: .location,
                                color: .red
                            )

                            ForEach(nearbyPlaces, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    } else {
                        // Resultados de búsqueda
                        if isSearching {
                            SectionHeader(title: NSLocalizedString("stickerview.location.searching", comment: "Searching"), icon: "magnifyingglass", color: .blue)

                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if searchResults.isEmpty {
                            EmptySearchView(searchQuery: searchText)
                        } else {
                            SectionHeader(
                                title: searchResults.count == 1
                                    ? String(format: NSLocalizedString("stickerview.location.results.one", comment: "One location result"), searchResults.count)
                                    : String(format: NSLocalizedString("stickerview.location.results.other", comment: "Multiple location results"), searchResults.count),
                                attachmentIcon: .location,
                                color: .green
                            )

                            ForEach(searchResults, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: searchText), value: searchText)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: searchResults), value: searchResults)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: nearbyPlaces), value: nearbyPlaces)
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            isTextFieldFocused = true
            requestLocationAndSearch()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            if let location = newLocation {
                userLocation = location
                searchNearbyPlaces()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                requestLocationAndSearch()
            }
        }
        .onDisappear {
            // Limpiar memoria al cerrar la vista
            cleanupMemory()
        }
    }

    // MARK: - Componentes de UI

    private struct LocationRowView: View {
        let location: SmartLocationInputView.LocationResult
        let onTap: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: location.categoryIcon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(width: 20, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(location.address)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)

                            if !location.distanceString.isEmpty {
                                Text("• \(location.distanceString)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.tertiaryText)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.tertiaryText)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private struct SkeletonLocationRow: View {
        @State private var isAnimating = false
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            HStack(spacing: 14) {
                Circle()
                    .fill(palette.skeletonFill)
                    .frame(width: 44, height: 44)
                    .shimmer(isAnimating)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.skeletonFill)
                        .frame(width: 140, height: 14)
                        .shimmer(isAnimating)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.skeletonFill)
                        .frame(width: 100, height: 12)
                        .shimmer(isAnimating)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .onAppear {
                isAnimating = true
            }
        }
    }

    private struct EmptyNearbyView: View {
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("stickerview.nearbyPlacesError")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    Text("stickerview.locationPermissionError")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(.horizontal, 4)
        }
    }

    private struct EmptySearchView: View {
        let searchQuery: String
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("stickerview.noPlacesFound")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    Text(String(format: NSLocalizedString("stickerview.tryDifferentSearch", comment: "Try different search"), searchQuery))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Funciones de búsqueda

    private func requestLocationAndSearch() {
        locationManager.requestLocation()
    }

    private func refreshLocationAndPlaces() {
        // Recargar ubicación y lugares cercanos
        isLoadingNearby = true
        locationManager.requestLocation()

        // Si ya tenemos ubicación, recargar lugares cercanos inmediatamente
        if let currentLocation = locationManager.location {
            userLocation = currentLocation
            searchNearbyPlaces()
        }
    }

    private func searchNearbyPlaces() {
        guard let userLocation = userLocation else { return }

        isLoadingNearby = true

        // Búsqueda más específica para lugares útiles (como en LocationPickerView)
        let searchQueries = [
            NSLocalizedString("stickerview.location.query.restaurants", comment: "Nearby restaurants query"),
            NSLocalizedString("stickerview.location.query.cafes", comment: "Nearby cafes query"),
            NSLocalizedString("stickerview.location.query.shops", comment: "Nearby shops query"),
            NSLocalizedString("stickerview.location.query.parks", comment: "Nearby parks query"),
            NSLocalizedString("stickerview.location.query.museums", comment: "Nearby museums query"),
            NSLocalizedString("stickerview.location.query.hotels", comment: "Nearby hotels query"),
            NSLocalizedString("stickerview.location.query.pharmacies", comment: "Nearby pharmacies query"),
            NSLocalizedString("stickerview.location.query.banks", comment: "Nearby banks query"),
            NSLocalizedString("stickerview.location.query.metroStations", comment: "Nearby metro stations query"),
            NSLocalizedString("stickerview.location.query.libraries", comment: "Nearby libraries query")
        ]

        var allPlaces: [LocationResult] = []
        let group = DispatchGroup()

        // Limitar a 4 búsquedas simultáneas para reducir memoria
        for query in searchQueries.prefix(4) {
            group.enter()

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 1500, // Reducir radio a 1.5km
                longitudinalMeters: 1500
            )
            request.resultTypes = .pointOfInterest

            let search = MKLocalSearch(request: request)
            search.start { response, error in
                defer { group.leave() }

                if let response = response {
                    let places: [LocationResult] = response.mapItems.prefix(2).compactMap { item in // Máximo 2 por categoría
                        guard let name = item.name else { return nil }

                        let distance = userLocation.distance(from: CLLocation(
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude
                        ))

                        let fullAddress = formatAddress(item.placemark)
                        let fullName = "\(name), \(fullAddress)"

                        return LocationResult(
                            displayName: name,
                            fullName: fullName,
                            address: fullAddress,
                            distance: distance,
                            category: item.pointOfInterestCategory?.rawValue ?? "place",
                            coordinate: item.placemark.coordinate
                        )
                    }

                    DispatchQueue.main.async {
                        allPlaces.append(contentsOf: places)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            // Filtrar duplicados manualmente y ordenar por distancia
            var uniquePlaces: [LocationResult] = []
            var seenCoordinates: Set<String> = []

            for place in allPlaces {
                let coordinateKey = "\(place.coordinate.latitude),\(place.coordinate.longitude)"
                if !seenCoordinates.contains(coordinateKey) {
                    seenCoordinates.insert(coordinateKey)
                    uniquePlaces.append(place)
                }
            }

            let sortedPlaces = uniquePlaces.sorted { $0.distance ?? 0 < $1.distance ?? 0 }
            self.nearbyPlaces = Array(sortedPlaces.prefix(12)) // 12 lugares totales
            self.isLoadingNearby = false

            // Limpiar memoria
            allPlaces.removeAll()
        }
    }

    private func searchPlaces(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let userLocation = userLocation {
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 5000, // Reducir radio a 5km para ahorrar memoria
                longitudinalMeters: 5000
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false

                guard let response = response else {
                    self.searchResults = []
                    return
                }

                // Ordenamiento inteligente por relevancia y distancia
                let sortedResults: [LocationResult] = response.mapItems.prefix(15).compactMap { item in
                    guard let name = item.name else { return nil }

                    let distance = self.userLocation?.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))

                    let fullAddress = formatAddress(item.placemark)
                    let fullName = "\(name), \(fullAddress)"

                    return LocationResult(
                        displayName: name,
                        fullName: fullName,
                        address: fullAddress,
                        distance: distance,
                        category: item.pointOfInterestCategory?.rawValue ?? "place",
                        coordinate: item.placemark.coordinate
                    )
                }.sorted { item1, item2 in
                    // Priorizar lugares con nombre
                    let hasName1 = !item1.displayName.isEmpty
                    let hasName2 = !item2.displayName.isEmpty

                    if hasName1 != hasName2 {
                        return hasName1
                    }

                    // Si ambos tienen nombre, priorizar por tipo (POI primero)
                    if hasName1 && hasName2 {
                        let isPOI1 = item1.category != "place"
                        let isPOI2 = item2.category != "place"
                        if isPOI1 != isPOI2 {
                            return isPOI1
                        }
                    }

                    // Finalmente, ordenar por distancia
                    return (item1.distance ?? Double.greatestFiniteMagnitude) < (item2.distance ?? Double.greatestFiniteMagnitude)
                }

                self.searchResults = sortedResults
            }
        }
    }

    private func cleanupMemory() {
        // Limpiar arrays para liberar memoria
        nearbyPlaces.removeAll()
        searchResults.removeAll()
        searchText = ""
        isSearching = false
        isLoadingNearby = false
    }

    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        // ✅ NÚMERO Y CALLE
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        // ✅ CÓDIGO POSTAL
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }

        // ✅ CIUDAD
        if let locality = placemark.locality {
            components.append(locality)
        }

        // ✅ PROVINCIA/ESTADO
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }

        // ✅ PAÍS
        if let country = placemark.country {
            components.append(country)
        }

        return components.joined(separator: ", ")
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

