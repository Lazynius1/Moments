import SwiftUI
import AVKit
import AVFoundation
import Kingfisher
import FirebaseFirestore
import FirebaseAuth


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
                        KFImage(url)
                            .resizable()
                            .placeholder {
                                Color.gray.opacity(0.3)
                                    .overlay(ProgressView().tint(.gray))
                            }
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
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
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
}

struct CustomVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = view.bounds
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)

        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer

        player.play()

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap))
        view.addGestureRecognizer(tapGesture)

        context.coordinator.observeBounds(view: view)

        return view
    }

    func updateUIView(_ uiViewController: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiViewController.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var boundsObservation: NSKeyValueObservation?
        let parent: CustomVideoPlayer

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
        }

        func observeBounds(view: UIView) {
            boundsObservation = view.observe(\.bounds) { [weak self] view, _ in
                self?.playerLayer?.frame = view.bounds
            }
        }

        @objc func handleTap() {
            if player?.timeControlStatus == .playing {
                player?.pause()
            } else {
                player?.play()
            }
        }

        deinit {
            boundsObservation?.invalidate()
        }
    }
}

// ✅ COMPONENTE ACTUALIZADO: AsyncProfileImageView con actualizaciones en tiempo real
struct AsyncProfileImageView: View {
    let userId: String
    @State private var profileImagePath: String?
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?
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
                // ✅ MEJORADO: Usar Kingfisher para caché persistente
                KFImage(url)
                    .onSuccess { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLoading = false
                        }
                    }
                    .resizable()
                    .placeholder {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    }
                    .fade(duration: 0.3)
                    .scaledToFill()
                    .clipShape(Circle())
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
        // ✅ CRÍTICO: Fix para el bug de fotos equivocadas en listas (Cell Reuse)
        .id(userId) // 👈 ESTO FUERZA QUE LA VISTA SE RECREE SI CAMBIA EL ID
        .onChange(of: userId) { newUserId in
            resetAndReload(for: newUserId)
        }
    }

    private func resetAndReload(for newUserId: String) {
        // 1. Detener listener anterior
        stopListening()
        
        // 2. Limpiar estado anterior inmediatamente
        profileImagePath = nil
        isLoading = true
        
        // 3. Iniciar nueva carga si el ID es válido
        if !newUserId.isEmpty {
            loadUserProfileImage()
            startListeningForChanges()
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
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(ProgressView().tint(.white))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
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
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme
    @State private var isSaved: Bool = false
    
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
