import SwiftUI
import AVFoundation


struct CarouselView: View {
    let mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(mediaItems.indices, id: \.self) { index in
                let mediaItem = mediaItems[index]
                Group {
                    if mediaItem.type == .image, let url = URL(string: mediaItem.url), !mediaItem.url.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.gray.opacity(0.3)
                                    .overlay(ProgressView().tint(.gray))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            case .failure:
                                Color.gray.opacity(0.3)
                            @unknown default:
                                Color.gray.opacity(0.3)
                            }
                        }
                    } else if mediaItem.type == .video, let url = URL(string: mediaItem.url), !mediaItem.url.isEmpty {
                        CustomVideoPlayer(url: url)
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.6),
                                        Color.purple.opacity(0.8),
                                        Color.pink.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .tag(index)
            }
        }
        // Android: PageTabViewStyle handled natively
    }
}

// MARK: - CustomVideoPlayer (Android placeholder)
// Video player will be implemented using native Android APIs
struct CustomVideoPlayer: View {
    let url: URL
    @State var isPlaying = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        Text("Video player")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                )
        }
        .onTapGesture {
            isPlaying.toggle()
        }
    }
}

// ✅ COMPONENTE ACTUALIZADO: AsyncProfileImageView con actualizaciones en tiempo real
struct AsyncProfileImageView: View {
    let userId: String
    @State var profileImagePath: String?
    @State var isLoading = true
    @State var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            // Fondo base siempre presente
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Contenido superpuesto
            if isLoading && profileImagePath == nil {
                // Estado de carga
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .tint(.white)
                    .scaleEffect(0.7)
            } else if let path = profileImagePath, let url = URL(string: path), !path.isEmpty {
                // Imagen del usuario con AsyncImage nativo
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
                .clipShape(Circle())
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoading = false
                    }
                }
            } else {
                // Placeholder cuando no hay imagen
                Image(systemName: "person.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            loadUserProfileImage()
            startListeningForChanges()
        }
        .onDisappear {
            stopListening()
        }
    }

    private func loadUserProfileImage() {
        guard !userId.isEmpty else {
            isLoading = false
            return
        }
        
        db.collection("users").document(userId).getDocument { document, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    return
                }

                if let data = document?.data(),
                   let path = data["profileImagePath"] as? String {
                    self.profileImagePath = path
                }
            }
        }
    }
    
    private func startListeningForChanges() {
        guard !userId.isEmpty else { return }
        
        listener = db.collection("users").document(userId)
            .addSnapshotListener { document, error in
                guard let document = document,
                      document.exists,
                      let data = document.data() else { return }
                
                let newImagePath = data["profileImagePath"] as? String
                
                DispatchQueue.main.async {
                    if newImagePath != self.profileImagePath {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.profileImagePath = newImagePath
                        }
                    }
                }
            }
    }
    
    private func stopListening() {
        listener?.remove()
        listener = nil
    }
}

struct ProfileImageView: View {
    let imagePath: String?

    var body: some View {
        Group {
            if let path = imagePath, let url = URL(string: path), !path.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(ProgressView().tint(.white))
                            .frame(width: 40, height: 40)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    case .failure:
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                    @unknown default:
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                    }
                }
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    )
                    .frame(width: 40, height: 40)
            }
        }
    }
}

struct ActionSubCardView: View {
    let moment: Moment
    let onComment: () -> Void
    @EnvironmentObject var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme
    @State var isSaved: Bool = false
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: {
                toggleLike()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: moment.reactions["heart"]?.contains(Auth.auth().currentUser?.uid ?? "") ?? false ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    // ✅ NUEVO: El autor siempre ve el contador, los demás solo si no está oculto
                    if moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts {
                        Text("\(moment.reactions["heart"]?.count ?? 0)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
            
            Button(action: onComment) {
                HStack(spacing: 6) {
                    Image(systemName: "message")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text("\(moment.commentCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Text("0")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            Button(action: {
                toggleSave()
            }) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            colorScheme == .dark ? Color.black.opacity(0.8) : Color.gray.opacity(0.6),
                            colorScheme == .dark ? Color.gray.opacity(0.7) : Color.gray.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        .onAppear {
            checkIfSaved()
        }
    }
    
    private func toggleLike() {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        // Usar addReaction en lugar de toggleMomentLike
        firestoreService.addReaction(to: momentId, reaction: "heart", userId: userId, authorId: moment.authorId) { error in
            if let error = error {
            }
        }
    }
    
    private func checkIfSaved() {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        // Usar checkIfSaved (ya correcto)
        firestoreService.checkIfSaved(userId: userId, momentId: momentId) { result in
            switch result {
            case .success(let saved):
                DispatchQueue.main.async {
                    self.isSaved = saved
                }
            case .failure(_):
                break
            }
        }
    }
    
    private func toggleSave() {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        // Usar toggleSaveMoment en lugar de saveMoment/removeSavedMoment
        firestoreService.toggleSaveMoment(userId: userId, momentId: momentId) { error in
            if let error = error {
            } else {
                DispatchQueue.main.async {
                    self.isSaved.toggle() // Actualizar estado local
                }
            }
        }
    }
}
