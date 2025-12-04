// StoryChainView.swift
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Story Chain View
struct StoryChainView: View {
    let chainId: String
    let chainTitle: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = StoryChainViewModel()
    @State private var selectedStoryIndex = 0
    @State private var chainStats: (partCount: Int, remainingTime: TimeInterval, isExpired: Bool) = (0, 0, false)
    @State private var showLimitAlert = false
    @State private var limitAlertMessage = ""
    @State private var showStoriesViewer = false
    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fondo glassmorphism simple como UserListView
                Color.clear.ignoresSafeArea()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.blue.opacity(0.4)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                
                if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text(NSLocalizedString("storyChains.loading", comment: "Loading chain"))
                            .foregroundColor(.white.opacity(0.8))
                            .font(.custom("Poppins-Regular", size: 16))
                    }
                } else if viewModel.stories.isEmpty {
                    GlassmorphicEmptyState(
                        icon: "link.broken",
                        message: NSLocalizedString("storyChains.notFound", comment: "No stories found in this chain"),
                        showCloseButton: true,
                        onClose: { dismiss() }
                    )
                } else {
                    VStack(spacing: 0) {
                        // Header con información de la cadena
                        chainHeader
                        
                        // Grid 2x2 de historias con miniatura estática (sin reproducción)
                        ScrollView {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, story in
                                    StoryChainGridItemView(
                                        story: story,
                                        position: story.chainPosition ?? index + 1,
                                        isSelected: selectedStoryIndex == index
                                    )
                                    .onTapGesture {
                                        selectedStoryIndex = index
                                    }
                                    .onTapGesture(count: 2) {
                                        selectedStoryIndex = index
                                        showStoriesViewer = true
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.loadChainStories(chainId: chainId)
        }
        .fullScreenCover(isPresented: $showStoriesViewer) {
            StoriesView(chainStories: viewModel.stories, startAtIndex: selectedStoryIndex)
        }
    }
    
    // MARK: - Chain Header
    private var chainHeader: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(chainTitle)
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    Text(String(format: NSLocalizedString("storyChains.parts", comment: "Parts"), chainStats.partCount, StoryChainLimits.maxParts))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                    
                    if !chainStats.isExpired {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(chainStats.remainingTime.formattedRemainingTime())
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(chainStats.remainingTime < 3600 ? .red : .secondary)
                    } else {
                        Text(NSLocalizedString("storyChains.expired", comment: "Expired"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            
            // Indicador de progreso de la cadena
            if !viewModel.stories.isEmpty {
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.stories.count, id: \.self) { index in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: index <= selectedStoryIndex
                                    ? [Color.blue, Color.purple, Color.pink]
                                    : [Color.white.opacity(0.3), Color.white.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .clipShape(Capsule())
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .background(.ultraThinMaterial)
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.blue.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            loadChainStats()
        }
        .alert(NSLocalizedString("storyChains.chainLimit", comment: "Chain Limit"), isPresented: $showLimitAlert) {
            Button(NSLocalizedString("storyChains.ok", comment: "OK")) { }
        } message: {
            Text(limitAlertMessage)
        }
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
                
                try await StoryChainLimitsService.shared.canContinueChain(chainId: chainId, userId: userId)
                
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
    
    private var thumbnailURL: URL? {
        if story.mediaItem.type == .video {
            if let thumb = story.mediaItem.thumbnailUrl, let url = URL(string: thumb) { return url }
            return URL(string: story.mediaItem.url)
        } else {
            return URL(string: story.mediaItem.url)
        }
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
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .clipped()
                    case .failure(_):
                        ZStack {
                            Color.white.opacity(0.06)
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
                    Color.white.opacity(0.06)
                    Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                        .foregroundColor(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            // Degradado sutil para legibilidad
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // Número de parte (esquina superior izquierda)
            VStack {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .background(.ultraThinMaterial)
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        Text("\(position)")
                            .font(.custom("Poppins-Bold", size: 13))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 28, height: 28)
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            
            // Pie con usuario y tipo de media
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: story.mediaItem.type == .video ? "video.fill" : "photo.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Text(story.username)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.15))
                .clipShape(Capsule())
                .padding(8)
            }
            .allowsHitTesting(false)
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
                    : LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
                .background(.ultraThinMaterial)
        )
    }
}

// MARK: - Preview
struct StoryChainView_Previews: PreviewProvider {
    static var previews: some View {
        StoryChainView(
            chainId: "preview-chain-id",
            chainTitle: NSLocalizedString("storyChains.example.title", comment: "My Day in 5 Photos")
        )
    }
}
