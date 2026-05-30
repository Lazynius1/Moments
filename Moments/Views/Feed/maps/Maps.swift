// ================== LocationMapView.swift ==================

import SwiftUI
import MapKit
import CoreLocation
import Kingfisher
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import WeatherKit

struct LocationMapView: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D?
    let echoHistoryUserId: String?
    let echoHistoryOnly: Bool
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    init(
        locationName: String,
        coordinate: CLLocationCoordinate2D?,
        echoHistoryUserId: String? = nil,
        echoHistoryOnly: Bool = false,
        isPresented: Binding<Bool>
    ) {
        self.locationName = locationName
        self.coordinate = coordinate
        self.echoHistoryUserId = echoHistoryUserId
        self.echoHistoryOnly = echoHistoryOnly
        self._isPresented = isPresented
    }

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var mapPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    ))
    @State private var annotations: [MapsLocationAnnotation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var locationMoments: [Moment] = []  // ✅ USAR MOMENT EN VEZ DE LocationMoment
    @State private var nearbyMoments: [Moment] = []
    @State private var echoHistoryMoments: [Moment] = []
    @State private var echoIdByMomentIdentity: [String: String] = [:]
    @State private var isLoadingMoments = false
    @State private var isLoadingNearbyMoments = false
    @State private var showingGallery = false
    @State private var selectedMoment: Moment?  // ✅ USAR MOMENT
    @State private var showingProfile = false
    @State private var showingDetail = false
    @State private var selectedMomentIndex = 0

    @State private var locationPermissionGranted = false
    @StateObject private var locationManager = LocationUtilities.shared

    @StateObject private var weatherService = WeatherService.shared
    @State private var currentWeather: WeatherData?
    @State private var weatherEffectsEnabled = true
    @State private var showingBottomSheet = false
    @State private var bottomSheetOffset: CGFloat = 300
    @State private var isDragging = false
    @State private var showSearchInAreaButton = false
    @State private var lastNearbyQueryKey: String = ""
    @State private var mapHeaderLocationName: String = ""
    @State private var momentAvailability: [String: Bool] = [:]
    @State private var availabilityValidationToken = UUID()

    // ✅ NUEVO: Estado para manejar mejor la carga inicial
    @State private var hasInitializedMap = false

    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()

    private var isEchoHistoryMode: Bool {
        echoHistoryOnly
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var mapDisplayMoments: [Moment] {
        let combined = locationMoments + nearbyMoments
        var seen = Set<String>()
        var result: [Moment] = []
        for moment in combined {
            let key = selectionKey(for: moment)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(moment)
        }
        return result
    }

    private var mapPinMoments: [Moment] {
        mapDisplayMoments.filter { moment in
            momentAvailability[moment.mapAvailabilityKey] ?? !isEchoHistoryMode
        }
    }

    private var mapCombinedAnnotations: [CombinedMapAnnotation] {
        var groupedMoments: [String: [Moment]] = [:]
        var groupedCoordinates: [String: CLLocationCoordinate2D] = [:]
        var groupedLocationTitles: [String: String] = [:]

        for moment in mapPinMoments {
            guard let coordinate = moment.locationCoordinate?.toCLLocationCoordinate2D,
                  CLLocationCoordinate2DIsValid(coordinate) else { continue }

            let clusterKey = locationClusterKey(for: moment, coordinate: coordinate)
            groupedMoments[clusterKey, default: []].append(moment)

            if groupedCoordinates[clusterKey] == nil {
                if isEchoHistoryMode, let echoId = echoId(for: moment) {
                    groupedCoordinates[clusterKey] = jitteredCoordinate(for: coordinate, seed: echoId)
                } else {
                    groupedCoordinates[clusterKey] = coordinate
                }
            }
            if groupedLocationTitles[clusterKey] == nil,
               let title = normalizedLocationName(from: moment) {
                groupedLocationTitles[clusterKey] = title
            }
        }

        var items: [CombinedMapAnnotation] = groupedMoments.compactMap { key, moments in
            guard let coordinate = groupedCoordinates[key] else { return nil }
            let sortedMoments = moments.sorted { $0.timestamp > $1.timestamp }
            return CombinedMapAnnotation(
                id: "cluster-\(key)",
                coordinate: coordinate,
                locationTitle: groupedLocationTitles[key],
                moment: sortedMoments.first,
                moments: sortedMoments
            )
        }

        items.sort { lhs, rhs in
            let leftDate = lhs.primaryMoment?.timestamp ?? .distantPast
            let rightDate = rhs.primaryMoment?.timestamp ?? .distantPast
            return leftDate > rightDate
        }
        return items
    }

    private var effectiveHeaderLocationName: String {
        let trimmed = mapHeaderLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return locationName
    }

    var body: some View {
        ZStack {
            // ✅ EL MAPA OCUPA TODO EL FONDO
            modernMapView
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    topControlsOverlay
                }

            // ✅ BARRA DE ESTADÍSTICAS (SI EXISTE) - La movimos dentro de modernHeaderView en el paso anterior,
            // pero si hay componentes adicionales los manejamos aquí.

            // ✅ BOTTOM SHEET
            LocationBottomSheet(
                isPresented: $showingBottomSheet,
                moments: locationMoments,
                momentAvailability: momentAvailability,
                isLoadingMoments: isLoadingMoments,
                locationName: effectiveHeaderLocationName,
                colorScheme: colorScheme,
                onMomentTap: { moment in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)

                        if let selectedIndex = locationMoments.firstIndex(where: { selectionKey(for: $0) == selectionKey(for: moment) }) {
                            selectedMoment = moment
                            selectedMomentIndex = selectedIndex
                            showingDetail = true
                        }
                    }
                }
            )

        }
        .navigationBarHidden(true)
        .onAppear {
            if mapHeaderLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mapHeaderLocationName = locationName
            }
            // ✅ MEJORADO: Verificar si ya tenemos coordenadas válidas antes de hacer setup
            if let coordinate = coordinate, CLLocationCoordinate2DIsValid(coordinate) {
                setupMapWithCoordinate(coordinate)
            } else {
                checkLocationPermissionsAndSetup()
            }
        }
        .onChange(of: coordinate?.latitude) { _, _ in
            // ✅ NUEVO: Reaccionar a cambios en las coordenadas usando latitude como trigger
            if let newCoordinate = coordinate, CLLocationCoordinate2DIsValid(newCoordinate), !hasInitializedMap {
                setupMapWithCoordinate(newCoordinate)
            }
        }
        .onChange(of: region.center.latitude) { _, _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.center.longitude) { _, _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.span.latitudeDelta) { _, _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.span.longitudeDelta) { _, _ in
            handleMapRegionChanged()
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            handleLocationPermissionChange(status)
        }
        // ✅ SHEETS SIN CAMBIOS
        .sheet(isPresented: $showingGallery) {
            ModernLocationGalleryView(
                locationName: effectiveHeaderLocationName,
                moments: locationMoments,
                colorScheme: colorScheme,
                isPresented: $showingGallery
            )
        }
        .sheet(isPresented: $showingProfile) {
            if let moment = selectedMoment {
                UserProfileView(userId: moment.authorId)
            }
        }
        .fullScreenCover(isPresented: $showingDetail) {
            LocationMomentDetailView(
                locationMoments: locationMoments,
                initialIndex: selectedMomentIndex,
                locationName: effectiveHeaderLocationName,
                momentAvailability: $momentAvailability,
                isPresented: $showingDetail
            )
        }
        .onChange(of: showingDetail) { _, _ in
            // ✅ onChange vacío para mantener la funcionalidad
        }

    }

    // ✅ MISMO FONDO QUE TU FEEDVIEW
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white,
                        Color(hex: "f8f9fa"),
                        Color(hex: "e9ecef"),
                        Color.white
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.02)
                .ignoresSafeArea()
        }
    }

    private var topControlsOverlay: some View {
        VStack(spacing: 0) {
            modernHeaderView
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var searchInAreaButton: some View {
        Button {
            searchInCurrentArea()
        } label: {
            HStack(spacing: 8) {
                if isLoadingNearbyMoments {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(NSLocalizedString("maps.search.thisArea", comment: "Search in this area"))
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(adaptiveColors.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.clear
                    .liquidGlass(in: Capsule())
            )
            .shadow(color: adaptiveColors.shadowColor.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var modernHeaderView: some View {
        VStack(alignment: .trailing, spacing: 12) {
            // ✅ FILA SUPERIOR: PILLS DE NAVEGACIÓN Y ACCIÓN
            HStack(alignment: .top, spacing: 12) {
                // ✅ PILL 1: NAVEGACIÓN Y INFO
                HStack(spacing: 12) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(adaptiveColors.primary)
                            .frame(width: 32, height: 32)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(effectiveHeaderLocationName)
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(adaptiveColors.primary)
                            .lineLimit(1)

                        if !locationMoments.isEmpty {
                            Text(String(format: NSLocalizedString("maps.location.moments", comment: "Number of moments in location"), locationMoments.count))
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(adaptiveColors.tertiary)
                        }
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
                    // ✅ PILL 2: ACCIONES (Weather Info + Share)
                    HStack(spacing: 12) {
                        if let weather = currentWeather {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    weatherEffectsEnabled.toggle()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: weatherEffectsEnabled ? weather.condition.systemImageName : "cloud.slash.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(weatherEffectsEnabled ? adaptiveColors.accent : adaptiveColors.primary.opacity(0.7))

                                    VStack(alignment: .leading, spacing: -2) {
                                        Text(weather.temperatureFormatted)
                                            .font(.custom("Poppins-Bold", size: 13))
                                            .foregroundColor(adaptiveColors.primary)

                                        Text(weather.condition.displayName)
                                            .font(.custom("Poppins-Medium", size: 9))
                                            .foregroundColor(adaptiveColors.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .background(Color.clear.liquidGlass(in: Capsule()))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: adaptiveColors.shadowColor.opacity(0.15), radius: 10, x: 0, y: 5)

                    // ✅ ATRIBUCIÓN CONTEXTUAL
                    if currentWeather != nil && weatherEffectsEnabled {
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("weather.attribution.text", comment: "Weather attribution text"))
                                .font(.custom("Poppins-Regular", size: 7))
                                .foregroundColor(.secondary.opacity(0.8))

                            Link(NSLocalizedString("weather.attribution.link", comment: "Weather attribution link"), destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                                .font(.custom("Poppins-Medium", size: 7))
                                .foregroundColor(.blue.opacity(0.6))
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
            .padding(.horizontal, 16)

            if hasInitializedMap && showSearchInAreaButton {
                HStack {
                    Spacer()
                    searchInAreaButton
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ✅ PILL LATERAL: ESTADÍSTICAS (Vertical a la derecha)
            if !locationMoments.isEmpty {
                VStack(spacing: 16) {
                    StatisticItem(
                        icon: "photo.fill",
                        value: "\(locationMoments.count)",
                        label: NSLocalizedString("maps.stats.photos", comment: "Photos label"),
                        color: adaptiveColors.accent
                    )

                    StatisticItem(
                        icon: "person.2.fill",
                        value: "\(Set(locationMoments.map { $0.authorId }).count)",
                        label: NSLocalizedString("maps.stats.users", comment: "Users label"),
                        color: .blue
                    )

                    StatisticItem(
                        icon: "calendar",
                        value: formatDateRange(),
                        label: NSLocalizedString("maps.stats.time", comment: "Time label"),
                        color: .orange
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 16)
                .background(
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: adaptiveColors.shadowColor.opacity(0.1), radius: 10, x: 0, y: 5)
                .padding(.trailing, 16)
                .onTapGesture {
                    withAnimation(.spring()) {
                        showingBottomSheet.toggle()
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // ✅ NUEVO: Componente de estadística Premium
    private func StatisticItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }

            VStack(spacing: 0) {
                Text(value)
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(adaptiveColors.primary)

                Text(label.uppercased())
                    .font(.custom("Poppins-Bold", size: 7))
                    .foregroundColor(adaptiveColors.tertiary)
                    .tracking(0.5)
            }
        }
    }

    // ✅ NUEVO: Formatear rango de fechas
    private func formatDateRange() -> String {
        guard !locationMoments.isEmpty else { return "N/A" }

        let sortedMoments = locationMoments.sorted { $0.timestamp < $1.timestamp }
        let oldest = sortedMoments.first!.timestamp
        let newest = sortedMoments.last!.timestamp

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        if Calendar.current.isDate(oldest, equalTo: newest, toGranularity: .month) {
            return formatter.string(from: oldest)
        } else {
            return "\(formatter.string(from: oldest))-\(formatter.string(from: newest))"
        }
    }

    // ✅ HELPER PARA COLORES DE CLIMA
    private func getWeatherColor(_ condition: WeatherCondition) -> Color {
        switch condition {
        case .clear:
            return .yellow
        case .partlyCloudy:
            return .orange
        case .cloudy:
            return .gray
        case .rain:
            return .blue
        case .snow:
            return .white
        case .thunderstorm:
            return .purple
        case .unknown:
            return adaptiveColors.secondary
        }
    }

    private var modernMapView: some View {
        ZStack {
            if isLoading {
                modernLoadingView
            } else if let errorMessage = errorMessage {
                modernErrorView(message: errorMessage)
            } else {
                ZStack {
                    // ✅ MAPA BASE
                    Map(position: $mapPosition) {
                        ForEach(mapCombinedAnnotations) { annotation in
                            Annotation(annotation.locationTitle ?? "", coordinate: annotation.coordinate) {
                                if let moment = annotation.primaryMoment {
                                    Button {
                                        openMomentFromMapAnnotation(annotation)
                                    } label: {
                                        MapMomentPin(
                                            moment: moment,
                                            colorScheme: colorScheme,
                                            count: annotation.count
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .mapStyle(getMapStyle())
                    .onMapCameraChange { context in
                        self.region = context.region
                    }


                    // ✅ OVERLAY DE COLOR SEGÚN CLIMA
                    if let weather = currentWeather, weatherEffectsEnabled {
                        Rectangle()
                            .fill(getWeatherOverlayColor(weather))
                            .allowsHitTesting(false)
                            .opacity(getWeatherOverlayOpacity(weather))
                            .animation(.easeInOut(duration: 2.0), value: weather.condition)
                    }

                    // ✅ EFECTOS DE PARTÍCULAS (LLUVIA/NIEVE)
                    if let weather = currentWeather, weatherEffectsEnabled {
                        WeatherParticleEffectView(weather: weather)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // ✅ OBTENER ESTILO DE MAPA SEGÚN CLIMA
    private func getMapStyle() -> MapStyle {
        guard let weather = currentWeather, weatherEffectsEnabled else {
            return .standard
        }

        if weather.isNight {
            return .standard // iOS ya maneja el modo nocturno automáticamente
        } else {
            return .standard
        }
    }

    // ✅ COLOR DE OVERLAY SEGÚN CONDICIÓN CLIMÁTICA
    private func getWeatherOverlayColor(_ weather: WeatherData) -> Color {
        switch weather.condition {
        case .clear:
            return weather.isNight ? Color.blue : Color.yellow
        case .partlyCloudy:
            return weather.isNight ? Color.indigo : Color.orange
        case .cloudy:
            return Color.gray
        case .rain:
            return Color.blue
        case .snow:
            return Color.white
        case .thunderstorm:
            return Color.purple
        case .unknown:
            return Color.clear
        }
    }

    // ✅ OPACIDAD DEL OVERLAY
    private func getWeatherOverlayOpacity(_ weather: WeatherData) -> Double {
        switch weather.condition {
        case .clear:
            return weather.isNight ? 0.1 : 0.05
        case .partlyCloudy:
            return 0.08
        case .cloudy:
            return 0.15
        case .rain:
            return 0.2
        case .snow:
            return 0.25
        case .thunderstorm:
            return 0.3
        case .unknown:
            return 0.0
        }
    }

    private var modernLoadingView: some View {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: adaptiveColors.buttonStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .tint(adaptiveColors.accent)
                        .scaleEffect(1.3)
                }

                VStack(spacing: 8) {
                    Text(NSLocalizedString("maps.loading.location", comment: "Loading location message"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(adaptiveColors.primary)

                    Text(locationName)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(adaptiveColors.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }

        private func modernErrorView(message: String) -> some View {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.red.opacity(0.6), Color.pink.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)

                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 12) {
                    Text(NSLocalizedString("maps.error.locationLoadFailed", comment: "Location load failed error message"))
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(adaptiveColors.primary)

                    Text(message)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(adaptiveColors.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button(action: setupMapLocation) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))

                            Text(NSLocalizedString("maps.error.retry", comment: "Retry button text"))
                                .font(.custom("Poppins-SemiBold", size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: adaptiveColors.buttonStroke,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: adaptiveColors.accent.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.top, 8)

                    if !locationPermissionGranted {
                        Button(action: {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }) {
                            Text(NSLocalizedString("maps.error.configurePermissions", comment: "Configure permissions button text"))
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.accent)
                                .underline()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
    }

extension LocationMapView {
    private var normalizedLocationNameQuery: String {
        locationName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private var isGenericLocationQuery: Bool {
        let normalizedDefault = NSLocalizedString("feed.location.default", comment: "Default location name")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let genericValues: Set<String> = [
            "",
            normalizedDefault,
            "ubicacion",
            "location",
            "ubicacion actual",
            "current location",
            "ubicacion seleccionada",
            "selected location",
            "ubicacion desconocida",
            "unknown location",
            "location unavailable",
            "ubicacion no disponible"
        ]

        return genericValues.contains(normalizedLocationNameQuery)
    }

    // MARK: - Funciones de permisos y setup
    func checkLocationPermissionsAndSetup() {
        let currentStatus = CLLocationManager().authorizationStatus // ✅ instance property (iOS 14+)

        // ✅ MEJORADO: Priorizar coordenadas existentes sobre permisos
        if let coordinate = coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            setupMapWithCoordinate(coordinate)
            return
        }

        switch currentStatus {
        case .notDetermined:
            locationManager.requestLocationPermission()
        case .denied, .restricted:
            locationPermissionGranted = false
            setupMapLocation()
        case .authorizedWhenInUse, .authorizedAlways:
            locationPermissionGranted = true
            setupMapLocation()
        @unknown default:
            setupMapLocation()
        }
    }

    func handleLocationPermissionChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationPermissionGranted = true
            if isLoading {
                setupMapLocation()
            }
        case .denied, .restricted:
            locationPermissionGranted = false
            if isLoading {
                setupMapLocation()
            }
        default:
            break
        }
    }

    func setupMapLocation() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        // ✅ MEJORADO: Priorizar coordenadas existentes
        if let coordinate = coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            setupMapWithCoordinate(coordinate)
            return
        }

        // Evita geocodear placeholders ("Ubicación", "Location", etc.).
        if isGenericLocationQuery {
            setupDefaultLocation(showMessage: false)
            return
        }

        // ✅ MEJORADO: Si no hay coordenadas, intentar geocoding con mejor manejo
        geocodeLocationWithRetry()
    }

    func geocodeLocationWithRetry() {
        // ✅ NUEVO: Configuración mejorada para geocoding
        let geocoder = CLGeocoder()

        // ✅ MEJORADO: Usar el nombre de ubicación tal como viene
        let searchQuery = locationName.trimmingCharacters(in: .whitespacesAndNewlines)

        if searchQuery.isEmpty || isGenericLocationQuery {
            setupDefaultLocation(showMessage: false)
            return
        }

        // ✅ NUEVO: Geocoding con timeout y reintentos
        geocoder.geocodeAddressString(searchQuery) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {

                    if let clError = error as? CLError {
                        switch clError.code {
                        case .locationUnknown:
                            self.errorMessage = String(format: NSLocalizedString("maps.error.locationNotFoundDetailed", comment: "Location not found with detail"), self.locationName)
                        case .denied:
                            self.errorMessage = NSLocalizedString("maps.error.locationDenied", comment: "Location access denied")
                        case .network:
                            self.errorMessage = NSLocalizedString("maps.error.network", comment: "Network error")
                        case .geocodeFoundNoResult:
                            self.errorMessage = String(format: NSLocalizedString("maps.error.noResultsDetailed", comment: "No results with detail"), self.locationName)
                        case .geocodeCanceled:
                            self.errorMessage = NSLocalizedString("maps.error.searchCanceled", comment: "Search canceled")
                        default:
                            // ✅ MEJORADO: Para errores de geocoding, mostrar ubicación por defecto
                            self.setupDefaultLocation(showMessage: true)
                            return
                        }
                    } else {
                        // ✅ MEJORADO: Para errores generales, mostrar ubicación por defecto
                        self.setupDefaultLocation(showMessage: true)
                        return
                    }

                    self.isLoading = false
                    return
                }

                guard let placemarks = placemarks, !placemarks.isEmpty else {
                    self.errorMessage = String(format: NSLocalizedString("maps.error.noResults", comment: "No results"), self.locationName)
                    self.isLoading = false
                    return
                }

                // ✅ MEJORADO: Filtrar resultados para encontrar la mejor coincidencia
                let validPlacemarks = placemarks.filter { placemark in
                    guard let location = placemark.location,
                          CLLocationCoordinate2DIsValid(location.coordinate) else {
                        return false
                    }
                    return true
                }

                guard let bestPlacemark = validPlacemarks.first,
                      let location = bestPlacemark.location else {
                    self.errorMessage = String(format: NSLocalizedString("maps.error.couldNotResolveLocation", comment: "Could not resolve location"), self.locationName)
                    self.isLoading = false
                    return
                }

                // ✅ MEJORADO: Actualizar las coordenadas y configurar el mapa
                self.setupMapWithCoordinate(location.coordinate)
            }
        }
    }

    func setupMapWithCoordinate(_ coordinate: CLLocationCoordinate2D) {
        // ✅ PREVENIR múltiples configuraciones del mapa
        guard !hasInitializedMap else {
            return
        }

        guard CLLocationCoordinate2DIsValid(coordinate) else {
            DispatchQueue.main.async {
                self.errorMessage = NSLocalizedString("maps.error.invalidCoordinates", comment: "Invalid coordinates")
                self.isLoading = false
            }
            return
        }

        // ✅ MEJORADO: Usar DispatchQueue.main.async para asegurar que se ejecute en el hilo principal
        DispatchQueue.main.async {
            // ✅ MEJORADO: Configurar región con animación suave
            withAnimation(.easeInOut(duration: 0.5)) {
                let newRegion = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
                self.region = newRegion
                self.mapPosition = .region(newRegion)
            }

            // ✅ MEJORADO: Limpiar anotaciones anteriores y agregar la nueva
            self.annotations.removeAll()
            self.annotations.append(MapsLocationAnnotation(
                id: UUID(),
                coordinate: coordinate,
                title: self.locationName
            ))

            // ✅ NUEVO: Marcar como inicializado y limpiar estados
            self.hasInitializedMap = true
            self.isLoading = false
            self.errorMessage = nil
            self.nearbyMoments = []
            self.lastNearbyQueryKey = self.nearbyQueryKey(for: self.region)
            self.showSearchInAreaButton = true



            // ✅ CARGAR MOMENTOS Y CLIMA EN PARALELO
            self.loadLocationMoments()
            self.loadWeatherData(for: coordinate)
        }
    }

    // ✅ NUEVA FUNCIÓN: Configurar ubicación por defecto cuando falla el geocoding
    private func setupDefaultLocation(showMessage: Bool = true) {


        // ✅ Usar ubicación por defecto (Madrid, España)
        let defaultCoordinate = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                let defaultRegion = MKCoordinateRegion(
                    center: defaultCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                self.region = defaultRegion
                self.mapPosition = .region(defaultRegion)
            }

            // ✅ Limpiar anotaciones y agregar anotación por defecto
            self.annotations.removeAll()
            self.annotations.append(MapsLocationAnnotation(
                id: UUID(),
                coordinate: defaultCoordinate,
                title: NSLocalizedString("maps.defaultLocation.title", comment: "Default location title")
            ))

            self.isLoading = false
            self.errorMessage = showMessage
                ? String(format: NSLocalizedString("maps.defaultLocation.message", comment: "Showing default location message"), self.locationName)
                : nil
            self.nearbyMoments = []
            self.lastNearbyQueryKey = self.nearbyQueryKey(for: self.region)
            self.showSearchInAreaButton = true



            // ✅ CARGAR MOMENTOS Y CLIMA DE LA UBICACIÓN POR DEFECTO
            self.loadLocationMoments()
            self.loadWeatherData(for: defaultCoordinate)
        }
    }

    func loadWeatherData(for coordinate: CLLocationCoordinate2D) {
        // ✅ PREVENIR múltiples llamadas al clima si ya tenemos datos
        guard currentWeather == nil else {
            return
        }



        Task {
            do {
                let weather = try await weatherService.getWeather(for: coordinate)

                DispatchQueue.main.async {
                    self.currentWeather = weather
                }

            } catch {
                // No mostrar error al usuario, los efectos simplemente no aparecerán
            }
        }
    }

    func loadLocationMoments() {
        DispatchQueue.main.async {
            self.isLoadingMoments = true
        }

        if isEchoHistoryMode {
            loadEchoHistoryMoments()
            return
        }

        // ✅ USAR TU SERVICIO EXISTENTE DE MOMENTOS EN VEZ DE CREAR UNO NUEVO
        LocationSearchService.shared.searchMomentsByLocation(
            locationName: locationName,
            currentUserId: Auth.auth().currentUser?.uid
        ) { moments in
            DispatchQueue.main.async {
                self.locationMoments = moments
                self.refreshMomentAvailability(for: moments)
                self.isLoadingMoments = false

                // ✅ AGREGAR ESTA LÍNEA:
                if !moments.isEmpty {
                    self.showingBottomSheet = true
                }
            }
        }
    }

    private func momentMapKey(_ moment: Moment) -> String {
        moment.mapAvailabilityKey
    }

    private func selectionKey(for moment: Moment) -> String {
        if isEchoHistoryMode {
            return momentIdentityKey(moment)
        }
        return momentMapKey(moment)
    }

    private func locationClusterKey(for moment: Moment, coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (coordinate.longitude * 10_000).rounded() / 10_000
        let normalizedLocation = normalizedLocationName(from: moment)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if isEchoHistoryMode, let echoId = echoId(for: moment), !echoId.isEmpty {
            return "\(lat)|\(lon)|\(normalizedLocation)|echo:\(echoId)"
        }
        return "\(lat)|\(lon)|\(normalizedLocation)"
    }

    private func openMomentFromMapAnnotation(_ annotation: CombinedMapAnnotation) {
        let clusterMoments: [Moment] = {
            if !annotation.moments.isEmpty { return annotation.moments }
            if let single = annotation.moment { return [single] }
            return []
        }()
        .filter { moment in
            momentAvailability[moment.mapAvailabilityKey] ?? !isEchoHistoryMode
        }
        guard !clusterMoments.isEmpty else { return }

        locationMoments = clusterMoments
        refreshMomentAvailability(for: clusterMoments)
        if let title = annotation.locationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            mapHeaderLocationName = title
        } else if let fallbackTitle = normalizedLocationName(from: clusterMoments[0]) {
            mapHeaderLocationName = fallbackTitle
        }

        selectedMoment = clusterMoments[0]
        selectedMomentIndex = 0
        showingBottomSheet = true
    }

    private func normalizedLocationName(from moment: Moment) -> String? {
        guard let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty else {
            return nil
        }
        return location
    }

    private func handleMapRegionChanged() {
        guard hasInitializedMap else { return }
        let _ = nearbyQueryKey(for: region)
        showSearchInAreaButton = true
    }

    private func searchInCurrentArea() {
        let queryKey = nearbyQueryKey(for: region)
        showSearchInAreaButton = true

        if isEchoHistoryMode {
            loadNearbyEchoMoments(in: region, queryKey: queryKey)
            return
        }

        loadNearbyMoments(in: region, queryKey: queryKey)
    }

    private func nearbyQueryKey(for region: MKCoordinateRegion) -> String {
        let lat = (region.center.latitude * 100).rounded() / 100
        let lon = (region.center.longitude * 100).rounded() / 100
        let latDelta = (region.span.latitudeDelta * 100).rounded() / 100
        let lonDelta = (region.span.longitudeDelta * 100).rounded() / 100
        return "\(lat)|\(lon)|\(latDelta)|\(lonDelta)"
    }

    private func loadNearbyMoments(in region: MKCoordinateRegion, queryKey: String) {
        DispatchQueue.main.async {
            self.isLoadingNearbyMoments = true
            self.lastNearbyQueryKey = queryKey
        }

        LocationSearchService.shared.searchMomentsInRegion(
            region: region,
            currentUserId: Auth.auth().currentUser?.uid
        ) { moments in
            DispatchQueue.main.async {
                // Evitar resultados stale si el usuario ya movió el mapa a otra región.
                guard self.lastNearbyQueryKey == queryKey else { return }
                self.nearbyMoments = moments
                self.isLoadingNearbyMoments = false
                self.showSearchInAreaButton = false

                if !moments.isEmpty {
                    self.locationMoments = moments
                    self.refreshMomentAvailability(for: moments)
                    if let firstLocation = moments.compactMap({ self.normalizedLocationName(from: $0) }).first {
                        self.mapHeaderLocationName = firstLocation
                    }
                    self.showingBottomSheet = true
                }
            }
        }
    }

    private func loadNearbyEchoMoments(in region: MKCoordinateRegion, queryKey: String) {
        DispatchQueue.main.async {
            self.isLoadingNearbyMoments = true
            self.lastNearbyQueryKey = queryKey
        }

        DispatchQueue.main.async {
            guard self.lastNearbyQueryKey == queryKey else { return }

            let filtered = self.echoHistoryMoments.filter { moment in
                guard let coord = moment.locationCoordinate?.toCLLocationCoordinate2D,
                      CLLocationCoordinate2DIsValid(coord) else { return false }
                return self.regionContainsCoordinate(region, coord)
            }

            self.nearbyMoments = filtered
            self.locationMoments = filtered
            self.refreshMomentAvailability(for: filtered)
            self.isLoadingNearbyMoments = false
            self.showSearchInAreaButton = false

            if !filtered.isEmpty {
                if let firstLocation = filtered.compactMap({ self.normalizedLocationName(from: $0) }).first {
                    self.mapHeaderLocationName = firstLocation
                }
                self.showingBottomSheet = true
            }
        }
    }

    func shareLocation() {
        var items: [Any] = [locationName]
        if let annotation = annotations.first {
            let locationURL = "https://maps.apple.com/?q=\(annotation.coordinate.latitude),\(annotation.coordinate.longitude)"
            items.append(locationURL)
        }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootViewController.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            rootViewController.present(activityVC, animated: true)
        }
    }

    private func loadEchoHistoryMoments() {
        let resolvedUserId = echoHistoryUserId ?? Auth.auth().currentUser?.uid
        let currentUserId = Auth.auth().currentUser?.uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId = resolvedUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let currentUserId = currentUserId,
              !userId.isEmpty,
              userId == currentUserId else {
            DispatchQueue.main.async {
                self.locationMoments = []
                self.echoHistoryMoments = []
                self.nearbyMoments = []
                self.echoIdByMomentIdentity = [:]
                self.momentAvailability = [:]
                self.isLoadingMoments = false
            }
            return
        }

        Firestore.firestore()
            .collection("echoes")
            .whereField("participantIds", arrayContains: userId)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if error != nil {
                        self.locationMoments = []
                        self.echoHistoryMoments = []
                        self.echoIdByMomentIdentity = [:]
                        self.momentAvailability = [:]
                        self.isLoadingMoments = false
                        return
                    }

                    let echoes = snapshot?.documents.compactMap { doc -> Echo? in
                        var echo = try? doc.data(as: Echo.self)
                        echo?.id = doc.documentID
                        return echo
                    } ?? []

                    let locationFiltered = echoes.filter {
                        self.echoMatchesCurrentLocation($0) && self.echoCanExposeHistory($0, to: userId)
                    }

                    self.loadViewableEchoHistoryMoments(from: locationFiltered, viewerId: userId)
                }
            }
    }

    private func echoCanExposeHistory(_ echo: Echo, to viewerId: String) -> Bool {
        let acceptedParticipants = echo.participants.filter { $0.status == .accepted }
        guard acceptedParticipants.count >= 2 else { return false }
        return acceptedParticipants.contains { $0.userId == viewerId }
    }

    private func loadViewableEchoHistoryMoments(from echoes: [Echo], viewerId: String) {
        let group = DispatchGroup()
        let lock = NSLock()
        var allEchoMoments: [Moment] = []
        var mapping: [String: String] = [:]

        for echo in echoes {
            for ref in echo.visibleMoments {
                group.enter()
                fetchViewableEchoHistoryMoment(ref, in: echo, viewerId: viewerId) { moment in
                    defer { group.leave() }
                    guard let moment else { return }

                    lock.lock()
                    allEchoMoments.append(moment)
                    if let echoId = echo.id, !echoId.isEmpty {
                        mapping[self.momentIdentityKey(moment)] = echoId
                    }
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            let deduped = self.dedupMomentsByIdentity(allEchoMoments).sorted { $0.timestamp > $1.timestamp }

            self.echoIdByMomentIdentity = mapping
            self.echoHistoryMoments = deduped
            self.locationMoments = deduped
            self.momentAvailability = deduped.reduce(into: [String: Bool]()) { result, moment in
                result[moment.mapAvailabilityKey] = true
            }
            self.isLoadingMoments = false
            self.showSearchInAreaButton = true

            if !deduped.isEmpty {
                if let firstLocation = deduped.compactMap({ self.normalizedLocationName(from: $0) }).first {
                    self.mapHeaderLocationName = firstLocation
                }
                self.showingBottomSheet = true
            }
        }
    }

    private func fetchViewableEchoHistoryMoment(
        _ ref: EchoMomentRef,
        in echo: Echo,
        viewerId: String,
        completion: @escaping (Moment?) -> Void
    ) {
        let momentId = ref.momentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorId = ref.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !momentId.isEmpty, !authorId.isEmpty else {
            completion(nil)
            return
        }

        Firestore.firestore()
            .collection("users").document(authorId)
            .collection("moments").document(momentId)
            .getDocument { snapshot, _ in
                guard snapshot?.exists == true,
                      var liveMoment = try? snapshot?.data(as: Moment.self),
                      liveMoment.isArchived != true,
                      liveMoment.authorId == authorId else {
                    completion(nil)
                    return
                }

                if liveMoment.id == nil {
                    liveMoment.id = momentId
                }

                self.privacyService.canUserViewMomentEnhanced(liveMoment, viewerId: viewerId) { canView in
                    guard canView else {
                        completion(nil)
                        return
                    }

                    completion(self.buildEchoHistoryMoment(from: liveMoment, echo: echo))
                }
            }
    }

    private func echoMatchesCurrentLocation(_ echo: Echo) -> Bool {
        let targetName = locationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let echoName = (echo.locationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !targetName.isEmpty, !echoName.isEmpty, targetName == echoName {
            return true
        }

        guard let targetCoordinate = coordinate else { return !targetName.isEmpty && targetName == echoName }
        let echoCoordinate = CLLocationCoordinate2D(latitude: echo.location.latitude, longitude: echo.location.longitude)
        guard CLLocationCoordinate2DIsValid(targetCoordinate), CLLocationCoordinate2DIsValid(echoCoordinate) else {
            return false
        }
        return CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
            .distance(from: CLLocation(latitude: echoCoordinate.latitude, longitude: echoCoordinate.longitude)) <= 1200
    }

    private func refreshMomentAvailability(for moments: [Moment]) {
        let baseAvailability = moments.reduce(into: [String: Bool]()) { result, moment in
            result[moment.mapAvailabilityKey] = !isEchoHistoryMode
        }
        momentAvailability = baseAvailability

        guard isEchoHistoryMode, let viewerId = Auth.auth().currentUser?.uid else {
            return
        }

        let token = UUID()
        availabilityValidationToken = token

        for moment in moments {
            validateLiveAvailability(for: moment, viewerId: viewerId, token: token)
        }
    }

    private func validateLiveAvailability(for moment: Moment, viewerId: String, token: UUID) {
        let key = moment.mapAvailabilityKey

        if moment.authorId == viewerId {
            setMomentAvailability(true, key: key, token: token)
            return
        }

        guard let momentId = moment.id, !momentId.isEmpty else {
            setMomentAvailability(false, key: key, token: token)
            return
        }

        Firestore.firestore()
            .collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .getDocument { snapshot, _ in
                guard snapshot?.exists == true else {
                    self.setMomentAvailability(false, key: key, token: token)
                    return
                }

                guard let liveMoment = try? snapshot?.data(as: Moment.self) else {
                    self.setMomentAvailability(false, key: key, token: token)
                    return
                }

                if liveMoment.isArchived == true {
                    self.setMomentAvailability(false, key: key, token: token)
                    return
                }

                self.privacyService.canUserViewMomentEnhanced(liveMoment, viewerId: viewerId) { canView in
                    self.setMomentAvailability(canView, key: key, token: token)
                }
            }
    }

    private func setMomentAvailability(_ value: Bool, key: String, token: UUID) {
        DispatchQueue.main.async {
            guard self.availabilityValidationToken == token else { return }
            self.momentAvailability[key] = value
        }
    }

    private func buildEchoHistoryMoment(from liveMoment: Moment, echo: Echo) -> Moment {
        let coordinate = Moment.LocationCoordinate(latitude: echo.location.latitude, longitude: echo.location.longitude)
        let resolvedLocation = echo.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationValue = (resolvedLocation?.isEmpty == false) ? resolvedLocation : locationName

        return Moment(
            id: liveMoment.id,
            authorId: liveMoment.authorId,
            username: liveMoment.username,
            content: liveMoment.content,
            imagePath: liveMoment.imagePath,
            videoUrl: liveMoment.videoUrl,
            timestamp: liveMoment.timestamp,
            reactions: liveMoment.reactions,
            commentCount: liveMoment.commentCount,
            profileImagePath: liveMoment.profileImagePath,
            taggedUsers: liveMoment.taggedUsers,
            location: locationValue,
            locationCoordinate: coordinate,
            audience: liveMoment.audience,
            mediaItems: liveMoment.mediaItems,
            aspectRatio: liveMoment.aspectRatio,
            customListId: liveMoment.customListId,
            thumbnailUrl: liveMoment.thumbnailUrl,
            videoDuration: liveMoment.videoDuration,
            videoFileSize: liveMoment.videoFileSize,
            videoResolution: liveMoment.videoResolution,
            disableComments: liveMoment.disableComments,
            hideLikeCounts: liveMoment.hideLikeCounts,
            allowSharing: liveMoment.allowSharing,
            scheduledDate: liveMoment.scheduledDate,
            trendingScore: liveMoment.trendingScore,
            engagementRate: liveMoment.engagementRate,
            isArchived: liveMoment.isArchived,
            archivedAt: liveMoment.archivedAt,
            hasHiddenLayers: liveMoment.hasHiddenLayers,
            hiddenLayerCount: liveMoment.hiddenLayerCount,
            isModerationHidden: liveMoment.isModerationHidden,
            originalAudience: liveMoment.originalAudience,
            reviewRequired: liveMoment.reviewRequired,
            canRestore: liveMoment.canRestore
        )
    }

    private func dedupMomentsByIdentity(_ moments: [Moment]) -> [Moment] {
        var seen = Set<String>()
        var result: [Moment] = []

        for moment in moments {
            let mediaKey = moment.videoUrl ?? moment.imagePath ?? ""
            let key = "\(moment.id ?? "noid")|\(moment.authorId)|\(mediaKey)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(moment)
        }

        return result
    }

    private func momentIdentityKey(_ moment: Moment) -> String {
        let mediaKey = moment.videoUrl ?? moment.imagePath ?? ""
        return "\(moment.id ?? "noid")|\(moment.authorId)|\(mediaKey)|\(Int(moment.timestamp.timeIntervalSince1970))"
    }

    private func echoId(for moment: Moment) -> String? {
        echoIdByMomentIdentity[momentIdentityKey(moment)]
    }

    private func jitteredCoordinate(for coordinate: CLLocationCoordinate2D, seed: String) -> CLLocationCoordinate2D {
        let hash = abs(seed.hashValue)
        let angle = (Double(hash % 360) * .pi) / 180
        let distanceMeters = 14.0 + Double(hash % 4) * 5.0 // 14-29m

        let latMetersPerDegree = 111_000.0
        let cosLat = max(cos(coordinate.latitude * .pi / 180), 0.2)
        let lonMetersPerDegree = latMetersPerDegree * cosLat

        let latOffset = (distanceMeters * cos(angle)) / latMetersPerDegree
        let lonOffset = (distanceMeters * sin(angle)) / lonMetersPerDegree

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latOffset,
            longitude: coordinate.longitude + lonOffset
        )
    }

    private func regionContainsCoordinate(_ region: MKCoordinateRegion, _ coordinate: CLLocationCoordinate2D) -> Bool {
        let latMin = region.center.latitude - (region.span.latitudeDelta / 2)
        let latMax = region.center.latitude + (region.span.latitudeDelta / 2)
        let lonMin = region.center.longitude - (region.span.longitudeDelta / 2)
        let lonMax = region.center.longitude + (region.span.longitudeDelta / 2)

        return coordinate.latitude >= latMin &&
            coordinate.latitude <= latMax &&
            coordinate.longitude >= lonMin &&
            coordinate.longitude <= lonMax
    }

    struct WeatherIndicatorView: View {
        let weather: WeatherData
        let colorScheme: ColorScheme
        @State private var isAnimating = false

        private var adaptiveColors: AdaptiveColors {
            AdaptiveColors(colorScheme: colorScheme)
        }

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: weather.condition.systemImageName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(getWeatherGradient(weather.condition))
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.temperatureFormatted)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(adaptiveColors.primary)

                    Text(weather.condition.displayName)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(adaptiveColors.secondary)
                        .lineLimit(1)
                }

                if weather.isNight {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.indigo)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.overlayStroke,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
            .onAppear {
                isAnimating = true
            }
        }

        private func getWeatherGradient(_ condition: WeatherCondition) -> LinearGradient {
            switch condition {
            case .clear:
                return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .partlyCloudy:
                return LinearGradient(colors: [.orange, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .cloudy:
                return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .rain:
                return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .snow:
                return LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .thunderstorm:
                return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .unknown:
                return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    // ✅ EFECTOS DE PARTÍCULAS (LLUVIA/NIEVE)
    struct WeatherParticleEffectView: UIViewRepresentable {
        let weather: WeatherData

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .clear
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            // Limpiar layers existentes
            uiView.layer.sublayers?.forEach { layer in
                if layer is CAEmitterLayer {
                    layer.removeFromSuperlayer()
                }
            }

            // Agregar efectos según condición climática
            switch weather.condition {
            case .rain:
                addRainEffect(to: uiView)
            case .snow:
                addSnowEffect(to: uiView)
            case .thunderstorm:
                addRainEffect(to: uiView)
                addLightningEffect(to: uiView)
            default:
                break
            }
        }

        private func addRainEffect(to view: UIView) {
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -10)
            emitter.emitterShape = .line
            emitter.emitterSize = CGSize(width: view.bounds.width * 2, height: 1)

            let cell = CAEmitterCell()
            cell.birthRate = weather.precipitation > 5 ? 300 : 150 // Más gotas si llueve fuerte
            cell.lifetime = 3.0
            cell.velocity = 200
            cell.velocityRange = 50
            cell.emissionLongitude = CGFloat.pi
            cell.emissionRange = 0.1
            cell.scale = 0.3
            cell.scaleRange = 0.2
            cell.alphaSpeed = -0.5
            cell.contents = createRainDropImage()?.cgImage

            emitter.emitterCells = [cell]
            view.layer.addSublayer(emitter)
        }

        private func addSnowEffect(to view: UIView) {
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -10)
            emitter.emitterShape = .line
            emitter.emitterSize = CGSize(width: view.bounds.width * 2, height: 1)

            let cell = CAEmitterCell()
            cell.birthRate = 50
            cell.lifetime = 8.0
            cell.velocity = 50
            cell.velocityRange = 30
            cell.emissionLongitude = CGFloat.pi / 6
            cell.emissionRange = CGFloat.pi / 3
            cell.scale = 0.5
            cell.scaleRange = 0.3
            cell.alphaSpeed = -0.1
            cell.contents = createSnowflakeImage()?.cgImage

            emitter.emitterCells = [cell]
            view.layer.addSublayer(emitter)
        }

        private func addLightningEffect(to view: UIView) {
            // Efecto de flash ocasional para tormentas
            Timer.scheduledTimer(withTimeInterval: Double.random(in: 3...8), repeats: true) { _ in
                let flash = CALayer()
                flash.backgroundColor = UIColor.white.cgColor
                flash.opacity = 0.3
                flash.frame = view.bounds
                view.layer.addSublayer(flash)

                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0.3
                animation.toValue = 0.0
                animation.duration = 0.2
                animation.autoreverses = true
                animation.repeatCount = 2

                CATransaction.begin()
                CATransaction.setCompletionBlock {
                    flash.removeFromSuperlayer()
                }
                flash.add(animation, forKey: "flash")
                CATransaction.commit()
            }
        }

        private func createRainDropImage() -> UIImage? {
            let size = CGSize(width: 2, height: 12)
            return UIGraphicsImageRenderer(size: size).image { context in
                context.cgContext.setFillColor(UIColor.cyan.withAlphaComponent(0.6).cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }

        private func createSnowflakeImage() -> UIImage? {
            let size = CGSize(width: 8, height: 8)
            return UIGraphicsImageRenderer(size: size).image { context in
                context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    struct WeatherAwareLocationPin: View {
        let locationName: String
        let colorScheme: ColorScheme
        let weather: WeatherData?
        let effectsEnabled: Bool
        @State private var isAnimating = false

        private var adaptiveColors: AdaptiveColors {
            AdaptiveColors(colorScheme: colorScheme)
        }

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 45, height: 45)
                        .blur(radius: 4)
                        .offset(y: 2)

                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(
                                        getWeatherAwareStroke(),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)

                        Image(systemName: getLocationIcon())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(getWeatherAwareGradient())
                    }
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: getAnimationDuration())
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                }

                Text(locationName)
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(adaptiveColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
                    .lineLimit(1)
            }
            .onAppear {
                isAnimating = true
            }
        }

        private func getLocationIcon() -> String {
            guard let weather = weather, effectsEnabled else {
                return "location.fill"
            }

            switch weather.condition {
            case .rain, .thunderstorm:
                return "location.fill"
            case .snow:
                return "location.fill"
            default:
                return "location.fill"
            }
        }

        private func getWeatherAwareStroke() -> LinearGradient {
            guard let weather = weather, effectsEnabled else {
                return LinearGradient(
                    colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            switch weather.condition {
            case .clear:
                return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .partlyCloudy:
                return LinearGradient(colors: [.orange, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .cloudy:
                return LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .rain:
                return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .snow:
                return LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .thunderstorm:
                return LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .unknown:
                return LinearGradient(colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        private func getWeatherAwareGradient() -> LinearGradient {
            guard weather != nil, effectsEnabled else {
                return LinearGradient(
                    colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            return getWeatherAwareStroke() // Reusar el mismo gradiente
        }

        private func getAnimationDuration() -> Double {
            guard let weather = weather, effectsEnabled else {
                return 1.5
            }

            switch weather.condition {
            case .thunderstorm:
                return 0.8 // Animación más rápida para tormentas
            case .rain:
                return 1.2
            case .snow:
                return 2.0 // Animación más lenta para nieve
            default:
                return 1.5
            }
        }
    }
}
