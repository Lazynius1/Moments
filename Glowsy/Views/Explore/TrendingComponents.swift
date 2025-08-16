// ================== TrendingComponents.swift ==================

import SwiftUI
import Kingfisher

// MARK: - 🔥 Sección de Trending Hashtags
struct TrendingHashtagsSection: View {
    let hashtags: [TrendingService.TrendingHashtag]
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        if !hashtags.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "🔥 Trending",
                    subtitle: "Hashtags populares ahora"
                )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(hashtags.prefix(10)) { hashtag in
                            TrendingHashtagCard(
                                hashtag: hashtag,
                                onTap: { onHashtagTap(hashtag.hashtag) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 📱 Tarjeta de Hashtag Trending
struct TrendingHashtagCard: View {
    let hashtag: TrendingService.TrendingHashtag
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: categoryGradient.first?.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)
                    
                    VStack(spacing: 2) {
                        Text(hashtag.category.emoji)
                            .font(.system(size: 20))
                        
                        Text("\(hashtag.count)")
                            .font(.custom("Poppins-Bold", size: 12))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(spacing: 2) {
                    Text("#\(hashtag.hashtag)")
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                        
                        Text("+\(Int(hashtag.growth))%")
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .frame(width: 80)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
    
    private var categoryGradient: [Color] {
        switch hashtag.category {
        case .general:
            return [Color(hex: "667eea"), Color(hex: "764ba2")]
        case .food:
            return [Color(hex: "ff9a9e"), Color(hex: "fecfef")]
        case .travel:
            return [Color(hex: "a8edea"), Color(hex: "fed6e3")]
        case .fashion:
            return [Color(hex: "ffecd2"), Color(hex: "fcb69f")]
        case .tech:
            return [Color(hex: "667eea"), Color(hex: "764ba2")]
        case .art:
            return [Color(hex: "ffeef8"), Color(hex: "f093fb")]
        case .lifestyle:
            return [Color(hex: "c3ec52"), Color(hex: "0ba360")]
        }
    }
}

// MARK: - 📍 Sección de Trending Locations
struct TrendingLocationsSection: View {
    let locations: [TrendingService.TrendingLocation]
    let onLocationTap: (String) -> Void
    
    var body: some View {
        if !locations.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "📍 Lugares populares",
                    subtitle: "Donde está pasando todo"
                )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(locations.prefix(8)) { location in
                            TrendingLocationCard(
                                location: location,
                                onTap: { onLocationTap(location.locationName) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 🗺️ Tarjeta de Ubicación Trending
struct TrendingLocationCard: View {
    let location: TrendingService.TrendingLocation
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "a8edea"), Color(hex: "fed6e3")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 4) {
                        Text(location.locationName)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        Text("\(location.momentCount) momentos")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.secondary)
                        
                        Text("\(location.uniqueUsers) usuarios")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 120, height: 140)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
}

// MARK: - 🚀 Sección de Momentos Trending
struct TrendingMomentsSection: View {
    let moments: [TrendingService.TrendingMoment]
    let onMomentTap: (Moment) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]
    
    var body: some View {
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "🚀 Trending ahora",
                    subtitle: "Los momentos más populares"
                )
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(moments.prefix(9)) { trendingMoment in
                        TrendingMomentCard(
                            trendingMoment: trendingMoment,
                            onTap: { onMomentTap(trendingMoment.moment) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 📸 Tarjeta de Momento Trending
struct TrendingMomentCard: View {
    let trendingMoment: TrendingService.TrendingMoment
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                if let imagePath = trendingMoment.moment.imagePath,
                   let url = getImageURL(from: imagePath) {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                                        .scaleEffect(0.8)
                                )
                        }
                        .onFailure { error in
                            print("Error loading trending moment image: \(error)")
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(trendingOverlay)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: "photo.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.6))
                        )
                        .overlay(trendingOverlay)
                }
            }
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
    
    private var trendingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            
            Text("trendingComponents.hot")
                .font(.custom("Poppins-Bold", size: 8))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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
        .shadow(color: .red.opacity(0.4), radius: 4, x: 0, y: 2)
    }
    
    private var engagementIndicator: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8))
                .foregroundColor(.white)
            
            Text("\(Int(trendingMoment.engagementRate))")
                .font(.custom("Poppins-Medium", size: 8))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
    
    private var trendingOverlay: some View {
        VStack {
            HStack {
                Spacer()
                trendingBadge
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            
            Spacer()
            
            // Indicador de engagement en la esquina inferior
            HStack {
                Spacer()
                engagementIndicator
            }
            .padding(.bottom, 8)
            .padding(.trailing, 8)
        }
    }
}

// MARK: - 🎯 Sección "Para Ti" Personalizada
struct ForYouSection: View {
    let moments: [TrendingService.TrendingMoment]
    let onMomentTap: (Moment) -> Void
    let onSeeAllTap: () -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    var body: some View {
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionHeader(
                        title: "🎯 Para ti",
                        subtitle: "Seleccionado especialmente"
                    )
                    
                    Spacer()
                    
                    Button(action: onSeeAllTap) {
                        Text("trendingComponents.seeMore")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(Color(hex: "667eea"))
                    }
                }
                .padding(.horizontal, 16)
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(moments.prefix(6)) { trendingMoment in
                        ForYouMomentCard(
                            trendingMoment: trendingMoment,
                            onTap: { onMomentTap(trendingMoment.moment) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 🎯 Tarjeta Para Ti (Más grande)
struct ForYouMomentCard: View {
    let trendingMoment: TrendingService.TrendingMoment
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                
                if let imagePath = trendingMoment.moment.imagePath,
                   let url = getImageURL(from: imagePath) {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                                )
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(forYouOverlay)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "photo.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.6))
                        )
                        .overlay(forYouOverlay)
                }
            }
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
    
    private var forYouOverlay: some View {
        VStack {
            HStack {
                personalizedBadge
                Spacer()
                scoreIndicator
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Info del momento en la parte inferior
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(trendingMoment.moment.username.prefix(1)).uppercased())
                                .font(.custom("Poppins-Bold", size: 10))
                                .foregroundColor(.black)
                        )
                    
                    Text("@\(trendingMoment.moment.username)")
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    Spacer()
                }
                
                if !trendingMoment.moment.content.isEmpty {
                    Text(trendingMoment.moment.content)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
    
    private var personalizedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            
                Text("trendingComponents.forYou")
                .font(.custom("Poppins-Bold", size: 8))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .shadow(color: Color(hex: "667eea").opacity(0.4), radius: 4, x: 0, y: 2)
    }
    
    private var scoreIndicator: some View {
        Text("\(Int(trendingMoment.trendingScore))")
            .font(.custom("Poppins-Bold", size: 10))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
    }
}

// MARK: - 📊 Vista de Estadísticas de Trending
struct TrendingStatsView: View {
    let hashtags: [TrendingService.TrendingHashtag]
    let locations: [TrendingService.TrendingLocation]
    let moments: [TrendingService.TrendingMoment]
    let lastUpdated: Date
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("trendingComponents.stats")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("trendingComponents.lastUpdated", comment: "Last updated"), timeAgo(from: lastUpdated)))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                StatCard(
                    icon: "🔥",
                    title: NSLocalizedString("trendingStats.hashtags", comment: "Hashtags"),
                    value: "\(hashtags.count)",
                    subtitle: NSLocalizedString("trendingStats.trending", comment: "trending")
                )
                
                StatCard(
                    icon: "📍",
                    title: NSLocalizedString("trendingStats.locations", comment: "Locations"),
                    value: "\(locations.count)",
                    subtitle: NSLocalizedString("trendingStats.popular", comment: "popular")
                )
                
                StatCard(
                    icon: "🚀",
                    title: NSLocalizedString("trendingStats.moments", comment: "Moments"),
                    value: "\(moments.count)",
                    subtitle: NSLocalizedString("trendingStats.featured", comment: "featured")
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 📈 Tarjeta de Estadística
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 24))
            
            Text(value)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.primary)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 🔧 Funciones auxiliares y utilidades
private func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.custom("Poppins-SemiBold", size: 20))
            .foregroundColor(.primary)
        
        Text(subtitle)
            .font(.custom("Poppins-Regular", size: 14))
            .foregroundColor(.secondary)
    }
    .padding(.horizontal, 16)
}

// MARK: - 🎨 Vista de Estado Vacío para Trending
struct EmptyTrendingView: View {
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "667eea").opacity(0.6), Color(hex: "764ba2").opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                VStack(spacing: 4) {
                    Text("🔥")
                        .font(.system(size: 32))
                    
                    Text("trendingComponents.trending")
                        .font(.custom("Poppins-Bold", size: 8))
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 12) {
                Text("trendingComponents.empty.title")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(.primary)
                
                Text("trendingComponents.empty.description")
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button(action: onRefresh) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("trendingComponents.refresh")
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "667eea").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - 🔄 Loading State para Trending
struct TrendingLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                
                Text("🔥")
                    .font(.system(size: 20))
            }
            
            VStack(spacing: 8) {
                Text("trendingComponents.analyzing")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("trendingComponents.discovering")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 60)
        .onAppear {
            isAnimating = true
        }
    }
}
