import SwiftUI
import AVFoundation
import Kingfisher

struct LocationBottomSheet: View {
    let moments: [Moment]
    let momentAvailability: [String: Bool]
    let isLoadingMoments: Bool
    let locationName: String
    let colorScheme: ColorScheme
    let onMomentTap: (Moment) -> Void

    @State private var viewMode: ViewMode = .gallery

    private let gridSpacing: CGFloat = 1
    private let gridColumns = 3

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

    private var uniqueContributors: [Moment] {
        var seen = Set<String>()
        return moments.filter { moment in
            guard !seen.contains(moment.authorId) else { return false }
            seen.insert(moment.authorId)
            return true
        }
    }

    private var statsText: String {
        String(
            format: NSLocalizedString("maps.bottomSheet.stats", comment: "Moments and contributor count"),
            moments.count,
            uniqueContributors.count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            bottomSheetHeader
            bottomSheetContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ✅ HEADER CON GLASSMORPHISM
    private var bottomSheetHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 40, height: 40)
                            .momentsChromeGlass(in: Circle(), interactive: false)

                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [adaptiveColors.accent, adaptiveColors.accent.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    Text(locationName)
                        .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                        .foregroundStyle(adaptiveColors.primary)
                        .lineLimit(1)

                    Spacer()

                    if !moments.isEmpty {
                        viewModeToggle
                    }
                }

                HStack(spacing: 10) {
                    Text(statsText)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(adaptiveColors.secondary)
                        .lineLimit(1)

                    Spacer()

                    if !uniqueContributors.isEmpty {
                        contributorAvatarStack
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

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

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = mode
                    }
                }) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(viewMode == mode ? .white : adaptiveColors.tertiary)
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
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var contributorAvatarStack: some View {
        HStack(spacing: -10) {
            ForEach(Array(uniqueContributors.prefix(3)), id: \.authorId) { moment in
                StoryRingAvatarView(
                    userId: moment.authorId,
                    size: 30,
                    lineWidth: 1.5
                )
                .overlay(
                    Circle()
                        .stroke(adaptiveColors.background.opacity(0.9), lineWidth: 2)
                )
            }

            if uniqueContributors.count > 3 {
                Text("+\(uniqueContributors.count - 3)")
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.clear)
                            .momentsChromeGlass(in: Circle(), interactive: false)
                    )
                    .overlay(
                        Circle()
                            .stroke(adaptiveColors.background.opacity(0.9), lineWidth: 2)
                    )
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
            }
        }
    }

    // ✅ VISTA DE GALERÍA (grid compacto tipo perfil, fondo glass conservado)
    private var galleryView: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: gridColumns),
            spacing: gridSpacing
        ) {
            ForEach(moments) { moment in
                let isAvailable = momentAvailability[moment.mapAvailabilityKey] ?? true
                Button(action: { onMomentTap(moment) }) {
                    MapBottomSheetGridCell(
                        moment: moment,
                        colorScheme: colorScheme,
                        isAvailable: isAvailable
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
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
                    .momentsChromeGlass(in: Circle())
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)

                Text(NSLocalizedString("maps.bottomSheet.loading.filtering", comment: "Filtering by privacy message"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(adaptiveColors.secondary)
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
                    .momentsChromeGlass(in: Circle())
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
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)

                Text(NSLocalizedString("maps.bottomSheet.empty.subtitle", comment: "Be the first to share a moment here"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(adaptiveColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(height: 300)
    }
}

struct MapLocationSystemSheetModifier: ViewModifier {
    @Binding var selectedDetent: PresentationDetent

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationBackground(.clear)
    }
}

extension View {
    func mapLocationSystemSheet(detent: Binding<PresentationDetent>) -> some View {
        modifier(MapLocationSystemSheetModifier(selectedDetent: detent))
    }
}

struct MapBottomSheetGridCell: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let isAvailable: Bool

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var hasMultipleMedia: Bool {
        (moment.mediaItems?.count ?? 0) > 1
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

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

                if hasMultipleMedia {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "square.on.square")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .blur(radius: isAvailable ? 0 : 14)
            .overlay {
                if !isAvailable {
                    MomentUnavailableOverlay(compact: true, cornerRadius: 0)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            // ✅ DURACIÓN DEL VIDEO (si está disponible)
            if let duration = moment.videoDuration {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatVideoDuration(duration))
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundStyle(.white)
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
                    HStack(spacing: 8) {
                        StoryRingAvatarView(
                            userId: moment.authorId,
                            size: 32,
                            lineWidth: 2.2
                        )
                            .shadow(radius: 2)

                        VStack(alignment: .leading, spacing: 0) {
                            LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username, prefix: "@")
                                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)

                            Text(formatTimeAgo(moment.timestamp))
                                .font(.system(size: legacyPoppinsSize(10)))
                                .foregroundStyle(.white.opacity(0.8))
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
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(adaptiveColors.primary.opacity(0.9))
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
                size: CGSize(width: UIApplication.shared.activeWindowSize.width - 40, height: 180),
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
        MomentsFormat.relativeTime(from: timestamp)
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
                    .foregroundStyle(.white.opacity(0.9))

                Text(NSLocalizedString("echo.viewer.unavailable", comment: ""))
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundStyle(.white)
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
