// StoryChainView.swift
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Story Chain View
struct StoryChainView: View {
    let chainId: String
    let chainTitle: String
    let canContinueChain: Bool // 🔗 NUEVO: Indica si el usuario actual puede continuar esta cadena
    let initialStoryId: String?
    let initialChainPosition: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = StoryChainViewModel()
    @State private var selectedStoryIndex = 0
    @State private var didApplyInitialSelection = false
    @State private var chainStats: (partCount: Int, remainingTime: TimeInterval, isExpired: Bool) = (0, 0, false)
    @State private var showLimitAlert = false
    @State private var limitAlertMessage = ""
    @State private var showStoriesViewer = false
    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(
        chainId: String,
        chainTitle: String,
        canContinueChain: Bool,
        initialStoryId: String? = nil,
        initialChainPosition: Int? = nil
    ) {
        self.chainId = chainId
        self.chainTitle = chainTitle
        self.canContinueChain = canContinueChain
        self.initialStoryId = initialStoryId
        self.initialChainPosition = initialChainPosition
    }
    
    var body: some View {
        ZStack {
            sheetBackground
                .ignoresSafeArea()

            Group {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.stories.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        chainHeader

                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, story in
                                    StoryChainGridItemView(
                                        story: story,
                                        position: story.chainPosition ?? index + 1,
                                        isSelected: selectedStoryIndex == index
                                    )
                                    .onTapGesture {
                                        selectedStoryIndex = index
                                        showStoriesViewer = true
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, canContinueChain ? 92 : 28)
                        }
                    }
                }
            }

            if canContinueChain && !viewModel.isLoading && !viewModel.stories.isEmpty {
                VStack {
                    Spacer()
                    continueFloatingButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
        .alert(NSLocalizedString("storyChains.chainLimit", comment: "Chain Limit"), isPresented: $showLimitAlert) {
            Button(NSLocalizedString("storyChains.ok", comment: "OK")) { }
        } message: {
            Text(limitAlertMessage)
        }
        .onAppear {
            viewModel.loadChainStories(chainId: chainId)
        }
        .onReceive(viewModel.$stories) { _ in
            applyInitialSelectionIfNeeded()
        }
        .fullScreenCover(isPresented: $showStoriesViewer) {
            StoriesView(chainStories: viewModel.stories, startAtIndex: selectedStoryIndex)
        }
    }

    private var sheetBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryForeground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.62)
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.25)
                .tint(primaryForeground)

            Text(NSLocalizedString("storyChains.loading", comment: "Loading chain"))
                .foregroundColor(secondaryForeground)
                .font(.custom("Poppins-Regular", size: 16))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryForeground)
                    .frame(width: 38, height: 38)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                Image(systemName: "link.slash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(primaryForeground)

                Text(NSLocalizedString("storyChains.notFound", comment: "No stories found in this chain"))
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundStyle(primaryForeground)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
    }

    private var continueFloatingButton: some View {
        Button(action: {
            continueChain()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))

                Text(NSLocalizedString("storyChains.continueStory", comment: "Continue Story"))
                    .font(.custom("Poppins-SemiBold", size: 15))
            }
            .foregroundStyle(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .background(
                colorScheme == .dark ? Color(hex: "FAF9F6") : Color(hex: "0B1215"),
                in: Capsule()
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Chain Header
    private var chainHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(primaryForeground)
                        .frame(width: 38, height: 38)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    Text(NSLocalizedString("storyChains.chain", comment: "Chain"))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(secondaryForeground)
                    Text(chainTitle)
                        .font(.custom("Poppins-SemiBold", size: 24))
                        .foregroundColor(primaryForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)

                Color.clear.frame(width: 38, height: 38)
            }

            HStack(spacing: 8) {
                infoChip(
                    icon: "link",
                    text: String(format: NSLocalizedString("storyChains.parts", comment: "Parts"), chainStats.partCount, StoryChainLimits.maxParts),
                    tint: colorScheme == .dark ? .white.opacity(0.86) : .black.opacity(0.76)
                )

                if !chainStats.isExpired {
                    infoChip(
                        icon: "clock",
                        text: chainStats.remainingTime.formattedRemainingTime(),
                        tint: chainStats.remainingTime < 3600 ? .red : (colorScheme == .dark ? .white.opacity(0.86) : .black.opacity(0.76))
                    )
                } else {
                    infoChip(
                        icon: "xmark.circle",
                        text: NSLocalizedString("storyChains.expired", comment: "Expired"),
                        tint: .red
                    )
                }
            }

            if !viewModel.stories.isEmpty {
                HStack(spacing: 5) {
                    ForEach(0..<viewModel.stories.count, id: \.self) { index in
                        Capsule()
                            .fill(
                                index <= selectedStoryIndex
                                ? LinearGradient(
                                    colors: [Color.blue, Color.purple, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [
                                        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.16),
                                        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 4)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .onAppear {
            loadChainStats()
        }
    }

    @ViewBuilder
    private func infoChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.custom("Poppins-Medium", size: 12))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: false))
    }
    
    // MARK: - Helper Functions
    private func openStoryViewer(story: Story, index: Int) {
        // Aquí podrías abrir el viewer de historias individual
        // Por ahora solo actualizamos el índice seleccionado
        selectedStoryIndex = index
    }
    
    private func loadChainStats() {
        Task {
            do {
                let stats = try await StoryChainLimitsService.shared.getChainStats(chainId: chainId)
                await MainActor.run {
                    chainStats = stats
                }
            } catch {
                // Error loading chain statistics
            }
        }
    }
    
    private func continueChain() {
        // Validar límites antes de continuar
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else { return }
                
                _ = try await StoryChainLimitsService.shared.canContinueChain(chainId: chainId, userId: userId)
                
                await MainActor.run {
                    // Cerrar esta vista y abrir el creator para continuar la cadena
                    dismiss()
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ContinueStoryChain"),
                        object: nil,
                        userInfo: [
                            "chainId": chainId,
                            "chainTitle": chainTitle,
                            "chainPosition": viewModel.stories.count + 1
                        ]
                    )
                }
            } catch {
                await MainActor.run {
                    if let chainError = error as? StoryChainLimitError {
                        limitAlertMessage = chainError.localizedDescription
                    } else {
                        limitAlertMessage = String(format: NSLocalizedString("storyChains.error.validation", comment: "Error validating chain"), error.localizedDescription)
                    }
                    showLimitAlert = true
                }
            }
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard !didApplyInitialSelection, !viewModel.stories.isEmpty else { return }

        let resolvedIndex: Int
        if let initialStoryId,
           let idx = viewModel.stories.firstIndex(where: { $0.id == initialStoryId }) {
            resolvedIndex = idx
        } else if let initialChainPosition,
                  let idx = viewModel.stories.firstIndex(where: { $0.chainPosition == initialChainPosition }) {
            resolvedIndex = idx
        } else {
            resolvedIndex = 0
        }

        selectedStoryIndex = max(0, min(resolvedIndex, viewModel.stories.count - 1))
        didApplyInitialSelection = true
    }
}

// MARK: - Story Chain Item View
struct StoryChainItemView: View {
    let story: Story
    let position: Int
    let totalParts: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View { 
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Número de parte
                ZStack {
                    // Fondo glassmorphism
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .background(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                    
                    // Color de selección
                    Circle()
                        .fill(isSelected ? Color.blue : Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    // Número
                    Text("\(position)")
                        .font(.custom("Poppins-Bold", size: 16))
                        .foregroundColor(.primary)
                }
                
                // Contenido de la historia
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(story.username)
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(timeAgoString(from: story.timestamp))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    if let text = story.text, !text.isEmpty {
                        Text(text)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Indicador de tipo de media
                    HStack(spacing: 4) {
                        Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(story.mediaItem.type == .video ? NSLocalizedString("storyChains.video", comment: "Video") : NSLocalizedString("storyChains.photo", comment: "Photo"))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Indicador de selección
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Fondo glassmorphism
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .background(.ultraThinMaterial)
                    
                    // Borde
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected
                            ? LinearGradient(colors: [Color.blue, Color.purple, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Story Chain View Model
class StoryChainViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firestoreService = FirestoreService()
    
    func loadChainStories(chainId: String) {
        isLoading = true
        error = nil
        
        firestoreService.db.collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .order(by: "chainPosition", descending: false)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.error = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.stories = []
                        return
                    }
                    
                    self?.stories = documents.compactMap { document in
                        try? document.data(as: Story.self)
                    }
                }
            }
    }
}

// MARK: - Grid Item (Miniatura estática 2x2)
struct StoryChainGridItemView: View {
    let story: Story
    let position: Int
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var thumbnailURL: URL? {
        if story.mediaItem.type == .video {
            if let thumb = story.mediaItem.thumbnailUrl, let url = URL(string: thumb) { return url }
            return URL(string: story.mediaItem.url)
        } else {
            return URL(string: story.mediaItem.url)
        }
    }

    private var profileImageURL: URL? {
        guard let path = story.profileImagePath, !path.isEmpty else { return nil }
        return URL(string: path)
    }
    
    var body: some View {
        ZStack {
            // Miniatura estática
            if let url = thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.white.opacity(0.06)
                            ProgressView().tint(.white)
                        }
                        .clipped()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    case .failure(_):
                        ZStack {
                            (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                            Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                                .foregroundColor(.secondary)
                        }
                        .clipped()
                    @unknown default:
                        Color.white.opacity(0.06)
                    }
                }
            } else {
                ZStack {
                    (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            // Degradado sutil para legibilidad
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // Header superior: username + número de parte con avatar oscurecido
            VStack {
                HStack(spacing: 6) {
                    Spacer()

                    Text(story.username)
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.34))
                        .clipShape(Capsule())

                    ZStack {
                        if let url = profileImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Circle().fill(Color.black.opacity(0.35))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Circle().fill(Color.black.opacity(0.35))
                                @unknown default:
                                    Circle().fill(Color.black.opacity(0.35))
                                }
                            }
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.7), Color.black.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)
                        }

                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 30, height: 30)

                        Circle()
                            .stroke(Color.white.opacity(0.32), lineWidth: 0.7)
                            .frame(width: 30, height: 30)

                        Text("\(position)")
                            .font(.custom("Poppins-Bold", size: 13))
                            .foregroundColor(.white)
                    }
                }
                Spacer()
            }
            .padding(8)

        }
        .frame(maxWidth: .infinity)
        .aspectRatio(9/16, contentMode: .fit)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected
                    ? LinearGradient(colors: [Color.blue, Color.purple, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.2),
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.6 : 0.8
                )
        )
    }
}
