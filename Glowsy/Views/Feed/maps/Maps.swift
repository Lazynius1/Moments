// ================== LocationMapView.swift ==================

import SwiftUI
import MapKit
import CoreLocation
import Kingfisher
import FirebaseAuth
import FirebaseFirestore
import WeatherKit

struct LocationMapView: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D?
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var annotations: [MapsLocationAnnotation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var locationMoments: [Moment] = []  // ✅ USAR MOMENT EN VEZ DE LocationMoment
    @State private var isLoadingMoments = false
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
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            modernBackgroundView
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                modernHeaderView
                
                modernMapView // ✅ Aquí es donde agregamos efectos climáticos
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            
                            LocationBottomSheet(
                    isPresented: $showingBottomSheet,
                    moments: locationMoments,
                    isLoadingMoments: isLoadingMoments,
                    locationName: locationName,
                    colorScheme: colorScheme,
                    onMomentTap: { moment in
                        if let selectedIndex = locationMoments.firstIndex(where: { $0.id == moment.id }) {
                            selectedMoment = moment
                            selectedMomentIndex = selectedIndex
                            showingDetail = true
                        }
                    }
                )
            
            // ✅ NUEVO: INDICADOR DE CLIMA
            if let weather = currentWeather, weatherEffectsEnabled {
                VStack {
                    HStack {
                        Spacer()
                        WeatherIndicatorView(weather: weather, colorScheme: colorScheme)
                            .padding(.trailing, 20)
                            .padding(.top, 100) // Debajo del header
                    }
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🗺️ LocationMapView apareciendo para: \(locationName)")
            checkLocationPermissionsAndSetup()
        }
        .onChange(of: coordinate?.latitude) { _ in
            // ✅ NUEVO: Reaccionar a cambios en las coordenadas usando latitude como trigger
            if let newCoordinate = coordinate, CLLocationCoordinate2DIsValid(newCoordinate) {
                print("📍 Coordenadas actualizadas: \(newCoordinate)")
                setupMapWithCoordinate(newCoordinate)
            }
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            handleLocationPermissionChange(status)
        }
        // ✅ SHEETS SIN CAMBIOS
        .sheet(isPresented: $showingGallery) {
            ModernLocationGalleryView(
                locationName: locationName,
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
                locationName: locationName,
                isPresented: $showingDetail
            )
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
    
    private var modernHeaderView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(action: { isPresented = false }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.buttonStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: adaptiveColors.buttonGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationName)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if !locationMoments.isEmpty {
                            Text("\(locationMoments.count) fotos")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.tertiary)
                        }
                        
                        // ✅ NUEVO: Indicador de distancia si tenemos ubicación actual
                        if let currentLocation = locationManager.currentLocation,
                           let coordinate = coordinate {
                            let distance = LocationUtilities.distance(
                                from: currentLocation.coordinate,
                                to: coordinate
                            )
                            
                            if !locationMoments.isEmpty {
                                Text("•")
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(adaptiveColors.tertiary)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "location.circle.fill")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(adaptiveColors.accent)
                                
                                Text(LocationUtilities.formatDistance(distance))
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(adaptiveColors.secondary)
                            }
                        }
                        

                    }
                }
                
                Spacer()
                
                // ✅ NUEVO: BOTÓN TOGGLE EFECTOS CLIMÁTICOS
                if currentWeather != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            weatherEffectsEnabled.toggle()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: weatherEffectsEnabled ?
                                                [adaptiveColors.accent, adaptiveColors.accent.opacity(0.6)] :
                                                adaptiveColors.buttonStroke,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                            
                            Image(systemName: weatherEffectsEnabled ? "cloud.fill" : "cloud.slash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: weatherEffectsEnabled ?
                                        [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)] :
                                        adaptiveColors.buttonGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                }
                
                Button(action: shareLocation) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.buttonStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                        
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: adaptiveColors.buttonGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: adaptiveColors.overlayStroke,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 0.5),
                alignment: .bottom
            )
            .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
            
            // ✅ NUEVO: Barra de estadísticas si hay momentos
            if !locationMoments.isEmpty {
                HStack(spacing: 20) {
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
                        label: "período",
                        color: .green
                    )
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 0.5),
                    alignment: .bottom
                )
            }
        }
    }
    
    // ✅ NUEVO: Componente de estadística
    private func StatisticItem(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(adaptiveColors.primary)
                
                Text(label)
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(adaptiveColors.tertiary)
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
                    Map(coordinateRegion: $region, annotationItems: annotations) { annotation in
                        MapAnnotation(coordinate: annotation.coordinate) {
                            WeatherAwareLocationPin(
                                locationName: locationName,
                                colorScheme: colorScheme,
                                weather: currentWeather,
                                effectsEnabled: weatherEffectsEnabled
                            )
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
                    Text("Cargando ubicación")
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
                    Text("No se pudo cargar la ubicación")
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
                            
                            Text("Reintentar")
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
                            Text("Configurar permisos")
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
    
    // MARK: - Funciones de permisos y setup
    func checkLocationPermissionsAndSetup() {
        print("🔍 Verificando permisos de ubicación...")
        print("📍 Estado actual: \(LocationUtilities.getLocationPermissionStatus())")
        
        let currentStatus = CLLocationManager.authorizationStatus()
        
        switch currentStatus {
        case .notDetermined:
            print("⚠️ Permisos no determinados, solicitando...")
            locationManager.requestLocationPermission()
        case .denied, .restricted:
            print("❌ Permisos denegados, procediendo sin verificación de ubicación")
            locationPermissionGranted = false
            setupMapLocation()
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Permisos concedidos")
            locationPermissionGranted = true
            setupMapLocation()
        @unknown default:
            print("⚠️ Estado de permisos desconocido")
            setupMapLocation()
        }
    }
    
    func handleLocationPermissionChange(_ status: CLAuthorizationStatus) {
        print("📍 Cambio en permisos de ubicación: \(status)")
        
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
        print("🗺️ Iniciando setup del mapa para: \(locationName)")
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // ✅ MEJORADO: Verificar que las coordenadas sean válidas
        if let coord = coordinate {
            print("🔍 Debug - coordinate recibido: lat: \(coord.latitude), lon: \(coord.longitude)")
        } else {
            print("🔍 Debug - coordinate recibido: nil")
        }
        print("🔍 Debug - locationName: \(locationName)")
        
        if let coordinate = coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            print("✅ Usando coordenadas proporcionadas: \(coordinate)")
            setupMapWithCoordinate(coordinate)
        } else {
            print("🔍 Coordenadas no disponibles o inválidas, geocodificando ubicación: \(locationName)")
            geocodeLocation()
        }
    }
    
    func geocodeLocation() {
        print("🔍 Iniciando geocoding para: \(locationName)")
        let geocoder = CLGeocoder()
        
        // ✅ MEJORADO: Agregar contexto para mejorar la precisión
        var searchQuery = locationName
        
        // ✅ MEJORADO: Agregar contexto de ciudad para ubicaciones famosas
        if locationName.lowercased().contains("sagrada familia") {
            searchQuery = "Sagrada Familia, Barcelona, Spain"
        } else if locationName.lowercased().contains("park güell") {
            searchQuery = "Park Güell, Barcelona, Spain"
        } else if locationName.lowercased().contains("casa batlló") {
            searchQuery = "Casa Batlló, Barcelona, Spain"
        } else if locationName.lowercased().contains("la pedrera") {
            searchQuery = "La Pedrera, Barcelona, Spain"
        }
        
        print("🔍 Búsqueda mejorada: \(searchQuery)")
        
        // ✅ MEJORADO: Agregar timeout y mejor manejo de errores
        geocoder.geocodeAddressString(searchQuery) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error en geocoding: \(error.localizedDescription)")
                    
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
                            print("⚠️ Usando ubicación por defecto debido a error de geocoding")
                            self.setupDefaultLocation()
                            return
                        }
                    } else {
                        // ✅ MEJORADO: Para errores generales, mostrar ubicación por defecto
                        print("⚠️ Usando ubicación por defecto debido a error general")
                        self.setupDefaultLocation()
                        return
                    }
                    
                    self.isLoading = false
                    return
                }
                
                guard let placemarks = placemarks, !placemarks.isEmpty else {
                    print("❌ No se encontraron placemarks para: \(searchQuery)")
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
                    
                    // ✅ Priorizar resultados en España para ubicaciones españolas
                    if searchQuery.lowercased().contains("barcelona") || 
                       searchQuery.lowercased().contains("spain") ||
                       searchQuery.lowercased().contains("sagrada familia") {
                        return placemark.isoCountryCode == "ES"
                    }
                    
                    return true
                }
                
                guard let bestPlacemark = validPlacemarks.first, let location = bestPlacemark.location else {
                    print("❌ No se encontraron placemarks válidos para: \(searchQuery)")
                    self.errorMessage = "Ubicación inválida"
                    self.isLoading = false
                    return
                }
                
                // ✅ MEJORADO: Verificar que las coordenadas sean válidas
                guard CLLocationCoordinate2DIsValid(location.coordinate) else {
                    print("❌ Coordenadas geocodificadas inválidas: \(location.coordinate)")
                    self.errorMessage = "Coordenadas de ubicación inválidas"
                    self.isLoading = false
                    return
                }
                
                print("✅ Geocoding exitoso para '\(self.locationName)':")
                print("  - Coordenadas: \(location.coordinate)")
                print("  - País: \(bestPlacemark.country ?? "N/A")")
                print("  - Ciudad: \(bestPlacemark.locality ?? "N/A")")
                print("  - Dirección: \(bestPlacemark.thoroughfare ?? "N/A")")
                self.setupMapWithCoordinate(location.coordinate)
            }
        }
    }
    
    func setupMapWithCoordinate(_ coordinate: CLLocationCoordinate2D) {
        print("🗺️ Configurando mapa con coordenadas: \(coordinate)")
        
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            print("❌ Coordenadas inválidas: \(coordinate)")
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
            
            self.isLoading = false
            self.errorMessage = nil
            
            print("✅ Mapa configurado exitosamente para: \(self.locationName)")
            
            // ✅ CARGAR MOMENTOS Y CLIMA EN PARALELO
            self.loadLocationMoments()
            self.loadWeatherData(for: coordinate)
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Configurar ubicación por defecto cuando falla el geocoding
    private func setupDefaultLocation() {
        print("🗺️ Configurando ubicación por defecto para: \(locationName)")
        
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
            self.errorMessage = "Mostrando ubicación por defecto. '\(self.locationName)' no se pudo encontrar."
            
            print("✅ Ubicación por defecto configurada para: \(self.locationName)")
            
            // ✅ CARGAR MOMENTOS Y CLIMA DE LA UBICACIÓN POR DEFECTO
            self.loadLocationMoments()
            self.loadWeatherData(for: defaultCoordinate)
        }
    }
    
    func loadWeatherData(for coordinate: CLLocationCoordinate2D) {
        print("🌤️ Cargando datos climáticos para: \(coordinate)")
        
        Task {
            do {
                let weather = try await weatherService.getWeather(for: coordinate)
                
                DispatchQueue.main.async {
                    self.currentWeather = weather
                    print("✅ Clima cargado: \(weather.condition.displayName), \(weather.temperatureFormatted)")
                }
                
            } catch {
                print("⚠️ No se pudo cargar el clima: \(error.localizedDescription)")
                // No mostrar error al usuario, los efectos simplemente no aparecerán
            }
        }
    }
    
    func loadLocationMoments() {
        print("📸 Cargando momentos para: \(locationName)")
        
        DispatchQueue.main.async {
            self.isLoadingMoments = true
        }
        
        // ✅ USAR TU SERVICIO EXISTENTE DE MOMENTOS EN VEZ DE CREAR UNO NUEVO
        LocationSearchService.shared.searchMomentsByLocation(
            locationName: locationName,
            currentUserId: Auth.auth().currentUser?.uid
        ) { moments in
            DispatchQueue.main.async {
                self.locationMoments = moments
                self.isLoadingMoments = false
                
                // ✅ AGREGAR ESTA LÍNEA:
                if !moments.isEmpty {
                    self.showingBottomSheet = true
                }
                
                print("📸 Cargados \(moments.count) momentos")
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
                Text("Fotos en este lugar")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                if !moments.isEmpty {
                    Button(action: onShowAll) {
                        HStack(spacing: 4) {
                            Text("Ver todas")
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(adaptiveColors.accent)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(adaptiveColors.accent)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if isLoading {
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .frame(width: 70, height: 70)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .tint(adaptiveColors.accent)
                                    .scaleEffect(0.7)
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
                .padding(.bottom, 12)
            }
        }
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
        .shadow(color: adaptiveColors.shadowColor, radius: 12, x: 0, y: 8)
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
        // ✅ USAR moment.imagePath EN VEZ DE moment.imageUrl
        AsyncImage(url: URL(string: moment.imagePath ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        imageLoaded = true
                    }
                }
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
            
            VStack(spacing: 0) {
                HStack {
                    Button("Cerrar") {
                        isPresented = false
                    }
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(adaptiveColors.accent)
                    
                    Spacer()
                    
                    Text(locationName)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(adaptiveColors.accent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                .shadow(color: adaptiveColors.shadowColor, radius: 8, x: 0, y: 4)
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(moments) { moment in
                            Button(action: {
                                selectedMoment = moment
                                showingDetail = true
                            }) {
                                // ✅ USAR moment.imagePath EN VEZ DE moment.imageUrl
                                KFImage(URL(string: moment.imagePath ?? ""))
                                    .placeholder {
                                        Rectangle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle())
                                                    .tint(adaptiveColors.accent)
                                                    .scaleEffect(0.7)
                                            )
                                    }
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .opacity(showingDetail ? 0.0 : 1.0)
                                    .animation(.easeIn(duration: 0.2), value: showingDetail)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingDetail) {
            if let selectedMoment = selectedMoment,
               let selectedIndex = moments.firstIndex(where: { $0.id == selectedMoment.id }) {
                LocationMomentDetailView(
                    locationMoments: moments,
                    initialIndex: selectedIndex,  // ✅ Usar selectedIndex calculado
                    locationName: locationName,
                    isPresented: $showingDetail
                )
            }
        }
    }
}

// ✅ SERVICIO LOCATIONSEARCHSERVICE REFACTORIZADO PARA DEVOLVER MOMENT

class LocationSearchService {
    static let shared = LocationSearchService()
    private let db = Firestore.firestore()
    private let privacyService = PrivacyService()
    
    private init() {}
    
    func searchMomentsByLocation(
        locationName: String,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        print("🔍 [LocationSearch] Buscando momentos para: '\(locationName)'")
        
        db.collectionGroup("moments")
            .whereField("location", isEqualTo: locationName)
            .whereField("audience", isEqualTo: "everyone")
            .limit(to: 20)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ [LocationSearch] Error: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("📭 [LocationSearch] No hay documentos")
                    completion([])
                    return
                }
                
                print("📄 [LocationSearch] Documentos encontrados: \(documents.count)")
                
                let group = DispatchGroup()
                var moments: [Moment] = []
                let syncQueue = DispatchQueue(label: "location.moments.sync")
                
                for document in documents {
                    group.enter()
                    do {
                        var moment = try document.data(as: Moment.self)
                        moment.id = document.documentID
                        
                        // ✅ Verificar que tenga imagen y username
                        guard let imagePath = moment.imagePath, !imagePath.isEmpty,
                              !moment.username.isEmpty else {
                            print("⚠️ [LocationSearch] Momento incompleto: \(document.documentID)")
                            group.leave()
                            continue
                        }
                        
                        // Verificar privacidad si hay usuario actual
                        if let currentUserId = currentUserId {
                            self?.privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                                if canView {
                                    syncQueue.async {
                                        moments.append(moment)
                                    }
                                } else {
                                    print("🔒 [LocationSearch] Momento filtrado por privacidad: \(document.documentID)")
                                }
                                group.leave()
                            }
                        } else {
                            // Sin usuario, agregar directamente
                            syncQueue.async {
                                moments.append(moment)
                            }
                            group.leave()
                        }
                    } catch {
                        print("❌ [LocationSearch] Error parseando momento: \(error)")
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    let sortedMoments = moments.sorted { $0.timestamp > $1.timestamp }
                    print("✅ [LocationSearch] Momentos finales: \(sortedMoments.count)")
                    completion(sortedMoments)
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
        print("📍 [LocationUtilities] Solicitando permisos de ubicación")
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("❌ [LocationUtilities] Permisos de ubicación denegados")
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 [LocationUtilities] Cambio de autorización: \(status.rawValue)")
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("❌ [LocationUtilities] Permisos denegados")
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        
        print("📍 [LocationUtilities] Ubicación actualizada: \(location.coordinate)")
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [LocationUtilities] Error de ubicación: \(error.localizedDescription)")
    }
    
    static func getCoordinates(for locationName: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        print("🔍 [LocationUtilities] Geocoding: \(locationName)")
        
        let authStatus = CLLocationManager.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            print("❌ [LocationUtilities] Permisos de ubicación denegados para geocoding")
            completion(nil)
            return
        }
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationName) { placemarks, error in
            if let error = error {
                let clError = error as? CLError
                switch clError?.code {
                case .locationUnknown:
                    print("❌ [LocationUtilities] Ubicación desconocida")
                case .denied:
                    print("❌ [LocationUtilities] Geocoding denegado - permisos insuficientes")
                case .network:
                    print("❌ [LocationUtilities] Error de red en geocoding")
                case .geocodeFoundNoResult:
                    print("❌ [LocationUtilities] No se encontraron resultados para: \(locationName)")
                case .geocodeCanceled:
                    print("❌ [LocationUtilities] Geocoding cancelado")
                default:
                    print("❌ [LocationUtilities] Error geocoding: \(error.localizedDescription)")
                }
                completion(nil)
                return
            }
            
            if let placemark = placemarks?.first,
               let location = placemark.location {
                print("✅ [LocationUtilities] Geocoding exitoso: \(location.coordinate)")
                completion(location.coordinate)
            } else {
                print("❌ [LocationUtilities] No se encontraron coordenadas para: \(locationName)")
                completion(nil)
            }
        }
    }
    
    static func getLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        print("🔍 [LocationUtilities] Reverse geocoding: \(coordinate)")
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("❌ [LocationUtilities] Error reverse geocoding: \(error.localizedDescription)")
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
                print("✅ [LocationUtilities] Reverse geocoding exitoso: \(finalName)")
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

// ✅ BOTTOM SHEET MODERNO ESTILO INSTAGRAM CON GLASSMORPHISM

struct LocationBottomSheet: View {
    @Binding var isPresented: Bool
    let moments: [Moment]
    let isLoadingMoments: Bool
    let locationName: String
    let colorScheme: ColorScheme
    let onMomentTap: (Moment) -> Void
    
    @State private var offset: CGFloat = 300
    @State private var isDragging = false
    @State private var viewMode: ViewMode = .gallery
    
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
                // ✅ FONDO CON GLASSMORPHISM
                if isPresented {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            hideBottomSheet()
                        }
                        .animation(.easeInOut(duration: 0.3), value: isPresented)
                }
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 0) {
                        // ✅ HANDLE PARA ARRASTRAR
                        dragHandle
                        
                        // ✅ HEADER DEL BOTTOM SHEET
                        bottomSheetHeader
                        
                        // ✅ CONTENIDO
                        bottomSheetContent
                            .frame(maxHeight: geometry.size.height * 0.6)
                    }
                    .frame(maxHeight: min(geometry.size.height * 0.8, geometry.size.height - 100))
                    .background(glassmorphicBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: adaptiveColors.shadowColor, radius: 20, x: 0, y: -8)
                    .offset(y: offset)
                    .gesture(dragGesture)
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
    
    // ✅ FONDO GLASSMORPHIC
    private var glassmorphicBackground: some View {
        ZStack {
            // Fondo base glassmorphic
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "1a1a2e").opacity(0.95),
                        Color(hex: "16213e").opacity(0.92),
                        Color.black.opacity(0.88)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.95),
                        Color(hex: "f8f9fa").opacity(0.92),
                        Color(hex: "e9ecef").opacity(0.88)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Overlay glassmorphic
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.2 : 0.4)
        }
    }
    
    // ✅ HANDLE DRAG
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(adaptiveColors.tertiary.opacity(0.6))
            .frame(width: 40, height: 6)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
    
    // ✅ HEADER CON GLASSMORPHISM
    private var bottomSheetHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(locationName)
                        .font(.custom("Poppins-SemiBold", size: 20))
                        .foregroundColor(adaptiveColors.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        Text("\(moments.count) \(moments.count == 1 ? "foto" : "fotos")")
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
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
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
            .padding(.bottom, 16)
            
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
    
    // ✅ CONTENIDO PRINCIPAL
    private var bottomSheetContent: some View {
        ScrollView {
            if isLoadingMoments {
                loadingView
            } else if moments.isEmpty {
                emptyView
            } else {
                VStack(spacing: 0) {
                    if viewMode == .gallery {
                        galleryView
                    } else {
                        listView
                    }
                }
                .padding(.top, 16)
            }
        }
        .scrollIndicators(.hidden)
    }
    
    // ✅ VISTA DE GALERÍA CON GLASSMORPHISM
    private var galleryView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
            ForEach(moments) { moment in
                Button(action: { onMomentTap(moment) }) {
                    AsyncImage(url: URL(string: moment.imagePath ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .aspectRatio(1, contentMode: .fill)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .tint(adaptiveColors.accent)
                                    .scaleEffect(0.6)
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
    }
    
    // ✅ VISTA DE LISTA CON GLASSMORPHISM
    private var listView: some View {
        LazyVStack(spacing: 12) {
            ForEach(moments) { moment in
                LocationMomentRow(
                    moment: moment,
                    colorScheme: colorScheme,
                    onTap: onMomentTap
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // ✅ LOADING CON GLASSMORPHISM
    private var loadingView: some View {
        VStack(spacing: 24) {
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
                    .scaleEffect(1.2)
            }
            
            VStack(spacing: 8) {
                Text("Cargando momentos...")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(adaptiveColors.primary)
                
                Text("Filtrando por privacidad")
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
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
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
                Text("No hay fotos en este lugar")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                
                Text("Sé el primero en compartir un momento aquí")
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
                isDragging = true
                let newOffset = max(0, value.translation.height)
                offset = newOffset
            }
            .onEnded { value in
                isDragging = false
                let velocity = value.predictedEndTranslation.height
                
                if velocity > 200 || offset > 150 {
                    hideBottomSheet()
                } else {
                    showBottomSheet()
                }
            }
    }
    
    // ✅ FUNCIONES DE ANIMACIÓN
    private func showBottomSheet() {
        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8)) {
            offset = 0
        }
    }
    
    private func hideBottomSheet() {
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.9)) {
            offset = 300
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
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

// ✅ ROW PARA VISTA DE LISTA CON GLASSMORPHISM
struct LocationMomentRow: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let onTap: (Moment) -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: { onTap(moment) }) {
            HStack(spacing: 12) {
                // ✅ IMAGEN CON GLASSMORPHISM
                AsyncImage(url: URL(string: moment.imagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                        .overlay(
                            ProgressView()
                                .tint(adaptiveColors.accent)
                                .scaleEffect(0.7)
                        )
                }
                
                // ✅ INFO DEL MOMENTO
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(moment.username)")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(adaptiveColors.primary)
                    
                    if !moment.content.isEmpty {
                        Text(moment.content)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(formatTimeAgo(moment.timestamp))
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(adaptiveColors.tertiary)
                }
                
                Spacer()
                
                // ✅ INDICADOR DE AUDIENCIA
                audienceIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
            .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var audienceIndicator: some View {
        Image(systemName: getAudienceIcon(moment.audience ?? "everyone"))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(getAudienceColor(moment.audience ?? "everyone"))
    }
    
    private func getAudienceIcon(_ audience: String) -> String {
        switch audience {
        case "everyone": return "globe"
        case "connections": return "person.2"
        case "bestFriends": return "heart"
        case "custom", "customList": return "person.3"
        default: return "globe"
        }
    }
    
    private func getAudienceColor(_ audience: String) -> Color {
        switch audience {
        case "everyone": return .green
        case "connections": return .blue
        case "bestFriends": return .pink
        case "custom", "customList": return .orange
        default: return adaptiveColors.secondary
        }
    }
    
    private func formatTimeAgo(_ timestamp: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
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
