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
            momentAvailability[moment.mapAvailabilityKey] ?? true
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
        .onChange(of: coordinate?.latitude) { _ in
            // ✅ NUEVO: Reaccionar a cambios en las coordenadas usando latitude como trigger
            if let newCoordinate = coordinate, CLLocationCoordinate2DIsValid(newCoordinate), !hasInitializedMap {
                setupMapWithCoordinate(newCoordinate)
            }
        }
        .onChange(of: region.center.latitude) { _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.center.longitude) { _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.span.latitudeDelta) { _ in
            handleMapRegionChanged()
        }
        .onChange(of: region.span.longitudeDelta) { _ in
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
        .onChange(of: showingDetail) { _ in
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
                        label: "fotos",
                        color: adaptiveColors.accent
                    )
                    
                    StatisticItem(
                        icon: "person.2.fill",
                        value: "\(Set(locationMoments.map { $0.authorId }).count)",
                        label: "usuarios",
                        color: .blue
                    )
                    
                    StatisticItem(
                        icon: "calendar",
                        value: formatDateRange(),
                        label: "tiempo",
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
                    Map(coordinateRegion: $region, annotationItems: mapCombinedAnnotations) { annotation in
                        MapAnnotation(coordinate: annotation.coordinate) {
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
                    .mapStyle(getMapStyle())
                    
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
        let currentStatus = CLLocationManager.authorizationStatus()
        
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
                            self.errorMessage = "No se pudo encontrar '\(self.locationName)'. Intenta con un nombre más específico."
                        case .denied:
                            self.errorMessage = "Acceso a ubicación denegado"
                        case .network:
                            self.errorMessage = "Error de conexión. Verifica tu internet"
                        case .geocodeFoundNoResult:
                            self.errorMessage = "No se encontraron resultados para '\(self.locationName)'. Intenta con un nombre más específico."
                        case .geocodeCanceled:
                            self.errorMessage = "Búsqueda cancelada"
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
                    self.errorMessage = "No se encontraron resultados para '\(self.locationName)'"
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
                    self.errorMessage = "No se pudo obtener la ubicación de '\(self.locationName)'"
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
                self.errorMessage = "Coordenadas de ubicación inválidas"
                self.isLoading = false
            }
            return
        }
        
        // ✅ MEJORADO: Usar DispatchQueue.main.async para asegurar que se ejecute en el hilo principal
        DispatchQueue.main.async {
            // ✅ MEJORADO: Configurar región con animación suave
            withAnimation(.easeInOut(duration: 0.5)) {
                self.region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
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
                self.region = MKCoordinateRegion(
                    center: defaultCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            
            // ✅ Limpiar anotaciones y agregar anotación por defecto
            self.annotations.removeAll()
            self.annotations.append(MapsLocationAnnotation(
                id: UUID(),
                coordinate: defaultCoordinate,
                title: "Ubicación por defecto"
            ))
            
            self.isLoading = false
            self.errorMessage = showMessage
                ? "Mostrando ubicación por defecto. '\(self.locationName)' no se pudo encontrar."
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
            momentAvailability[moment.mapAvailabilityKey] ?? true
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
        guard let userId = resolvedUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
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
                    
                    let locationFiltered = echoes.filter { self.echoMatchesCurrentLocation($0) }
                    var allEchoMoments: [Moment] = []
                    var mapping: [String: String] = [:]
                    
                    for echo in locationFiltered {
                        let builtMoments = self.buildMomentsFromEcho(echo)
                        allEchoMoments.append(contentsOf: builtMoments)
                        
                        if let echoId = echo.id, !echoId.isEmpty {
                            for moment in builtMoments {
                                mapping[self.momentIdentityKey(moment)] = echoId
                            }
                        }
                    }
                    let deduped = self.dedupMomentsByIdentity(allEchoMoments).sorted { $0.timestamp > $1.timestamp }
                    
                    self.echoIdByMomentIdentity = mapping
                    self.echoHistoryMoments = deduped
                    self.locationMoments = deduped
                    self.refreshMomentAvailability(for: deduped)
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
            result[moment.mapAvailabilityKey] = true
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
            setMomentAvailability(true, key: key, token: token)
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

                let audience = (liveMoment.audience ?? moment.audience ?? "everyone").lowercased()
                switch audience {
                case "everyone", "connections":
                    self.setMomentAvailability(true, key: key, token: token)

                case "bestfriends":
                    self.privacyService.checkIfBestFriend(userId: moment.authorId, friendId: viewerId) { isBestFriend in
                        self.setMomentAvailability(isBestFriend, key: key, token: token)
                    }

                case "custom", "customlist":
                    self.privacyService.canUserViewMomentEnhanced(liveMoment, viewerId: viewerId) { canView in
                        self.setMomentAvailability(canView, key: key, token: token)
                    }

                case "onlyme":
                    self.setMomentAvailability(false, key: key, token: token)

                default:
                    self.setMomentAvailability(true, key: key, token: token)
                }
            }
    }

    private func setMomentAvailability(_ value: Bool, key: String, token: UUID) {
        DispatchQueue.main.async {
            guard self.availabilityValidationToken == token else { return }
            self.momentAvailability[key] = value
        }
    }
    
    private func buildMomentsFromEcho(_ echo: Echo) -> [Moment] {
        let coordinate = Moment.LocationCoordinate(latitude: echo.location.latitude, longitude: echo.location.longitude)
        let resolvedLocation = echo.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationValue = (resolvedLocation?.isEmpty == false) ? resolvedLocation : locationName
        
        return echo.moments.compactMap { ref in
            let mediaType = ref.mediaType.lowercased()
            let imagePath = mediaType == "video" ? nil : ref.mediaUrl
            let videoUrl = mediaType == "video" ? ref.mediaUrl : nil
            
            return Moment(
                id: ref.momentId,
                authorId: ref.authorId,
                username: ref.username,
                content: "",
                imagePath: imagePath,
                videoUrl: videoUrl,
                timestamp: ref.timestamp,
                reactions: [:],
                commentCount: 0,
                profileImagePath: nil,
                taggedUsers: nil,
                location: locationValue,
                locationCoordinate: coordinate,
                audience: ref.audience,
                mediaItems: nil,
                aspectRatio: ref.aspectRatio,
                customListId: ref.customListId,
                thumbnailUrl: ref.thumbnailUrl,
                videoDuration: nil,
                videoFileSize: nil,
                videoResolution: nil,
                disableComments: false,
                hideLikeCounts: false,
                allowSharing: false,
                scheduledDate: nil,
                trendingScore: nil,
                engagementRate: nil,
                isArchived: false,
                archivedAt: nil
            )
        }
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
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            
            let context = UIGraphicsGetCurrentContext()
            context?.setFillColor(UIColor.cyan.withAlphaComponent(0.6).cgColor)
            context?.fill(CGRect(origin: .zero, size: size))
            
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return image
        }
        
        private func createSnowflakeImage() -> UIImage? {
            let size = CGSize(width: 8, height: 8)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            
            let context = UIGraphicsGetCurrentContext()
            context?.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            context?.fillEllipse(in: CGRect(origin: .zero, size: size))
            
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return image
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
            guard let weather = weather, effectsEnabled else {
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

// ================== MapsLocationAnnotation ==================

struct MapsLocationAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
}

private extension Moment {
    var mapAvailabilityKey: String {
        if let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return "\(authorId)|\(Int(timestamp.timeIntervalSince1970))|\(content)"
    }

    var mapHasVideoMedia: Bool {
        if let mediaItems, mediaItems.contains(where: { $0.type == .video }) {
            return true
        }
        if let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty {
            return true
        }
        return false
    }
    
    var mapHasRenderableMedia: Bool {
        if let mediaItems, mediaItems.contains(where: { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        
        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return true
        }
        
        if let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty {
            return true
        }
        
        return false
    }
    
    var mapPreferredImageURL: String? {
        if let mediaItems {
            if let firstImage = mediaItems.first(where: { $0.type == .image }) {
                let imageURL = firstImage.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !imageURL.isEmpty { return imageURL }
            }
            
            if let firstVideo = mediaItems.first(where: { $0.type == .video }) {
                if let thumb = firstVideo.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
                    return thumb
                }
                let fallback = firstVideo.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallback.isEmpty { return fallback }
            }
        }
        
        if let thumbnailUrl = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }
        
        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }
        
        return nil
    }
    
    var mapPreferredVideoThumbnailURL: String? {
        if let mediaItems, let firstVideo = mediaItems.first(where: { $0.type == .video }) {
            if let thumb = firstVideo.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
                return thumb
            }
            let fallback = firstVideo.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty { return fallback }
        }
        
        if let thumbnailUrl = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }
        
        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }
        
        return nil
    }
}

struct CombinedMapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let locationTitle: String?
    let moment: Moment?
    let moments: [Moment]

    var primaryMoment: Moment? {
        moment ?? moments.first
    }

    var count: Int {
        if !moments.isEmpty { return moments.count }
        return moment == nil ? 0 : 1
    }
}

struct MapMomentPin: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let count: Int

    private var pinSize: CGFloat { count > 1 ? 58 : 50 }
    private var mediaSize: CGFloat { pinSize - 6 }
    
    var body: some View {
        ZStack {
            if let previewURL, let url = URL(string: previewURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: mediaSize, height: mediaSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
            } else {
                Circle()
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15))
                    .frame(width: mediaSize, height: mediaSize)
                    .overlay(
                        ZStack {
                            Image(systemName: "photo")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        }
                    )
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
            }

            if count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Text("+\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .offset(x: 8, y: -8)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var previewURL: String? {
        moment.mapPreferredImageURL ?? moment.mapPreferredVideoThumbnailURL
    }
}

// ✅ PIN MODERNO CON TU ESTILO
struct ModernLocationPin: View {
    let locationName: String
    let colorScheme: ColorScheme
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
                                    LinearGradient(
                                        colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                        .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    .easeInOut(duration: 1.5)
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
}

// ✅ GALERÍA MODERNA USANDO MOMENT EN VEZ DE LocationMoment
struct ModernLocationGallery: View {
    let moments: [Moment]  // ✅ CAMBIO AQUÍ
    let isLoading: Bool
    let colorScheme: ColorScheme
    let onMomentTap: (Moment) -> Void  // ✅ CAMBIO AQUÍ
    let onShowAll: () -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(adaptiveColors.accent)
                    
                    Text("Explorar galería")
                        .font(.custom("Poppins-Bold", size: 16))
                        .foregroundColor(adaptiveColors.primary)
                }
                
                Spacer()
                
                if !moments.isEmpty {
                    Button(action: onShowAll) {
                        Text("Ver todas")
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(adaptiveColors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(adaptiveColors.accent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            
            if isLoading {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .frame(width: 85, height: 110)
                            .overlay(ProgressView().tint(adaptiveColors.accent))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            } else if !moments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(moments.prefix(8).enumerated()), id: \.offset) { index, moment in
                            Button(action: { onMomentTap(moment) }) {
                                ModernLocationPhotoCard(moment: moment, colorScheme: colorScheme)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
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
        .shadow(color: adaptiveColors.shadowColor.opacity(0.1), radius: 15, x: 0, y: 10)
        .padding(.horizontal, 16)
    }
}

// ✅ TARJETA DE FOTO USANDO MOMENT
struct ModernLocationPhotoCard: View {
    let moment: Moment  // ✅ CAMBIO AQUÍ
    let colorScheme: ColorScheme
    @State private var imageLoaded = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            if moment.mapHasVideoMedia {
                MapsVideoThumbnailView(
                    moment: moment,
                    size: CGSize(width: 90, height: 120),
                    cornerRadius: 14,
                    colorScheme: colorScheme
                )
            } else {
                AsyncImage(url: URL(string: moment.mapPreferredImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 70, height: 70)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(adaptiveColors.accent)
                                .scaleEffect(0.7)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: adaptiveColors.overlayStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            }
        }
        .onAppear {
            guard !imageLoaded else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                imageLoaded = true
            }
        }
        .scaleEffect(imageLoaded ? 1.0 : 0.95)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: imageLoaded)
    }
}

// ✅ GALERÍA COMPLETA USANDO MOMENT
struct ModernLocationGalleryView: View {
    let locationName: String
    let moments: [Moment]  // ✅ CAMBIO AQUÍ
    let colorScheme: ColorScheme
    @Binding var isPresented: Bool
    @State private var selectedMoment: Moment?  // ✅ CAMBIO AQUÍ
    @State private var showingDetail = false
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 3)
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            // Fondo Base Premium
            adaptiveColors.background.ignoresSafeArea()
            
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color.black, Color(hex: "0A0A0A")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Header Refinado
                headerView
                
                if moments.isEmpty {
                    emptyStateView
                } else {
                    galleryGrid
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingDetail) {
            if let selectedMoment = selectedMoment,
               let selectedIndex = moments.firstIndex(where: { $0.id == selectedMoment.id }) {
                LocationMomentDetailView(
                    locationMoments: moments,
                    initialIndex: selectedIndex,
                    locationName: locationName,
                    isPresented: $showingDetail
                )
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 20) {
            Button(action: { isPresented = false }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(adaptiveColors.primary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(locationName)
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                    .lineLimit(1)
                
                Text("\(moments.count) Momentos")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(adaptiveColors.accent)
            }
            
            Spacer()
            
            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(adaptiveColors.primary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(adaptiveColors.overlayStroke[0])
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(adaptiveColors.tertiary)
            
            Text("No hay fotos aún")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(adaptiveColors.primary)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(moments) { moment in
                    Button(action: {
                        selectedMoment = moment
                        showingDetail = true
                    }) {
                        Group {
                            if moment.mapHasVideoMedia {
                                MapsVideoThumbnailView(
                                    moment: moment,
                                    size: CGSize(width: 120, height: 120),
                                    cornerRadius: 0,
                                    colorScheme: colorScheme
                                )
                            } else {
                                KFImage(URL(string: moment.mapPreferredImageURL ?? ""))
                                    .placeholder {
                                        Rectangle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(ProgressView().tint(adaptiveColors.accent))
                                    }
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipped()
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 2)
        }
    }
}

// ✅ SERVICIO LOCATIONSEARCHSERVICE REFACTORIZADO PARA DEVOLVER MOMENT

class LocationSearchService {
    static let shared = LocationSearchService()
    private let db = Firestore.firestore()
    private let privacyService = PrivacyService()
    private let functionsRegion = "europe-southwest1"
    
    private init() {}
    
    private struct BackendMapMomentsResponse: Codable {
        let moments: [BackendMoment]
        let source: String?
        let totalCandidates: Int?
    }
    
    private enum MapQueryMode {
        case location(String)
        case region(MKCoordinateRegion)
    }
    
    func searchMomentsByLocation(
        locationName: String,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        guard currentUserId != nil else {
            searchMomentsByLocationLegacy(
                locationName: locationName,
                currentUserId: currentUserId,
                completion: completion
            )
            return
        }
        
        fetchMapMomentsFromBackend(mode: .location(locationName), limit: 400) { [weak self] backendMoments in // ✅ Aumentado límite para no perder posts antiguos
            if let backendMoments {
                completion(backendMoments)
                return
            }
            
            self?.searchMomentsByLocationLegacy(
                locationName: locationName,
                currentUserId: currentUserId,
                completion: completion
            )
        }
    }
    
    func searchMomentsInRegion(
        region: MKCoordinateRegion,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        guard currentUserId != nil else {
            searchMomentsInRegionLegacy(
                region: region,
                currentUserId: currentUserId,
                completion: completion
            )
            return
        }
        
        fetchMapMomentsFromBackend(mode: .region(region), limit: 400) { [weak self] backendMoments in // ✅ Aumentado límite para no perder posts antiguos
            if let backendMoments {
                completion(backendMoments)
                return
            }
            
            self?.searchMomentsInRegionLegacy(
                region: region,
                currentUserId: currentUserId,
                completion: completion
            )
        }
    }
    
    private func fetchMapMomentsFromBackend(
        mode: MapQueryMode,
        limit: Int,
        completion: @escaping ([Moment]?) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }
        
        Task {
            do {
                let idToken = try await user.getIDToken()
                guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                guard let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/getMapMomentsPage") else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                var body: [String: Any] = ["limit": limit]
                switch mode {
                case .location(let locationName):
                    body["mode"] = "location"
                    body["locationName"] = locationName
                case .region(let region):
                    body["mode"] = "region"
                    body["centerLatitude"] = region.center.latitude
                    body["centerLongitude"] = region.center.longitude
                    body["latitudeDelta"] = region.span.latitudeDelta
                    body["longitudeDelta"] = region.span.longitudeDelta
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 15
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                let decoded = try JSONDecoder().decode(BackendMapMomentsResponse.self, from: data)
                let moments = decoded.moments
                    .map { $0.toMoment() }
                    .filter { $0.isArchived != true }
                    .sorted { $0.timestamp > $1.timestamp }
                
                await MainActor.run { completion(moments) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }
    
    private func searchMomentsByLocationLegacy(
        locationName: String,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        let now = Date()
        
        db.collectionGroup("moments")
            .whereField("location", isEqualTo: locationName)
            .whereField("audience", isEqualTo: "everyone")
            .limit(to: 400) // ✅ Limite super alto para pillar posts antiguos sin saturar la RAM
            .getDocuments { [weak self] snapshot, error in
                if let _ = error {
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let group = DispatchGroup()
                var moments: [Moment] = []
                let syncQueue = DispatchQueue(label: "location.moments.sync")
                
                for document in documents {
                    group.enter()
                    do {
                        var moment = try document.data(as: Moment.self)
                        moment.id = document.documentID
                        
                        guard moment.isArchived != true else {
                            group.leave()
                            continue
                        }
                        
                        let isAuthor = (currentUserId == moment.authorId)
                        if !isAuthor,
                           let scheduledDate = moment.scheduledDate,
                           scheduledDate > now {
                            group.leave()
                            continue
                        }
                        
                        guard moment.mapHasRenderableMedia,
                              !moment.username.isEmpty else {
                            group.leave()
                            continue
                        }
                        
                        if let currentUserId = currentUserId {
                            self?.privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                                if canView {
                                    syncQueue.async {
                                        moments.append(moment)
                                    }
                                }
                                group.leave()
                            }
                        } else {
                            syncQueue.async {
                                moments.append(moment)
                            }
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    completion(moments.sorted { $0.timestamp > $1.timestamp })
                }
            }
    }
    
    private func searchMomentsInRegionLegacy(
        region: MKCoordinateRegion,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        let now = Date()
        let latitudeMin = max(-90.0, region.center.latitude - (region.span.latitudeDelta / 2.0))
        let latitudeMax = min(90.0, region.center.latitude + (region.span.latitudeDelta / 2.0))
        let longitudeMin = max(-180.0, region.center.longitude - (region.span.longitudeDelta / 2.0))
        let longitudeMax = min(180.0, region.center.longitude + (region.span.longitudeDelta / 2.0))
        
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("locationCoordinate.latitude", isGreaterThanOrEqualTo: latitudeMin)
            .whereField("locationCoordinate.latitude", isLessThanOrEqualTo: latitudeMax)
            .order(by: "locationCoordinate.latitude")
            .limit(to: 400) // ✅ Limite super alto para pillar posts antiguos sin saturar la RAM
            .getDocuments { [weak self] snapshot, error in
                if let _ = error {
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                let group = DispatchGroup()
                var moments: [Moment] = []
                let syncQueue = DispatchQueue(label: "location.region.moments.sync")
                
                for document in documents {
                    group.enter()
                    do {
                        var moment = try document.data(as: Moment.self)
                        moment.id = document.documentID
                        
                        guard moment.isArchived != true else {
                            group.leave()
                            continue
                        }
                        
                        let isAuthor = (currentUserId == moment.authorId)
                        if !isAuthor,
                           let scheduledDate = moment.scheduledDate,
                           scheduledDate > now {
                            group.leave()
                            continue
                        }
                        
                        guard moment.mapHasRenderableMedia,
                              !moment.username.isEmpty else {
                            group.leave()
                            continue
                        }
                        
                        guard let coordinate = moment.locationCoordinate else {
                            group.leave()
                            continue
                        }
                        
                        guard coordinate.longitude >= longitudeMin, coordinate.longitude <= longitudeMax else {
                            group.leave()
                            continue
                        }
                        
                        if let currentUserId = currentUserId {
                            self?.privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                                if canView {
                                    syncQueue.async {
                                        moments.append(moment)
                                    }
                                }
                                group.leave()
                            }
                        } else {
                            syncQueue.async {
                                moments.append(moment)
                            }
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    completion(moments.sorted { $0.timestamp > $1.timestamp })
                }
            }
    }
}

// ✅ CLASE LOCATIONUTILITIES (SIN CAMBIOS - YA ESTÁ BIEN)
class LocationUtilities: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = LocationUtilities()
    private let locationManager = CLLocationManager()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = CLLocationManager.authorizationStatus()
    }
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Permisos denegados
            break
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            // Permisos denegados
            break
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Error de ubicación
    }
    
    static func getCoordinates(for locationName: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let authStatus = CLLocationManager.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            completion(nil)
            return
        }
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationName) { placemarks, error in
            if let error = error {
                completion(nil)
                return
            }
            
            if let placemark = placemarks?.first,
               let location = placemark.location {
                completion(location.coordinate)
            } else {
                completion(nil)
            }
        }
    }
    
    static func getLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                completion(nil)
                return
            }
            
            if let placemark = placemarks?.first {
                var locationComponents: [String] = []
                
                if let name = placemark.name {
                    locationComponents.append(name)
                } else if let locality = placemark.locality {
                    locationComponents.append(locality)
                }
                
                if let administrativeArea = placemark.administrativeArea {
                    locationComponents.append(administrativeArea)
                }
                
                if let country = placemark.country {
                    locationComponents.append(country)
                }
                
                let locationName = locationComponents.joined(separator: ", ")
                let finalName = locationName.isEmpty ? "Ubicación desconocida" : locationName
                completion(finalName)
            } else {
                completion("Ubicación desconocida")
            }
        }
    }
    
    func getCurrentLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                completion(self.currentLocation?.coordinate)
            }
            
        case .notDetermined:
            requestLocationPermission()
            completion(nil)
            
        default:
            completion(nil)
        }
    }
    
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    static func formatDistance(_ distanceInMeters: Double) -> String {
        if distanceInMeters < 1000 {
            return String(format: "%.0f m", distanceInMeters)
        } else {
            let kilometers = distanceInMeters / 1000
            return String(format: "%.1f km", kilometers)
        }
    }
    
    static func getLocationPermissionStatus() -> String {
        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            return "No determinado"
        case .restricted:
            return "Restringido"
        case .denied:
            return "Denegado"
        case .authorizedAlways:
            return "Autorizado siempre"
        case .authorizedWhenInUse:
            return "Autorizado en uso"
        @unknown default:
            return "Desconocido"
        }
    }
}

struct LocationBottomSheet: View {
    @Binding var isPresented: Bool
    let moments: [Moment]
    let momentAvailability: [String: Bool]
    let isLoadingMoments: Bool
    let locationName: String
    let colorScheme: ColorScheme
    let onMomentTap: (Moment) -> Void
    
    @State private var offset: CGFloat = UIScreen.main.bounds.height
    @State private var viewMode: ViewMode = .gallery
    @State private var dragStartOffset: CGFloat = 0
    
    private let sheetLargeOffset: CGFloat = 0
    private let sheetMediumOffset: CGFloat = 170
    private let sheetHiddenOffset: CGFloat = UIScreen.main.bounds.height + 60
    
    enum ViewMode: String, CaseIterable {
        case gallery = "gallery"
        case list = "list"
        
        var icon: String {
            switch self {
            case .gallery: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Eliminamos el fondo oscuro para permitir navegación en el mapa
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        dragHandle
                        bottomSheetHeader
                        bottomSheetContent
                    }
                    .background(glassmorphicBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: adaptiveColors.shadowColor, radius: 20, x: 0, y: -8)
                    .offset(y: offset)
                    // Eliminamos el frames fijos aquí para que el contenido mande si es poco
                    .frame(maxHeight: min(geometry.size.height * 0.8, geometry.size.height - 100), alignment: .bottom)
                }
            }
        }
        .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.8), value: offset)
        .onAppear {
            if isPresented {
                showBottomSheet()
            }
        }
        .onChange(of: isPresented) { presented in
            if presented {
                showBottomSheet()
            } else {
                hideBottomSheet()
            }
        }
        .onChange(of: moments.count) { _ in
            if isPresented && offset > 50 {
                showBottomSheet()
            }
        }
    }
    
    // ✅ FONDO GLASSMORPHIC MEJORADO (Transpariencia máxima)
    private var glassmorphicBackground: some View {
        ZStack {
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: adaptiveColors.overlayStroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
    }
    
    // ✅ HANDLE DRAG
    private var dragHandle: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        adaptiveColors.tertiary.opacity(0.42),
                        adaptiveColors.tertiary.opacity(0.26)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 42, height: 5)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.22), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 6, x: 0, y: 2)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .gesture(dragGesture)
    }
    
    // ✅ HEADER CON GLASSMORPHISM
    private var bottomSheetHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(locationName)
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(String(format: NSLocalizedString("maps.bottomSheet.moments", comment: "Number of moments in location"), moments.count))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(adaptiveColors.secondary)
                        

                    }
                }
                
                Spacer()
                
                // ✅ TOGGLE VIEW MODE CON GLASSMORPHISM
                if !moments.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewMode = mode
                                }
                            }) {
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
                                                LinearGradient(
                                                    colors: [Color.clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .animation(.easeInOut(duration: 0.2), value: viewMode)
                            }
                        }
                    }
                    .padding(4)
                    .background(
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            // ✅ SEPARADOR GLASSMORPHIC
            if !moments.isEmpty && !isLoadingMoments {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: adaptiveColors.overlayStroke,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // ✅ CONTENIDO PRINCIPAL ADAPTATIVO
    private var bottomSheetContent: some View {
        Group {
            if isLoadingMoments {
                loadingView
                    .padding(.top, 16)
                    .padding(.bottom, 30)
            } else if moments.isEmpty {
                emptyView
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if viewMode == .gallery {
                            galleryView
                        } else {
                            modernListView
                        }
                    }
                    .id("\(viewMode.rawValue)-\(moments.count)")
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(viewMode == .gallery && moments.count <= 3)
                .frame(maxHeight: viewMode == .list ? UIScreen.main.bounds.height * 0.68 : (moments.count <= 3 ? 320 : 500))
            }
        }
    }
    
    // ✅ VISTA DE GALERÍA MEJORADA (Grid estilo Explorer)
    private var galleryView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(moments) { moment in
                let isAvailable = momentAvailability[moment.mapAvailabilityKey] ?? true
                Button(action: { onMomentTap(moment) }) {
                    GeometryReader { geometry in
                        ZStack {
                            // Fondo material por si la imagen tarda o es pequeña
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            
                            // ✅ DETECTAR SI ES VIDEO O IMAGEN
                            if moment.mapHasVideoMedia {
                                MapsVideoThumbnailView(
                                    moment: moment,
                                    size: CGSize(width: geometry.size.width, height: geometry.size.width),
                                    cornerRadius: 0,
                                    colorScheme: colorScheme
                                )
                            } else {
                                KFImage(URL(string: moment.mapPreferredImageURL ?? ""))
                                    .placeholder {
                                        ProgressView()
                                            .tint(adaptiveColors.accent)
                                            .scaleEffect(0.6)
                                    }
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.width)
                                    .clipped()
                            }
                        }
                        .blur(radius: isAvailable ? 0 : 14)
                        .overlay {
                            if !isAvailable {
                                MomentUnavailableOverlay(compact: true, cornerRadius: 4)
                            }
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(PlainButtonStyle())
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // ✅ VISTA DE LISTA MODERNA (Estilo Feed)
    private var modernListView: some View {
        LazyVStack(spacing: 16) {
            ForEach(moments) { moment in
                ModernLocationMomentRow(
                    moment: moment,
                    colorScheme: colorScheme,
                    isAvailable: momentAvailability[moment.mapAvailabilityKey] ?? true,
                    onTap: onMomentTap
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // ✅ LOADING CON GLASSMORPHISM
    private var loadingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Color.clear
                    .frame(width: 80, height: 80)
                    .liquidGlass(in: Circle())
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
                    .scaleEffect(1.2)
            }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("maps.bottomSheet.loading.moments", comment: "Loading moments message"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(adaptiveColors.primary)
                
                Text(NSLocalizedString("maps.bottomSheet.loading.filtering", comment: "Filtering by privacy message"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(adaptiveColors.secondary)
            }
        }
        .frame(height: 250)
    }
    
    // ✅ EMPTY STATE CON GLASSMORPHISM
    private var emptyView: some View {
        VStack(spacing: 20) {
            ZStack {
                Color.clear
                    .frame(width: 100, height: 100)
                    .liquidGlass(in: Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.overlayStroke,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
                
                Image(systemName: "camera.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("maps.bottomSheet.empty.title", comment: "No moments in this location"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                
                Text(NSLocalizedString("maps.bottomSheet.empty.subtitle", comment: "Be the first to share a moment here"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(adaptiveColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(height: 300)
    }

    // ✅ GESTOS Y ANIMACIONES
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if abs(value.translation.height) < 0.5 {
                    dragStartOffset = offset
                }
                let proposed = dragStartOffset + value.translation.height
                offset = min(max(proposed, sheetLargeOffset), sheetHiddenOffset)
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height

                if velocity > 280 || offset > 240 {
                    hideBottomSheet()
                } else if velocity < -180 || offset < 85 {
                    snapToLarge()
                } else {
                    snapToMedium()
                }
            }
    }

    // ✅ FUNCIONES DE ANIMACIÓN
    private func showBottomSheet() {
        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8)) {
            offset = sheetMediumOffset
        }
    }

    private func hideBottomSheet() {
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.9)) {
            offset = sheetHiddenOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }

    private func snapToMedium() {
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.85)) {
            offset = sheetMediumOffset
        }
    }

    private func snapToLarge() {
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.85)) {
            offset = sheetLargeOffset
        }
    }
    
    // ✅ HELPER PARA COLORES DEL CLIMA
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
}

// ✅ COMPONENTE PARA THUMBNAIL DE VIDEO
struct MapsVideoThumbnailView: View {
    let moment: Moment
    let size: CGSize
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            // ✅ THUMBNAIL DEL VIDEO
            AsyncImage(url: URL(string: moment.mapPreferredVideoThumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ProgressView()
                            .tint(adaptiveColors.accent)
                            .scaleEffect(0.6)
                    )
            }
            
            // ✅ OVERLAY OSCURO PARA ICONO
            Rectangle()
                .fill(.black.opacity(0.3))
                .frame(width: size.width, height: size.height)
            
            // ✅ ICONO DE PLAY
            Image(systemName: "play.circle.fill")
                .font(.system(size: size.width * 0.3))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            
            // ✅ DURACIÓN DEL VIDEO (si está disponible)
            if let duration = moment.videoDuration {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatVideoDuration(duration))
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.black.opacity(0.7))
                            )
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    // ✅ FORMATO DE DURACIÓN
    private func formatVideoDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// ✅ ROW PARA VISTA DE LISTA CON GLASSMORPHISM
// ✅ COMPONENTE DE FILA MODERNA (Inspirado en ModernPostCardView)
struct ModernLocationMomentRow: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let isAvailable: Bool
    let onTap: (Moment) -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: { onTap(moment) }) {
            VStack(alignment: .leading, spacing: 0) {
                // Background con blur y gradiente sutil
                ZStack(alignment: .bottomLeading) {
                    // Contenido visual (Video o Imagen)
                    mediaPreview
                    
                    // Overlay inferior para mejor lectura de info
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    
                    // Info sutil sobre la imagen
                    HStack(spacing: 10) {
                        StoryRingAvatarView(
                            userId: moment.authorId,
                            size: 32,
                            lineWidth: 2.2
                        )
                            .shadow(radius: 2)
                        
                        VStack(alignment: .leading, spacing: 0) {
                            LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username, prefix: "@")
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                            
                            Text(formatTimeAgo(moment.timestamp))
                                .font(.custom("Poppins-Regular", size: 10))
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(radius: 1)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                
                // Texto si existe
                if !moment.content.isEmpty {
                    Text(moment.content)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(adaptiveColors.primary.opacity(0.9))
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .blur(radius: isAvailable ? 0 : 16)
            .overlay {
                if !isAvailable {
                    MomentUnavailableOverlay(compact: false, cornerRadius: 18)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
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
            .shadow(color: adaptiveColors.shadowColor.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var mediaPreview: some View {
        if moment.mapHasVideoMedia {
            MapsVideoThumbnailView(
                moment: moment,
                size: CGSize(width: UIScreen.main.bounds.width - 40, height: 180),
                cornerRadius: 18,
                colorScheme: colorScheme
            )
        } else {
            AsyncImage(url: URL(string: moment.mapPreferredImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } placeholder: {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(ProgressView().tint(adaptiveColors.accent))
            }
        }
    }
    
    private func formatTimeAgo(_ timestamp: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

struct MomentUnavailableOverlay: View {
    let compact: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: compact ? 6 : 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: compact ? 18 : 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Text(NSLocalizedString("echo.viewer.unavailable", comment: ""))
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : nil)
                    .padding(.horizontal, compact ? 8 : 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// ✅ EXTENSIÓN PARA ESQUINAS ESPECÍFICAS
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
