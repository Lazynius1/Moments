import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

// MARK: - Thumbnail de momento moderno (OPTIMIZADO)
struct ModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let customListNamesById: [String: String]
    let onTap: (() -> Void)? // ✅ MANTENER: Callback opcional
    var onLongPress: (() -> Void)? = nil
    var isInteractionEnabled: Bool = true
    @State private var isPressed = false

    // ✅ NUEVOS: Estados para thumbnails de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    private struct AudienceBadgeStyle {
        let icon: String
        let title: String
        let background: Color
    }

    private var normalizedAudience: String {
        moment.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? "everyone"
    }

    private var audienceBadgeStyle: AudienceBadgeStyle {
        switch normalizedAudience {
        case "bestfriends", "bestfriend":
            return AudienceBadgeStyle(
                icon: "heart.fill",
                title: NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type"),
                background: Color(hex: "24C26A").opacity(0.92)
            )
        case "connections", "connection", "mutuals", "mutual":
            return AudienceBadgeStyle(
                icon: "person.2.fill",
                title: NSLocalizedString("audience.type.connections", comment: "Connections audience type"),
                background: Color(hex: "00B4D8").opacity(0.92)
            )
        case "customlist":
            let listName = moment.customListId.flatMap { customListNamesById[$0] }
            let resolvedName = (listName?.isEmpty == false)
                ? (listName ?? "")
                : NSLocalizedString("audience.type.customList", comment: "Custom list audience type")
            return AudienceBadgeStyle(
                icon: "list.bullet.rectangle",
                title: resolvedName,
                background: Color(hex: "A855F7").opacity(0.92)
            )
        case "custom":
            return AudienceBadgeStyle(
                icon: "person.crop.circle.badge.plus",
                title: NSLocalizedString("audience.type.custom", comment: "Custom audience type"),
                background: Color(hex: "F59E0B").opacity(0.92)
            )
        case "onlyme":
            return AudienceBadgeStyle(
                icon: "lock.fill",
                title: NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type"),
                background: Color.black.opacity(0.78)
            )
        default:
            return AudienceBadgeStyle(
                icon: "globe",
                title: NSLocalizedString("audience.type.everyone", comment: "Everyone audience type"),
                background: Color(hex: "0EA5A3").opacity(0.9)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
                // ✅ NUEVO: Lógica actualizada para manejar videos y imágenes
                if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
                    // Es un momento nuevo con mediaItems
                    if mediaItem.type == .video {
                        // ✅ NUEVO: Priorizar thumbnailUrl si existe
                        if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                            imageView(imageURL: thumbnailUrl)
                        } else {
                            // Si no hay thumbnail URL (legacy), generar uno
                            videoThumbnailView(videoURL: mediaItem.url)
                        }
                    } else {
                        // ✅ NUEVO: Mostrar imagen desde mediaItems
                        imageView(imageURL: mediaItem.url)
                    }
                } else if let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) {
                    // ✅ MANTENER: Fallback para momentos legacy con imagePath
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(.gray.opacity(0.6))
                                )
                                .overlay(ProgressView().tint(Color(hex: "007AFF")))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(borderOverlay())
                        .clipped()
                } else {
                    // ✅ MANTENER: Placeholder para sin contenido
                    emptyContentView()
                }

                // ✅ NUEVO: Badge de audiencia en esquina superior izquierda
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            audienceBadgeView

                            // Indicador de publicación programada (solo autor)
                            if moment.isScheduled && moment.authorId == Auth.auth().currentUser?.uid {
                                scheduledBadgeView
                            }
                        }
                        Spacer()
                    }
                    Spacer()
                }

                // ✅ NUEVO: Indicador de video
                if let mediaItem = moment.primaryVisibleMediaItem, mediaItem.type == .video {
                    VStack {
                        HStack {
                            Spacer()
                            if moment.isPinned == true {
                                pinnedBadgeView
                                    .padding(6)
                            }
                        }
                        Spacer()
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding(6)
                            Spacer()
                        }
                    }
                } else if moment.isPinned == true {
                    VStack {
                        HStack {
                            Spacer()
                            pinnedBadgeView
                                .padding(6)
                        }
                        Spacer()
                    }
                }

                // ✅ MANTENER: Contador de likes
                // ✅ NUEVO: El autor siempre ve el contador, los demás solo si no está oculto
                if let likeCount = moment.reactions["heart"]?.count, likeCount > 0,
                   (moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts) {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 9))
                        Text("\(likeCount)")
                            .font(.custom("Poppins-Medium", size: 9))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(4)
                }
            }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isPressed)
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .overlay {
            if isInteractionEnabled, onTap != nil || onLongPress != nil {
                ProfileMomentThumbnailGestureOverlay(
                    onTap: { onTap?() },
                    onLongPress: onLongPress,
                    onPressingChanged: { isPressed = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var audienceBadgeView: some View {
        let style = audienceBadgeStyle
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            Text(style.title)
                .font(.custom("Poppins-SemiBold", size: 8))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(style.background)
        .clipShape(Capsule())
        .padding(6)
    }

    @ViewBuilder
    private var scheduledBadgeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .bold))
            Text(moment.scheduledRemainingText)
                .font(.custom("Poppins-Bold", size: 8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.72))
        .clipShape(Capsule())
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var pinnedBadgeView: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(6)
            .background(Color.black.opacity(0.68))
            .clipShape(Circle())
    }

    // ✅ NUEVA: Vista para thumbnails de video
    @ViewBuilder
    private func videoThumbnailView(videoURL: String) -> some View {
        ZStack {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(borderOverlay())
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(Color(hex: "007AFF"))
                                        .scaleEffect(0.8)
                                    Text("profile.video.uploading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray.opacity(0.6))
                                    Text("profile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    )
                    .overlay(borderOverlay())
            }
        }
        .onAppear {
            loadVideoThumbnail(from: videoURL)
        }
    }

    // ✅ NUEVA: Vista para imágenes desde mediaItems
    @ViewBuilder
    private func imageView(imageURL: String) -> some View {
        if let url = getImageURL(from: imageURL) {
            KFImage(url)
                .placeholder {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            VStack(spacing: 6) {
                                ProgressView()
                                    .tint(Color(hex: "007AFF"))
                                    .scaleEffect(0.8)
                                Text("profile.image.uploading")
                                    .font(.custom("Poppins-Regular", size: 8))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        )
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .overlay(borderOverlay())
                .clipped()
        } else {
            emptyContentView()
        }
    }

    // ✅ NUEVA: Vista para contenido vacío
    @ViewBuilder
    private func emptyContentView() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(.gray.opacity(0.6))

                    Text(moment.content.isEmpty ? NSLocalizedString("profile.content.empty", comment: "No content text") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 3)
                }
            )
            .overlay(borderOverlay())
    }

    // ✅ NUEVA: Overlay de borde reutilizable
    @ViewBuilder
    private func borderOverlay() -> some View {
        EmptyView()
    }

    // ✅ NUEVA: Función para cargar thumbnail de video
    private func loadVideoThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        isLoadingVideoThumbnail = true

        Task {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2) // Retina

            do {
                let (cgImage, _) = try await imageGenerator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
                let uiImage = UIImage(cgImage: cgImage)

                await MainActor.run {
                    self.videoThumbnail = uiImage
                    self.isLoadingVideoThumbnail = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingVideoThumbnail = false
                }
            }
        }
    }

    // ✅ MANTENER: Función existente
    private func getImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }

    init(
        moment: Moment,
        size: CGFloat,
        customListNamesById: [String: String] = [:],
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        isInteractionEnabled: Bool = true
    ) {
        self.moment = moment
        self.size = size
        self.customListNamesById = customListNamesById
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.isInteractionEnabled = isInteractionEnabled
    }
}


// MARK: - Estado vacío para momentos
struct ProfileSectionEmptyState: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ProfileColors.textPrimary.opacity(0.05))
                    .frame(width: 54, height: 54)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(ProfileColors.textSecondary.opacity(0.7))
            }

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.custom("Poppins-SemiBold", size: 17))
                    .foregroundColor(ProfileColors.textPrimary)

                Text(subtitleKey)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Estado vacío para momentos
struct ModernEmptyMomentsView: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "camera",
            titleKey: "profile.moments.empty.title",
            subtitleKey: "profile.moments.empty.subtitle"
        )
    }
}

// MARK: - ✅ NUEVO: Placeholder para Guardados
struct ProfileSavedPlaceholder: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "bookmark",
            titleKey: LocalizedStringKey("profile.saved.empty.title"),
            subtitleKey: LocalizedStringKey("profile.saved.empty.subtitle")
        )
    }
}
