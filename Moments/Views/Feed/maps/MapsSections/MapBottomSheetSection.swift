import SwiftUI
import AVFoundation
import Kingfisher

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
        .onChange(of: isPresented) { _, presented in
            if presented {
                showBottomSheet()
            } else {
                hideBottomSheet()
            }
        }
        .onChange(of: moments.count) { _, _ in
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
