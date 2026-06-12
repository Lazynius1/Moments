// ================== TrendingView.swift ==================

import SwiftUI
import FirebaseAuth

struct TrendingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var trendingService = TrendingService.shared
    @State private var trendingContent: TrendingService.PersonalizedTrendingContent?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Namespace private var zoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var zoomTrendingMoment: Moment?
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag = false
    @State private var selectedLocation: String = ""
    @State private var showLocationMap = false
    @Environment(\.colorScheme) var colorScheme
    
    private var TrendingadaptiveColors: TrendingAdaptiveColors {
        TrendingAdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
            // Fondo moderno
            modernBackgroundView
                .ignoresSafeArea(.all)
            
            if isLoading {
                TrendingLoadingView()
            } else if let errorMessage = errorMessage {
                ErrorStateView(message: errorMessage) {
                    loadTrendingContent()
                }
            } else if let content = trendingContent {
                mainContentView(content)
            } else {
                EmptyTrendingView {
                    loadTrendingContent()
                }
            }
            }
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace
                )
            }
            .onChange(of: zoomDestination) { _, newValue in
                if newValue == nil {
                    zoomTrendingMoment = nil
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .momentZoomNavigationSurface(colorScheme: colorScheme)
        .onAppear {
            loadTrendingContent()
        }
        .refreshable {
            await refreshContent()
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: "#\(selectedHashtag)")
        }
        .fullScreenCover(isPresented: $showLocationMap) {
            LocationMapView(
                locationName: selectedLocation,
                coordinate: nil,
                isPresented: $showLocationMap
            )
        }
    }

    private func openTrendingMomentZoom(_ moment: Moment) {
        zoomTrendingMoment = moment
        MomentZoomOpener.open(
            moment: moment,
            moments: [moment],
            initialIndex: 0,
            presentation: .single,
            destination: &zoomDestination,
            zoomIDPrefix: "trending"
        )
    }

    private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
        guard let moment = zoomTrendingMoment else { return [] }
        return MomentZoomOpener.resolvedMoments(for: destination, in: [moment])
    }
    
    // MARK: - Fondo moderno
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
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.02)
        }
    }
    
    // MARK: - Contenido principal
    private func mainContentView(_ content: TrendingService.PersonalizedTrendingContent) -> some View {
        VStack(spacing: 0) {
            // Header compacto
            headerView
            
            // Scroll del contenido
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    // Hero Section - SIN padding top
                    heroSection(content)
                        .padding(.top, 30)
                    
                    // Trending Hashtags
                    TrendingHashtagsSection(
                        hashtags: content.hashtags,
                        onHashtagTap: { hashtag in
                            ExploreHapticFeedback.impact(.medium)
                            selectedHashtag = hashtag
                            showExploreWithHashtag = true
                        }
                    )
                    
                    // Trending Locations
                    TrendingLocationsSection(
                        locations: content.locations,
                        onLocationTap: { location in
                            ExploreHapticFeedback.impact(.medium)
                            selectedLocation = location
                            showLocationMap = true
                        }
                    )
                    
                    // Para Ti (Momentos personalizados)
                    ForYouSection(
                        moments: content.moments,
                        zoomNamespace: zoomNamespace,
                        onMomentTap: { moment in
                            ExploreHapticFeedback.impact(.light)
                            openTrendingMomentZoom(moment)
                        },
                        onHashtagTap: { hashtag in
                            ExploreHapticFeedback.impact(.light)
                            selectedHashtag = hashtag.hasPrefix("#") ? hashtag : "#\(hashtag)"
                            showExploreWithHashtag = true
                        },
                        onSeeAllTap: {
                            // Scroll to trending moments section
                            withAnimation(.easeInOut(duration: 0.8)) {
                                scrollOffset = 800
                            }
                        }
                    )
                    
                    // Trending Moments Grid
                    TrendingMomentsSection(
                        moments: content.moments,
                        zoomNamespace: zoomNamespace,
                        onMomentTap: { moment in
                            ExploreHapticFeedback.impact(.light)
                            openTrendingMomentZoom(moment)
                        }
                    )
                    
                    // Estadísticas finales
                    TrendingStatsView(
                        hashtags: content.hashtags,
                        locations: content.locations,
                        moments: content.moments,
                        lastUpdated: content.lastUpdated
                    )
                    
                    // Espacio final
                    Color.clear.frame(height: 40)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TrendingScrollOffsetKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(TrendingScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
    }
    
    // MARK: - Header compacto
    private var headerView: some View {
        HStack(spacing: 16) {
            // Botón cerrar
            Button(action: {
                ExploreHapticFeedback.impact(.light)
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TrendingadaptiveColors.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(TrendingadaptiveColors.overlayStroke.first?.opacity(0.3) ?? .clear, lineWidth: 1)
                    )
                    .shadow(color: TrendingadaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("🔥")
                        .font(.system(size: 24))
                    
                    Text("trending.title")
                        .font(.custom("Poppins-Bold", size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                Text("trending.subtitle")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(TrendingadaptiveColors.secondary)
            }
            
            Spacer()
            
            // Botón refresh
            Button(action: {
                ExploreHapticFeedback.impact(.medium)
                loadTrendingContent()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.orange)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.orange.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .scaleEffect(isLoading ? 0.9 : 1.0)
            .rotationEffect(.degrees(isLoading ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Hero Section
    private func heroSection(_ content: TrendingService.PersonalizedTrendingContent) -> some View {
        VStack(spacing: 20) {
            // Badge principal
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text("trending.live")
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .tracking(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)
            
            // Estadísticas hero
            HStack(spacing: 24) {
                HeroStatCard(
                    icon: "🔥",
                    number: "\(content.hashtags.count)",
                    label: "Hashtags",
                    color: .orange
                )
                
                HeroStatCard(
                    icon: "📍",
                    number: "\(content.locations.count)",
                    label: "Lugares",
                    color: .blue
                )
                
                HeroStatCard(
                    icon: "🚀",
                    number: "\(content.moments.count)",
                    label: "Momentos",
                    color: .purple
                )
            }
            
            // Descripción
                            Text("trending.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(TrendingadaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: TrendingadaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: TrendingadaptiveColors.shadowColor, radius: 12, x: 0, y: 8)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Funciones
    private func loadTrendingContent() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        errorMessage = nil
        
        trendingService.fetchPersonalizedTrendingContent(for: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let content):
                    trendingContent = content
                    
                case .failure(let error):
                    errorMessage = "Error cargando trending: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func refreshContent() async {
        await withCheckedContinuation { continuation in
            loadTrendingContent()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Hero Stat Card
struct HeroStatCard: View {
    let icon: String
    let number: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    private var TrendingadaptiveColors: TrendingAdaptiveColors {
        TrendingAdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Text(icon)
                    .font(.system(size: 24))
            }
            
            VStack(spacing: 4) {
                Text(number)
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(TrendingadaptiveColors.primary)
                
                Text(label)
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(TrendingadaptiveColors.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Error State View
struct TrendingErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var TrendingadaptiveColors: TrendingAdaptiveColors {
        TrendingAdaptiveColors (colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 12) {
                Text("trending.error.title")
                    .font(.custom("Poppins-SemiBold", size: 22))
                    .foregroundColor(TrendingadaptiveColors.primary)
                
                Text(message)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(TrendingadaptiveColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("trending.error.retry")
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.orange.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 80)
    }
}

// MARK: - Preference Key para scroll
struct TrendingScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - AdaptiveColors
struct TrendingAdaptiveColors {
    let colorScheme: ColorScheme
    
    var primary: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var secondary: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }
    
    var tertiary: Color {
        colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.8)
    }
    
    var accent: Color {
        Color(hex: "007AFF")
    }
    
    var overlayStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.2), Color(hex: "007AFF").opacity(0.3)] :
        [Color.black.opacity(0.1), Color(hex: "007AFF").opacity(0.4)]
    }
    
    var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.1) : .black.opacity(0.15)
    }
}

// MARK: - Preview
struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TrendingView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            TrendingView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
