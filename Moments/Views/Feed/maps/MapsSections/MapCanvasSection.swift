import SwiftUI
import MapKit
import CoreLocation
import Kingfisher

struct MapPlacePin: View {
    let cluster: MapPlaceCluster
    let colorScheme: ColorScheme

    @State private var isPulsing = false

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var extraCount: Int {
        max(0, cluster.totalCount - 1)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Pulso: hay una story de hace menos de 1 h → "está pasando ahora"
            if cluster.hasFreshStory && !MotionPolicy.reduceMotion {
                Circle()
                    .stroke(adaptiveColors.accent.opacity(0.55), lineWidth: 2)
                    .frame(width: 54, height: 54)
                    .scaleEffect(isPulsing ? 1.45 : 1.0)
                    .opacity(isPulsing ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            if let story = cluster.primaryStory {
                MapStoryPin(story: story, colorScheme: colorScheme)
            } else if let moment = cluster.primaryMoment {
                // count: 1 → solo la miniatura; el badge +N lo pone MapPlacePin
                MapMomentPin(moment: moment, colorScheme: colorScheme, count: 1)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "mappin").foregroundStyle(.white))
            }

            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .offset(x: 8, y: -8)
            }
        }
        .onAppear {
            if cluster.hasFreshStory {
                isPulsing = true
            }
        }
    }
}

struct MapMomentPin: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let count: Int

    private var pinSize: CGFloat { count > 1 ? 56 : 48 }
    private var mediaSize: CGFloat { count > 1 ? 40 : 42 }

    var body: some View {
        ZStack {
            if count > 1 {
                stackedPlaceholder(offset: CGSize(width: -7, height: 5), scale: 0.88, opacity: 0.55)
                stackedPlaceholder(offset: CGSize(width: 7, height: -5), scale: 0.88, opacity: 0.7)
            }

            momentThumbnail
                .shadow(color: .black.opacity(0.28), radius: 7, x: 0, y: 3)

            if count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        Text("+\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.78)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .offset(x: 10, y: -10)
                    }
                    Spacer()
                }
                .frame(width: pinSize, height: pinSize)
            }
        }
        .frame(width: pinSize, height: pinSize)
    }

    @ViewBuilder
    private var momentThumbnail: some View {
        if let previewURL, let url = URL(string: previewURL) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: mediaSize, height: mediaSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
        } else {
            Circle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15))
                .frame(width: mediaSize, height: mediaSize)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                )
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
        }
    }

    @ViewBuilder
    private func stackedPlaceholder(offset: CGSize, scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.92))
            .frame(width: mediaSize * scale, height: mediaSize * scale)
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .offset(offset)
            .opacity(opacity)
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
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
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
                        .foregroundStyle(adaptiveColors.accent)

                    Text(NSLocalizedString("maps.gallery.explore", comment: "Explore gallery section title"))
                        .font(.system(size: legacyPoppinsSize(16), weight: .bold))
                        .foregroundStyle(adaptiveColors.primary)
                }

                Spacer()

                if !moments.isEmpty {
                    Button(action: onShowAll) {
                        Text(NSLocalizedString("maps.gallery.seeAll", comment: "See all gallery items"))
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundStyle(adaptiveColors.accent)
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
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                imageLoaded = true
            }
        }
        .scaleEffect(imageLoaded ? 1.0 : 0.95)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: imageLoaded), value: imageLoaded)
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
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingDetail) {
            if let selectedMoment = selectedMoment,
               let selectedIndex = moments.firstIndex(where: { $0.id == selectedMoment.id }) {
                MomentDetailContainerView(
                    context: .map(
                        moments: moments,
                        initialIndex: selectedIndex,
                        locationName: locationName,
                        momentAvailability: .constant([:]),
                        isPresented: $showingDetail
                    )
                )
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 20) {
            Button(action: { isPresented = false }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(locationName)
                    .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)
                    .lineLimit(1)

                Text(String(format: NSLocalizedString("maps.bottomSheet.moments", comment: "Number of moments in location"), moments.count))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(adaptiveColors.accent)
            }

            Spacer()

            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)

                    AttachmentIconView(icon: .share, preset: .shareInline, tintColor: adaptiveColors.primary)
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
                .foregroundStyle(adaptiveColors.tertiary)

            Text(NSLocalizedString("maps.gallery.empty", comment: "Gallery empty state"))
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
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
