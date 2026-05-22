import SwiftUI
import Kingfisher
import AVFoundation

struct ProfileSavedContent: View {
    @ObservedObject var viewModel: SavedMomentsViewModel
    @State private var showingSavedMomentDetail = false
    @State private var selectedSavedMomentIndex = 0
    @State private var showingSavedManager = false
    @State private var selectedFilter: SavedQuickFilter = .all
    @State private var detailMoments: [Moment] = []
    @Environment(\.colorScheme) var colorScheme
    @State private var showingRestrictedRemoveAlert = false
    @State private var restrictedMomentToRemove: Moment?

    enum SavedQuickFilter: CaseIterable {
        case all
        case videos
        case text
        case location

        var title: String {
            switch self {
            case .all:
                return NSLocalizedString("profile.saved.filter.all", comment: "All saved filter")
            case .videos:
                return NSLocalizedString("profile.saved.filter.videos", comment: "Videos saved filter")
            case .text:
                return NSLocalizedString("profile.saved.filter.text", comment: "Text saved filter")
            case .location:
                return NSLocalizedString("profile.saved.filter.location", comment: "Location saved filter")
            }
        }

        func matches(_ moment: Moment) -> Bool {
            switch self {
            case .all:
                return true
            case .videos:
                if let firstMedia = moment.primaryVisibleMediaItem {
                    return firstMedia.type == .video
                }
                return moment.videoUrl != nil
            case .text:
                return !moment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .location:
                return !(moment.location ?? "").isEmpty
            }
        }
    }

    private var filteredMoments: [Moment] {
        viewModel.moments.filter { selectedFilter.matches($0) }
    }

    private var previewMoments: [Moment] {
        Array(filteredMoments.prefix(12))
    }

    private var recentMoments: [Moment] {
        Array(viewModel.moments.sorted { $0.timestamp > $1.timestamp }.prefix(8))
    }

    private var gridSpacing: CGFloat { 4 }

    private var gridItemSize: CGFloat {
        // 20 + 20 outer padding, then 8 + 8 inner grid padding.
        let availableWidth = UIScreen.main.bounds.width - 56
        return max(88, (availableWidth - (gridSpacing * 2)) / 3)
    }

    var body: some View {
        if viewModel.isLoading {
            // Estado de carga
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(NSLocalizedString("profile.saved.loading", comment: "Loading saved"))
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else if viewModel.moments.isEmpty {
            // Estado vacío
            ProfileSavedPlaceholder()
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(SavedQuickFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedFilter = filter
                                }
                            }) {
                                Text(filter.title)
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(selectedFilter == filter ? ProfileColors.textPrimary : ProfileColors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Color.clear.liquidGlass(
                                            in: Capsule(),
                                            interactive: true
                                        )
                                        .opacity(selectedFilter == filter ? 1 : 0.78)
                                    )
                            }
                            .scaleEffect(selectedFilter == filter ? 1.0 : 0.985)
                        }
                    }

                    Spacer()

                    Button(action: {
                        showingSavedManager = true
                    }) {
                        HStack(spacing: 6) {
                            Text(NSLocalizedString("profile.saved.openAll", comment: "Open all saved"))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(ProfileColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
                    }
                }
                .padding(.horizontal, 20)

                if previewMoments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 30))
                            .foregroundColor(ProfileColors.textSecondary)
                        Text(NSLocalizedString("profile.saved.filtered.empty", comment: "No saved moments for selected filter"))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(ProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 20)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(gridItemSize), spacing: gridSpacing), count: 3),
                        spacing: gridSpacing
                    ) {
                        ForEach(Array(previewMoments.enumerated()), id: \.offset) { index, moment in
                            ScreenshotProtectedView(
                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                            ) {
                                ProfileSavedMomentThumbnail(
                                    moment: moment,
                                    size: gridItemSize,
                                    isRestricted: isMomentRestricted(moment),
                                    isMutedRestriction: isMomentRestricted(moment) && isMomentMuted(moment),
                                    onTap: {
                                        handleSavedMomentTap(
                                            moment: moment,
                                            sourceMoments: filteredMoments,
                                            fallbackIndex: index
                                        )
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: calculateSavedGridHeight(itemCount: previewMoments.count))
                }

                if !recentMoments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("profile.saved.recent", comment: "Recent saved moments section"))
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(ProfileColors.textPrimary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(recentMoments.enumerated()), id: \.offset) { _, moment in
                                    ScreenshotProtectedView(
                                        isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                    ) {
                                        ProfileSavedMomentThumbnail(
                                            moment: moment,
                                            size: 92,
                                            isRestricted: isMomentRestricted(moment),
                                            isMutedRestriction: isMomentRestricted(moment) && isMomentMuted(moment),
                                            onTap: {
                                                handleSavedMomentTap(
                                                    moment: moment,
                                                    sourceMoments: recentMoments,
                                                    fallbackIndex: 0
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingSavedMomentDetail) {
                ModernSavedMomentsDetailView(
                    moments: detailMoments.isEmpty ? filteredMoments.filter { !isMomentRestricted($0) } : detailMoments,
                    initialIndex: selectedSavedMomentIndex,
                    onDismiss: {
                        showingSavedMomentDetail = false
                    },
                    onRemoveMoment: { moment in
                        if let momentId = moment.id {
                            viewModel.removeMoment(momentId: momentId)
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingSavedManager) {
                SavedMomentsView()
            }
            .alert(NSLocalizedString("savedMoments.remove.title", comment: "Remove from saved"), isPresented: $showingRestrictedRemoveAlert) {
                Button(NSLocalizedString("savedMoments.cancel", comment: "Cancel"), role: .cancel) {
                    restrictedMomentToRemove = nil
                }
                Button(NSLocalizedString("savedMoments.remove.confirm", comment: "Remove"), role: .destructive) {
                    if let moment = restrictedMomentToRemove, let momentId = moment.id {
                        viewModel.removeMoment(momentId: momentId)
                    }
                    restrictedMomentToRemove = nil
                }
            } message: {
                if let moment = restrictedMomentToRemove {
                    if isMomentMuted(moment) {
                        Text(NSLocalizedString("savedMoments.remove.message.muted", comment: "Moment hidden due to muted account"))
                    } else {
                        Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
                    }
                } else {
                    Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
                }
            }
        }
    }

    private func isMomentRestricted(_ moment: Moment) -> Bool {
        guard let momentId = moment.id else { return true }
        return !(viewModel.visibilityByMomentId[momentId] ?? true)
    }

    private func isMomentMuted(_ moment: Moment) -> Bool {
        viewModel.isMomentFromMutedUser(moment)
    }

    private func handleSavedMomentTap(moment: Moment, sourceMoments: [Moment], fallbackIndex: Int) {
        guard let momentId = moment.id else { return }

        if let canView = viewModel.visibilityByMomentId[momentId], !canView {
            restrictedMomentToRemove = moment
            showingRestrictedRemoveAlert = true
            return
        }

        if viewModel.visibilityByMomentId[momentId] == nil {
            viewModel.refreshVisibilityForMoment(moment) { canView in
                guard canView else {
                    HapticManager.shared.notification(.warning)
                    return
                }
                openSavedDetail(momentId: momentId, sourceMoments: sourceMoments, fallbackIndex: fallbackIndex)
            }
            return
        }

        openSavedDetail(momentId: momentId, sourceMoments: sourceMoments, fallbackIndex: fallbackIndex)
    }

    private func openSavedDetail(momentId: String, sourceMoments: [Moment], fallbackIndex: Int) {
        let accessibleMoments = sourceMoments.filter { candidate in
            guard let candidateId = candidate.id else { return false }
            return viewModel.visibilityByMomentId[candidateId] ?? true
        }

        guard !accessibleMoments.isEmpty else { return }

        detailMoments = accessibleMoments
        selectedSavedMomentIndex = accessibleMoments.firstIndex(where: { $0.id == momentId }) ?? min(fallbackIndex, max(accessibleMoments.count - 1, 0))
        showingSavedMomentDetail = true
    }

    private func calculateSavedGridHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let columns = 3
        let rows = ceil(Double(itemCount) / Double(columns))
        return CGFloat(rows) * gridItemSize + (CGFloat(rows - 1) * gridSpacing)
    }
}

// MARK: - Thumbnail para momento guardado
struct ProfileSavedMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let isRestricted: Bool
    let isMutedRestriction: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    // Estados para miniaturas de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // --- CONTENIDO MEDIA ---
                Group {
                    if let mediaItem = moment.primaryVisibleMediaItem {
                        if mediaItem.type == .video {
                            videoView(videoURL: mediaItem.url, thumbnailURL: mediaItem.thumbnailUrl)
                        } else {
                            imageView(url: mediaItem.url)
                        }
                    } else if let imagePath = moment.imagePath {
                        imageView(url: imagePath)
                    } else if let videoUrl = moment.videoUrl {
                        videoView(videoURL: videoUrl, thumbnailURL: moment.thumbnailUrl)
                    } else {
                        // Momento de texto
                        textMomentView()
                    }
                }
                .blur(radius: isRestricted ? 14 : 0)

                if isRestricted {
                    savedRestrictedOverlay
                }

                // --- INDICADORES ---

                // Play indicator si es video
                if isVideo && !isRestricted {
                    VStack {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.3)))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }

                if !isRestricted {
                    // Badge de guardado
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(ProfileColors.blue.opacity(0.8)))
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isVideo: Bool {
        if let firstMedia = moment.primaryVisibleMediaItem {
            return firstMedia.type == .video
        }
        return moment.videoUrl != nil
    }

    @ViewBuilder
    private func imageView(url: String) -> some View {
        KFImage(URL(string: url))
            .placeholder {
                Rectangle()
                    .fill(ProfileColors.borderColor.opacity(0.3))
                    .overlay(ProgressView().scaleEffect(0.8))
            }
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipped()
    }

    @ViewBuilder
    private func videoView(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, let url = URL(string: thumb) {
                // Usar thumbnail del servidor
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generated = videoThumbnail {
                // Usar thumbnail generado localmente
                Image(uiImage: generated)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                // Cargando o fallback
                Rectangle()
                    .fill(ProfileColors.borderColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        VStack(spacing: 4) {
                            if isLoadingVideoThumbnail {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    )
                    .onAppear {
                        loadVideoThumbnail(from: videoURL)
                    }
            }
        }
    }

    @ViewBuilder
    private func textMomentView() -> some View {
        ZStack {
            LinearGradient(
                colors: [ProfileColors.blue.opacity(0.8), ProfileColors.accent.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(moment.content)
                .font(.custom("Poppins-Medium", size: 10))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(6)
        }
        .frame(width: size, height: size)
    }

    private var savedRestrictedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                )
                .frame(width: size, height: size)

            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.title" : "savedMoments.restricted.title",
                        comment: "Saved moment restricted title"
                    )
                )
                    .font(.custom("Poppins-SemiBold", size: 9))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.subtitle" : "savedMoments.restricted.subtitle",
                        comment: "Saved moment restricted subtitle"
                    )
                )
                    .font(.custom("Poppins-Regular", size: 8))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func loadVideoThumbnail(from urlString: String) {
        guard videoThumbnail == nil, !isLoadingVideoThumbnail, let url = URL(string: urlString) else { return }

        isLoadingVideoThumbnail = true

        Task {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2)

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
}
