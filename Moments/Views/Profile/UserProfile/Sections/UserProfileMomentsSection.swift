import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// MARK: - ✅ NUEVO: Thumbnail de momento moderno como ProfileView
struct UserModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme

    // ✅ NUEVOS: Estados para thumbnails de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    var body: some View {
        Button(action: onTap) {
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
                                .fill(UserProfileColors.cardBackground)
                                .frame(width: size, height: size)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(UserProfileColors.textTertiary)
                                )
                                .overlay(ProgressView().tint(UserProfileColors.accent))
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
                        Text(String(format: NSLocalizedString("userProfile.likes.count", comment: "Likes count"), likeCount))
                            .font(.custom("Poppins-Medium", size: 9))
                            .foregroundColor(UserProfileColors.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(UserProfileColors.materialBackground)
                    .clipShape(Capsule())
                    .padding(4)
                }

                // ✅ NUEVO: Indicador de publicación programada (Solo para el autor)
                if moment.isScheduled && moment.authorId == Auth.auth().currentUser?.uid {
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(moment.scheduledRemainingText)
                                    .font(.custom("Poppins-Bold", size: 9))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .shadow(color: UserProfileColors.shadowColor, radius: 4, x: 0, y: 2)
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { isPressed = $0 }, perform: {})
    }

    @ViewBuilder
    private var pinnedBadgeView: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(6)
            .background(Color.black.opacity(colorScheme == .dark ? 0.68 : 0.58))
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
                    .fill(UserProfileColors.cardBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(UserProfileColors.accent)
                                        .scaleEffect(0.8)
                                    Text("userProfile.video.loading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(UserProfileColors.textTertiary)
                                    Text("userProfile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
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
                        .fill(UserProfileColors.cardBackground)
                        .overlay(
                            VStack(spacing: 6) {
                                ProgressView()
                                    .tint(UserProfileColors.accent)
                                    .scaleEffect(0.8)
                                Text("userProfile.image.loading")
                                    .font(.custom("Poppins-Regular", size: 8))
                                    .foregroundColor(UserProfileColors.textSecondary)
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
            .fill(UserProfileColors.cardBackground)
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(UserProfileColors.textTertiary)

                    Text(moment.content.isEmpty ? NSLocalizedString("userProfile.noContent", comment: "No content") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(UserProfileColors.textPrimary)
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

    private func getImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }
}

// MARK: - Función auxiliar para calcular altura del grid (añadir a UserModernPublicProfileView)
func calculateGridHeight(itemCount: Int) -> CGFloat {
    let columns = 3
    let rows = ceil(Double(itemCount) / Double(columns))
    let spacing: CGFloat = 4
    let totalSpacing = spacing * CGFloat(columns - 1) + 16
    let itemWidth = (UIScreen.main.bounds.width - totalSpacing) / 3
    return CGFloat(rows) * itemWidth + (CGFloat(rows - 1) * spacing)
}
