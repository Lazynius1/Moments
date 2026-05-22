// MARK: - Location Picker Implementation

import CoreLocation
import MapKit
import SwiftUI

struct LocationPickerView: View {
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var locationName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686), // Barcelona por defecto
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showingNearbyPlaces = true
    @State private var nearbyPlaces: [MKMapItem] = []
    @State private var isRequestingLocation = false
    @State private var locationError: String?

    @StateObject private var locationManager = LocationUtilities.shared

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(adaptiveColors.secondary)

                    TextField(NSLocalizedString("creator.location.search", comment: ""), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(adaptiveColors.primary)
                        .onSubmit {
                            searchLocation()
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            showingNearbyPlaces = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(adaptiveColors.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule(), interactive: true)
                .padding()

                // Map
                Map(position: $position) {
                    if let selectedLocation = selectedLocation {
                        Marker(locationName.isEmpty ? "Ubicación" : locationName, coordinate: selectedLocation)
                            .tint(.blue)
                    }
                }
                .onMapCameraChange { context in
                    region = context.region
                }
                .frame(height: 200)
                .cornerRadius(10)
                .padding(.horizontal)

                // Current location button
                HStack {
                    Button(action: {
                        requestCurrentLocation()
                    }) {
                        HStack {
                            if isRequestingLocation {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(adaptiveColors.primary)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text("creator.location.useCurrent")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(adaptiveColors.primary)
                        .padding(.vertical, 8)
                    }
                    .disabled(isRequestingLocation)

                    // Botón para actualizar ubicación si ya tenemos permisos
                    if locationManager.authorizationStatus == .authorizedWhenInUse ||
                       locationManager.authorizationStatus == .authorizedAlways {
                        Button(action: {
                            updateCurrentLocationAndNearbyPlaces()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("common.update")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                            .padding(.vertical, 8)
                        }
                        .disabled(isRequestingLocation)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Error message
                if let error = locationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Places list
                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(adaptiveColors.accent)
                    Text("creator.searching")
                        .foregroundColor(adaptiveColors.secondary)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if showingNearbyPlaces {
                                Text("creator.location.nearby")
                                    .font(.headline)
                                    .foregroundColor(adaptiveColors.primary)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                                    .padding(.bottom, 10)
                            }

                            ForEach(showingNearbyPlaces ? nearbyPlaces : searchResults, id: \.self) { place in
                                LocationRow(place: place) {
                                    selectLocation(place)
                                }
                            }
                        }
                    }
                }
            }
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .toolbarBackground(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("creator.addLocation")
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("creator.tag.done", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(adaptiveColors.primary)
                    .fontWeight(.semibold)
                    .disabled(selectedLocation == nil)
                }
            }
        }
        .onAppear {
            loadNearbyPlaces()
        }
        .onReceive(locationManager.$currentLocation) { location in
            if let location = location, isRequestingLocation {
                let coordinate = location.coordinate
                selectedLocation = coordinate

                // Usar geocoding inverso para obtener el nombre real de la ubicación
                getLocationNameFromCoordinates(coordinate)

                let newRegion = MKCoordinateRegion(center: coordinate, span: region.span)
                region = newRegion
                withAnimation {
                    position = .region(newRegion)
                }
                isRequestingLocation = false
                loadNearbyPlaces() // Recargar lugares cercanos con nueva ubicación
            }
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            if status == .denied || status == .restricted {
                locationError = NSLocalizedString("creator.location.permissionDenied", comment: "")
                isRequestingLocation = false
            }
        }
    }

    private func searchLocation() {
        guard !searchText.isEmpty else { return }

        isSearching = true
        showingNearbyPlaces = false

        // Usar ubicación del usuario si está disponible, si no usar la región del mapa
        let searchRegion = locationManager.currentLocation != nil ?
            MKCoordinateRegion(
                center: locationManager.currentLocation!.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ) : region

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = searchRegion
        request.resultTypes = [.pointOfInterest, .address] // Incluir direcciones y POIs

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false

                if let response = response {
                    // Ordenar resultados por relevancia y distancia
                    let sortedResults = response.mapItems.sorted { item1, item2 in
                        // Priorizar lugares con nombre
                        let hasName1 = item1.name != nil && !item1.name!.isEmpty
                        let hasName2 = item2.name != nil && !item2.name!.isEmpty

                        if hasName1 != hasName2 {
                            return hasName1
                        }

                        // Si ambos tienen nombre, priorizar por tipo (POI primero)
                        if hasName1 && hasName2 {
                            let isPOI1 = item1.pointOfInterestCategory != nil
                            let isPOI2 = item2.pointOfInterestCategory != nil
                            if isPOI1 != isPOI2 {
                                return isPOI1
                            }
                        }

                        return true
                    }

                    searchResults = sortedResults
                } else {
                    searchResults = []
                }
            }
        }
    }

    private func loadNearbyPlaces() {
        // Priorizar ubicación del usuario, luego ubicación seleccionada, luego región por defecto
        let centerCoordinate: CLLocationCoordinate2D

        if let currentLocation = locationManager.currentLocation {
            centerCoordinate = currentLocation.coordinate
        } else if let selectedLocation = selectedLocation {
            centerCoordinate = selectedLocation
        } else {
            centerCoordinate = region.center
        }

        let searchRegion = MKCoordinateRegion(
            center: centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        // Búsqueda más específica para lugares útiles
        let searchQueries = [
            "restaurantes",
            "cafés",
            "tiendas",
            "parques",
            "museos",
            "hoteles",
            "farmacias",
            "bancos",
            "estaciones de metro",
            "bibliotecas"
        ]

        var allPlaces: [MKMapItem] = []
        let group = DispatchGroup()

        for query in searchQueries.prefix(5) { // Solo usar los primeros 5 para no sobrecargar
            group.enter()

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            request.resultTypes = .pointOfInterest

            let search = MKLocalSearch(request: request)
            search.start { response, error in
                defer { group.leave() }

                if let response = response {
                    DispatchQueue.main.async {
                        allPlaces.append(contentsOf: response.mapItems.prefix(3)) // Máximo 3 por categoría
                    }
                }
            }
        }

        group.notify(queue: .main) {
            // Filtrar duplicados y ordenar por distancia
            let uniquePlaces = Array(Set(allPlaces)).prefix(15)
            self.nearbyPlaces = Array(uniquePlaces)
        }
    }

    private func requestCurrentLocation() {
        isRequestingLocation = true
        locationError = nil

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestLocationPermission()
        case .denied, .restricted:
            locationError = NSLocalizedString("creator.location.permissionDenied", comment: "")
            isRequestingLocation = false
        case .authorizedWhenInUse, .authorizedAlways:
            if let currentLocation = locationManager.currentLocation {
                let coordinate = currentLocation.coordinate
                selectedLocation = coordinate

                // Usar geocoding inverso para obtener el nombre real de la ubicación
                getLocationNameFromCoordinates(coordinate)

                let newRegion = MKCoordinateRegion(center: coordinate, span: region.span)
                region = newRegion
                withAnimation {
                    position = .region(newRegion)
                }
                isRequestingLocation = false
            } else {
                // Si no hay ubicación actual, solicitar una nueva
                locationManager.requestLocationPermission()
            }
        @unknown default:
            locationError = NSLocalizedString("creator.location.unknownPermissionState", comment: "")
            isRequestingLocation = false
        }
    }

    private func getLocationNameFromCoordinates(_ coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    // Generar nombre limpio y conciso (estilo nativo)
                    self.locationName = self.generateCleanLocationName(from: placemark)
                } else {
                    self.locationName = NSLocalizedString("creator.location.current", comment: "")
                }
            }
        }
    }

    private func generateCleanLocationName(from placemark: CLPlacemark) -> String {
        // Priorizar el nombre del lugar si existe
        if let name = placemark.name, !name.isEmpty {
            // Si es un lugar específico, usar solo el nombre + ciudad
            if let locality = placemark.locality, !locality.isEmpty {
                return "\(name), \(locality)"
            }
            return name
        }

        // Si no hay nombre específico, usar calle + ciudad
        if let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty {
            if let locality = placemark.locality, !locality.isEmpty {
                return "\(thoroughfare), \(locality)"
            }
            return thoroughfare
        }

        // Fallback a ciudad
        if let locality = placemark.locality, !locality.isEmpty {
            return locality
        }

        if let administrativeArea = placemark.administrativeArea, !administrativeArea.isEmpty {
            return administrativeArea
        }

        return NSLocalizedString("creator.location.current", comment: "")
    }

    private func updateCurrentLocationAndNearbyPlaces() {
        isRequestingLocation = true
        locationError = nil

        // Solicitar nueva ubicación
        locationManager.requestLocationPermission()

        // También actualizar la región del mapa si tenemos ubicación actual
        if let currentLocation = locationManager.currentLocation {
            let coordinate = currentLocation.coordinate

            // Actualizar la región del mapa
            let newRegion = MKCoordinateRegion(center: coordinate, span: region.span)
            region = newRegion
            withAnimation {
                position = .region(newRegion)
            }

            // Actualizar la ubicación seleccionada si no hay ninguna
            if selectedLocation == nil {
                selectedLocation = coordinate
                getLocationNameFromCoordinates(coordinate)
            }

            // Recargar lugares cercanos con la nueva ubicación
            loadNearbyPlaces()
        }
    }

    private func selectLocation(_ place: MKMapItem) {
        selectedLocation = place.placemark.coordinate
        locationName = place.name ?? NSLocalizedString("creator.location.selected", comment: "")

        let newRegion = MKCoordinateRegion(center: place.placemark.coordinate, span: region.span)
        region = newRegion
        withAnimation {
            position = .region(newRegion)
        }
    }
}

struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct LocationRow: View {
    let place: MKMapItem
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var categoryIcon: String {
        guard let category = place.pointOfInterestCategory else { return "mappin" }

        switch category {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .store: return "bag"
        case .park: return "tree"
        case .museum: return "building.columns"
        case .hotel: return "bed.double"
        case .pharmacy: return "cross.case"
        case .bank: return "building.columns"
        case .school: return "graduationcap"
        case .hospital: return "cross.case"
        case .gasStation: return "fuelpump"
        case .airport: return "airplane"
        case .beach: return "beach.umbrella"
        case .theater: return "theatermasks"
        case .stadium: return "sportscourt"
        case .university: return "building.columns"
        case .library: return "books.vertical"
        case .postOffice: return "envelope"
        case .police: return "shield"
        case .fireStation: return "flame"
        default: return "mappin"
        }
    }

    private var categoryName: String {
        guard let category = place.pointOfInterestCategory else { return "Lugar" }

        switch category {
        case .restaurant: return "Restaurante"
        case .cafe: return "Café"
        case .store: return "Tienda"
        case .park: return "Parque"
        case .museum: return "Museo"
        case .hotel: return "Hotel"
        case .pharmacy: return "Farmacia"
        case .bank: return "Banco"
        case .school: return "Escuela"
        case .hospital: return "Hospital"
        case .gasStation: return "Gasolinera"
        case .airport: return "Aeropuerto"
        case .beach: return "Playa"
        case .theater: return "Teatro"
        case .stadium: return "Estadio"
        case .university: return "Universidad"
        case .library: return "Biblioteca"
        case .postOffice: return "Oficina de Correos"
        case .police: return "Policía"
        case .fireStation: return "Bomberos"
        default: return "Lugar"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icono de categoría
                Image(systemName: categoryIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "Ubicación sin nombre")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(adaptiveColors.primary)

                    Text(categoryName)
                        .font(.caption)
                        .foregroundColor(adaptiveColors.secondary)

                    if let address = place.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(adaptiveColors.secondary.opacity(0.8))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(adaptiveColors.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Divider()
            .background(
                colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2)
            )
    }
}
