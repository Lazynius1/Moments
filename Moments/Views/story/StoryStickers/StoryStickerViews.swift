import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Interactive Poll Data
struct InteractivePollData {
    let pollData: [String]
    let storyId: String
    let stickerId: String
}

// MARK: - Interactive Poll Overlay
struct InteractivePollOverlay: View {
    let pollData: [String]
    let storyId: String
    let userId: String
    let stickerId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0]
    @State private var totalVotes = 0

    var body: some View {
        ZStack {
            // Fondo semi-transparente
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 20) {
                // Pregunta
                Text(pollData[0])
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                // Opciones interactivas
                VStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { index in
                        InteractivePollOption(
                            text: pollData[index + 1],
                            percentage: calculatePercentage(for: index),
                            isSelected: selectedOption == index,
                            hasVoted: hasVoted,
                            onTap: {
                                if !hasVoted {
                                    selectedOption = index
                                    submitVote()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 30)

                if hasVoted {
                    Text("poll.thanks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.top, 10)
                }

                Text(String(format: NSLocalizedString("poll.votes", comment: "Votes count"), totalVotes))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            loadVoteCounts()
        }
    }

    private func calculatePercentage(for option: Int) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCounts[option] ?? 0) / Double(totalVotes) * 100
    }

    private func submitVote() {
        guard let selectedOption = selectedOption,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Guardar voto en Firestore
        let voteData: [String: Any] = [
            "userId": currentUserId,
            "option": selectedOption,
            "timestamp": FieldValue.serverTimestamp()
        ]

        pollVotesCollection()
            .document(currentUserId)
            .setData(voteData) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        hasVoted = true
                        loadVoteCounts()
                    }
                }
            }
    }

    private func loadVoteCounts() {
        pollVotesCollection()
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                    totalVotes = counts.values.reduce(0, +)
                }
            }
    }

    private func pollVotesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(stickerId)
            .collection("votes")
    }
}

// MARK: - Interactive Poll Sticker (Estilo Nativo)
struct InteractivePollSticker: View {
    let pollData: [String]
    let storyId: String
    let userId: String
    let stickerId: String
    @Binding var selectedOption: Int?
    @Binding var hasVoted: Bool
    @Binding var voteCounts: [Int: Int]
    @Binding var totalVotes: Int
    let onVote: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(pollData[0].count > 42 ? String(pollData[0].prefix(42)) + "..." : pollData[0])
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 18)
                .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    InteractivePollOptionButton(
                        text: pollData[index + 1].count > 26 ? String(pollData[index + 1].prefix(26)) + "..." : pollData[index + 1],
                        percentage: calculatePercentage(for: index),
                        isSelected: selectedOption == index,
                        hasVoted: hasVoted,
                        onTap: {
                            if !hasVoted {
                                selectedOption = index
                                onVote(index)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(
            Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .onAppear {
            loadVoteCounts()
        }
    }

    private func calculatePercentage(for option: Int) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCounts[option] ?? 0) / Double(totalVotes) * 100
    }

    private func loadVoteCounts() {
        // ✅ Cargar votos reales desde Firestore
        guard !storyId.isEmpty else { return }

        pollVotesCollection()
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    return
                }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                    totalVotes = counts.values.reduce(0, +)
                }
            }

        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        pollVotesCollection()
            .document(currentUserId)
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let option = data["option"] as? Int else { return }

                DispatchQueue.main.async {
                    selectedOption = option
                    hasVoted = true
                }
            }
    }

    private func pollVotesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(stickerId)
            .collection("votes")
    }
}

// MARK: - Interactive Poll Option Button
struct InteractivePollOptionButton: View {
    let text: String
    let percentage: Double
    let isSelected: Bool
    let hasVoted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.1))

                    if hasVoted {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? Color.white : Color.white.opacity(0.35))
                            .frame(width: proxy.size.width * (percentage / 100))
                            .animation(.easeInOut(duration: 0.5), value: percentage)
                    }

                    HStack(spacing: 10) {
                        Text(text)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isSelected ? .black : .white)
                            .shadow(color: isSelected ? .clear : .black.opacity(0.15), radius: 2)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if hasVoted {
                            Text("\(Int(percentage))%")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isSelected ? .black : .white)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 52)
        .disabled(hasVoted)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Interactive Poll Option
struct InteractivePollOption: View {
    let text: String
    let percentage: Double
    let isSelected: Bool
    let hasVoted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Barra de progreso
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 50)
                    .overlay(
                        Rectangle()
                            .fill(isSelected ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: UIScreen.main.bounds.width * 0.7 * (percentage / 100))
                            .animation(.easeInOut(duration: 0.5), value: percentage)
                        , alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 25))

                // Texto y porcentaje
                HStack {
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    if hasVoted {
                        Text("\(Int(percentage))%")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .disabled(hasVoted)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// MARK: - Poll Vote View
struct PollVoteView: View {
    let pollData: [String]
    let storyId: String
    let userId: String
    let stickerId: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0] // option index: count

    var body: some View {
        ZStack {
            // Fondo con blur
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 25) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)

                    Text("poll.vote")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }

                // Pregunta
                Text(pollData[0])
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Opciones
                VStack(spacing: 15) {
                    ForEach(0..<2, id: \.self) { index in
                        Button(action: {
                            selectedOption = index
                            submitVote()
                        }) {
                            HStack {
                                Text(pollData[index + 1])
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)

                                Spacer()

                                if hasVoted {
                                    Text("\(voteCounts[index] ?? 0)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedOption == index ? Color.blue : Color.white.opacity(0.2))
                            )
                        }
                        .disabled(hasVoted)
                    }
                }
                .padding(.horizontal, 20)

                if hasVoted {
                    Text("poll.thanks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                }

                // Botón cerrar
                Button("common.close") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                )
            }
            .padding(30)
        }
        .onAppear {
            loadVoteCounts()
        }
    }

    private func submitVote() {
        guard let selectedOption = selectedOption,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Guardar voto en Firestore
        let voteData: [String: Any] = [
            "userId": currentUserId,
            "option": selectedOption,
            "timestamp": FieldValue.serverTimestamp()
        ]

        pollVotesCollection()
            .document(currentUserId)
            .setData(voteData) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        hasVoted = true
                        loadVoteCounts()
                    }
                }
            }
    }

    private func loadVoteCounts() {
        pollVotesCollection()
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }

                var counts: [Int: Int] = [0: 0, 1: 0]
                for doc in documents {
                    if let option = doc.data()["option"] as? Int {
                        counts[option, default: 0] += 1
                    }
                }

                DispatchQueue.main.async {
                    voteCounts = counts
                }
            }
    }

    private func pollVotesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(stickerId)
            .collection("votes")
    }
}

private struct InteractiveEmojiSliderSticker: View {
    let prompt: String
    let emoji: String
    let storyId: String
    let userId: String
    let stickerId: String

    @State private var dragValue: Double?
    @State private var submittedValue: Double?
    @State private var averageValue: Double = 0.5
    @State private var totalVotes: Int = 0

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isAuthor: Bool {
        currentUserId == userId
    }

    private var displayValue: Double {
        if let dragValue {
            return dragValue
        }
        if let submittedValue {
            return submittedValue
        }
        if isAuthor, totalVotes > 0 {
            return averageValue
        }
        return 0.5
    }

    private var canVote: Bool {
        !isAuthor && submittedValue == nil && currentUserId != nil && !storyId.isEmpty
    }

    private var displayAverage: Double? {
        if isAuthor {
            return nil
        }
        if submittedValue != nil, totalVotes > 0 {
            return averageValue
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            StickerEmojiSliderCardView(
                prompt: prompt,
                emoji: emoji,
                value: displayValue,
                averageValue: displayAverage
            )
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geometry in
                let metrics = emojiSliderTrackMetrics(totalWidth: geometry.size.width)
                let trackFrame = emojiSliderTrackFrame(totalSize: geometry.size, showsPrompt: emojiSliderHasPrompt(prompt))

                // Hitbox expandida para que sea MUCHO más fácil de tocar
                let hitBox = CGRect(
                    x: trackFrame.minX - 40,
                    y: trackFrame.minY - 30,
                    width: trackFrame.width + 80,
                    height: trackFrame.height + 60
                )

                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                // Solo requiere estar dentro al iniciar, luego fluye
                                guard canVote, hitBox.contains(gesture.startLocation) else { return }
                                dragValue = normalizedValue(
                                    for: gesture.location.x,
                                    metrics: metrics
                                )
                            }
                            .onEnded { gesture in
                                guard canVote, hitBox.contains(gesture.startLocation) else {
                                    dragValue = nil
                                    return
                                }

                                let value = normalizedValue(
                                    for: gesture.location.x,
                                    metrics: metrics
                                )
                                dragValue = nil
                                submitVote(value)
                            }
                    )
            }
        }
        .onAppear {
            loadVoteState()
            loadVoteAggregate()
        }
    }

    private func normalizedValue(for locationX: CGFloat, metrics: (leading: CGFloat, width: CGFloat, thumbBaseSize: CGFloat, trackHeight: CGFloat)) -> Double {
        let minX = metrics.leading
        let maxX = metrics.leading + metrics.width
        let clampedX = min(max(locationX, minX), maxX)
        return Double((clampedX - minX) / max(metrics.width, 1))
    }

    private func sliderVotesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("emojiSliders")
            .document(stickerId)
            .collection("votes")
    }

    private func loadVoteState() {
        guard let currentUserId else { return }

        sliderVotesCollection()
            .document(currentUserId)
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data() else { return }

                // Safely decode Double or Int
                let value: Double
                if let doubleVal = data["value"] as? Double {
                    value = doubleVal
                } else if let intVal = data["value"] as? Int {
                    value = Double(intVal)
                } else {
                    return
                }

                DispatchQueue.main.async {
                    submittedValue = value
                }
            }
    }

    private func loadVoteAggregate() {
        sliderVotesCollection()
            .getDocuments { snapshot, _ in
                let values = snapshot?.documents.compactMap { $0.data()["value"] as? Double } ?? []
                let total = values.count
                let average = total > 0 ? values.reduce(0, +) / Double(total) : 0.5

                DispatchQueue.main.async {
                    totalVotes = total
                    averageValue = average
                }
            }
    }

    private func submitVote(_ value: Double) {
        guard let currentUserId else { return }

        let voteRef = sliderVotesCollection().document(currentUserId)
        voteRef.getDocument { snapshot, _ in
            if let data = snapshot?.data() {
                let existingValue: Double?
                if let doubleVal = data["value"] as? Double {
                    existingValue = doubleVal
                } else if let intVal = data["value"] as? Int {
                    existingValue = Double(intVal)
                } else {
                    existingValue = nil
                }

                if let validExistingValue = existingValue {
                    DispatchQueue.main.async {
                        submittedValue = validExistingValue
                        loadVoteAggregate()
                    }
                    return
                }
            }

            voteRef.setData([
                "userId": currentUserId,
                "value": value,
                "timestamp": FieldValue.serverTimestamp()
            ]) { error in
                guard error == nil else { return }

                DispatchQueue.main.async {
                    submittedValue = value
                    loadVoteAggregate()
                }
            }
        }
    }
}

// MARK: - StoryStickerView para mostrar stickers en historias
struct StoryStickerView: View {
    let sticker: StickerItem
    let screenSize: CGSize
    let storyId: String
    let userId: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void

    @State private var selectedPollOption: Int? = nil
    @State private var hasVoted = false
    @State private var voteCounts: [Int: Int] = [0: 0, 1: 0]
    @State private var totalVotes = 0

    var body: some View {
        // ✅ SOLUCIÓN DEFINITIVA: Solo una renderización
        if sticker.type == .shareMoment {
            // ✅ SHARE MOMENT UNIFICADO (FOTO Y VIDEO)
            // Renderizamos siempre el header y caption, independientemente de si es animado o no
            Button(action: {
                handleStickerTap()
            }) {
                ZStack {
                    // 1. Capa base: Imagen estática
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)

                    // 2. Capa animada: Video (si existe)
                    if let videoURL = sticker.videoURL {
                         StickerVideoPlayer(url: videoURL)
                            .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                            .allowsHitTesting(false)
                    }

                    // 3. OVERLAYS (Header + Caption) - SIEMPRE VISIBLES
                    ZStack(alignment: .top) {
                        Color.clear // Contenedor transparente para alinear

                        // Header Overlay (Username + Profile)
                        HStack(spacing: 10 * sticker.scale) {
                            // Profile Image
                            if let interactionData = sticker.interactionData,
                               let userId = interactionData.userId {
                                AsyncProfileImageView(userId: userId)
                                    .frame(width: 34 * sticker.scale, height: 34 * sticker.scale)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1 * sticker.scale
                                            )
                                    )
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 34 * sticker.scale, height: 34 * sticker.scale)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text(sticker.interactionData?.username ?? "User")
                                    .font(.custom("Poppins-Bold", size: 13 * sticker.scale))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12 * sticker.scale)
                        .padding(.vertical, 10 * sticker.scale)
                        .background(
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.black, .black, .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9 * sticker.scale))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8 * sticker.scale)
                                    .padding(.vertical, 4 * sticker.scale)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10 * sticker.scale)
                            }
                        }

                        // Gallery Indicator Overlay (Top Right)
                        if (sticker.interactionData?.mediaCount ?? 0) > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 11 * sticker.scale, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6 * sticker.scale)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8 * sticker.scale))
                                        .padding(12 * sticker.scale)
                                        .padding(.top, 42 * sticker.scale) // Below header text
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)

        } else if sticker.isAnimated {
            Button(action: {
                handleStickerTap()
            }) {
                if let videoURL = sticker.videoURL {
                    ZStack {
                        Image(uiImage: sticker.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)

                        ZStack(alignment: .top) {
                            StickerVideoPlayer(url: videoURL)
                                .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                                .allowsHitTesting(false)

                            if let interactionData = sticker.interactionData, let username = interactionData.username {
                                HStack(spacing: 8 * sticker.scale) {
                                    Circle()
                                        .fill(.white.opacity(0.1))
                                        .frame(width: 24 * sticker.scale, height: 24 * sticker.scale)
                                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5 * sticker.scale))

                                    Text(username)
                                        .font(.custom("Poppins-Bold", size: 10 * sticker.scale))
                                        .foregroundColor(.white)

                                    Spacer()
                                }
                                .padding(.horizontal, 10 * sticker.scale)
                                .padding(.vertical, 8 * sticker.scale)
                                .background(
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .mask(
                                            LinearGradient(
                                                colors: [.black, .black, .clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                            }

                            if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                                VStack {
                                    Spacer()
                                    Text(caption)
                                        .font(.custom("Poppins-Medium", size: 9 * sticker.scale))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8 * sticker.scale)
                                        .padding(.vertical, 4 * sticker.scale)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                        .padding(.bottom, 10 * sticker.scale)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
                    .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                } else if sticker.gifURL != nil {
                    AnimatedStickerView(
                        sticker: sticker,
                        size: CGSize(
                            width: sticker.image.size.width * sticker.scale,
                            height: sticker.image.size.height * sticker.scale
                        )
                    )
                    .frame(
                        width: sticker.image.size.width * sticker.scale,
                        height: sticker.image.size.height * sticker.scale
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .poll, let pollData = sticker.interactionData?.pollData {
            // ✅ POLL INTERACTIVO: Diseño completo e interactivo
            InteractivePollSticker(
                pollData: pollData,
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id,
                selectedOption: $selectedPollOption,
                hasVoted: $hasVoted,
                voteCounts: $voteCounts,
                totalVotes: $totalVotes,
                onVote: { option in
                    handlePollVote(option: option, pollData: pollData)
                }
            )
            .frame(width: 300, height: 172)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
            // ✅ QUESTION INTERACTIVO: Diseño completo e interactivo
            InteractiveQuestionSticker(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(width: 300, height: 132)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
            // ✅ LOCATION INTERACTIVO: Diseño completo e interactivo
            InteractiveLocationSticker(
                locationName: locationName,
                coordinate: sticker.interactionData?.locationCoordinate,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .mention, let username = sticker.interactionData?.username {
            // ✅ MENTION INTERACTIVO: Diseño completo nativo
            InteractiveMentionSticker(
                username: username,
                onTap: {
                    handleStickerTap()
                }
            )
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
            // ✅ HASHTAG INTERACTIVO: Diseño completo e interactivo
            InteractiveHashtagSticker(
                hashtag: hashtag,
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .quiz, let question = sticker.interactionData?.quizQuestion, let options = sticker.interactionData?.quizOptions {
            InteractiveQuizSticker(
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id,
                question: question,
                options: options,
                correctIndex: sticker.interactionData?.quizCorrectIndex ?? 0
            )
            .frame(width: 300) // ✅ CONSISTENCIA CON EL EDITOR
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .frame {
            InteractiveFrameSticker(
                storyId: storyId,
                image: sticker.image,
                caption: sticker.interactionData?.caption,
                contentScale: sticker.interactionData?.contentScale ?? 1.0,
                contentOffset: CGSize(
                    width: sticker.interactionData?.contentOffsetX ?? 0,
                    height: sticker.interactionData?.contentOffsetY ?? 0
                ),
                onPauseStory: onPauseStory,
                onResumeStory: onResumeStory
            )
            .frame(width: 200, height: 240) // ✅ CONSISTENCIA CON EL EDITOR
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .reveal {
            EmptyView()
        } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
            Button(action: {
                handleStickerTap()
            }) {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .countdown,
                  let countdownTitle = sticker.interactionData?.countdownTitle,
                  let targetAtMs = sticker.interactionData?.countdownTargetAtMs {
            StickerCountdownCardView(title: countdownTitle, targetAtMs: targetAtMs)
                .scaleEffect(sticker.scale)
                .rotationEffect(sticker.rotation)
        } else if sticker.type == .emojiSlider,
                  let sliderPrompt = sticker.interactionData?.sliderPrompt,
                  let sliderEmoji = sticker.interactionData?.sliderEmoji {
            InteractiveEmojiSliderSticker(
                prompt: sliderPrompt,
                emoji: sliderEmoji,
                storyId: storyId,
                userId: userId,
                stickerId: sticker.id
            )
            .frame(width: emojiSliderRenderingSize(prompt: sliderPrompt).width, height: emojiSliderRenderingSize(prompt: sliderPrompt).height)
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .audio, let audioURL = sticker.interactionData?.audioURL {
            InteractiveAudioStickerView(
                audioURL: audioURL,
                duration: sticker.interactionData?.audioDuration ?? 15.0
            )
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)
        } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {
            // ✅ WEATHER ANIMADO: Diseño animado según clima
            AnimatedWeatherSticker(
                weatherSymbol: weatherSymbol,
                temperature: sticker.interactionData?.questionText ?? "🌤️"
            )
            .frame(width: 140, height: 50)
            .scaleEffect(sticker.scale) // ✅ APLICAR ESCALA
            .rotationEffect(sticker.rotation)
            .onAppear {

            }
        } else if sticker.type == .time {
            StickerTimeCardView(
                timeText: sticker.interactionData?.questionText ?? Date.now.formatted(date: .omitted, time: .shortened),
                dateText: sticker.interactionData?.caption ?? Date.now.formatted(date: .numeric, time: .omitted)
            )
            .frame(width: 164, height: 56)
            .scaleEffect(sticker.scale)
            .rotationEffect(sticker.rotation)

        } else {
            // Solo imagen estática
            // Solo imagen estática
            Button(action: {
                handleStickerTap()
            }) {
                Image(uiImage: sticker.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: sticker.image.size.width * sticker.scale, height: sticker.image.size.height * sticker.scale)
                    .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            }
            .buttonStyle(PlainButtonStyle())
            .clipShape(RoundedRectangle(cornerRadius: 28 * sticker.scale))
            .rotationEffect(sticker.rotation)
        }
    }

    // ✅ MANEJAR TAP EN STICKERS
    private func handleStickerTap() {

        switch sticker.type {
        case .mention:
            if let interactionData = sticker.interactionData,
               let userId = interactionData.userId {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowUserProfileFromStory"), object: userId)
                }
            }

        case .poll:
            // ✅ ESTILO NATIVO: El poll es interactivo directamente, no necesita tap aquí
            break

        case .question:
            // ✅ ESTILO NATIVO: El question es interactivo directamente, no necesita tap aquí
            break

        case .hashtag:
            // ✅ ESTILO NATIVO: El hashtag es interactivo directamente, no necesita tap aquí
            break

        case .location:
            // ✅ ESTILO NATIVO: El location es interactivo directamente, no necesita tap aquí
            break

        case .link:
            if let rawURL = sticker.interactionData?.linkURL,
               let url = normalizedStickerURL(from: rawURL) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }

        case .countdown:
            break

        case .emojiSlider:
            break

        case .shareMoment:
            if let interactionData = sticker.interactionData,
               let momentId = interactionData.momentId,
               let userId = interactionData.userId {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenMomentFromStory"),
                        object: nil,
                        userInfo: ["momentId": momentId, "userId": userId]
                    )
                }
            }

        default:
            break
        }
    }

    // ✅ NUEVO: Manejar voto de poll directamente como Moments
    private func handlePollVote(option: Int, pollData: [String]) {
        // Guardar voto real en Firestore
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !storyId.isEmpty else { return }

        let pollVotesRef = Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("pollVotes").document(sticker.id)
            .collection("votes")

        // Verificar si ya votó
        pollVotesRef.document(currentUserId)
            .getDocument { snapshot, error in
                if let snapshot = snapshot, snapshot.exists {
                    if let option = snapshot.data()?["option"] as? Int {
                        DispatchQueue.main.async {
                            selectedPollOption = option
                            hasVoted = true
                        }
                    }
                    return
                }

                // Guardar voto
                let voteData: [String: Any] = [
                    "userId": currentUserId,
                    "option": option,
                    "timestamp": FieldValue.serverTimestamp()
                ]

                pollVotesRef.document(currentUserId)
                    .setData(voteData) { error in
                        if error == nil {
                            DispatchQueue.main.async {
                                hasVoted = true
                                // Actualizar votos localmente
                                voteCounts[option, default: 0] += 1
                                totalVotes += 1
                            }
                        } else {
                        }
                    }
            }
    }
}

// MARK: - ✅ STICKER INTERACTIVO DE QUESTIONS
struct InteractiveQuestionSticker: View {
    let questionText: String
    let storyId: String
    let userId: String
    let stickerId: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void

    @State private var showingResponseInput = false
    @State private var showingResponsesView = false
    @State private var responseText = ""
    @State private var responseCount = 0
    @State private var hasResponded = false
    @State private var isLoading = false
    @State private var isAuthor = false

    var body: some View {
        Button(action: {
            if isAuthor {
                // ✅ AUTOR: Ver respuestas
                showingResponsesView = true
            } else if !hasResponded {
                // ✅ ESPECTADOR: Responder
                showingResponseInput = true
            }
        }) {
            VStack(spacing: 14) {
                Text(questionText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Text(responseSubtitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.15))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .background(
                Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingResponseInput, onDismiss: {
            onResumeStory()
        }) {
            QuestionResponseInputView(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                stickerId: stickerId,
                onResponseSubmitted: { count in
                    responseCount = count
                    hasResponded = true
                    showingResponseInput = false
                    onResumeStory()
                }
            )
            .onAppear {
                onPauseStory()
            }
        }
        .sheet(isPresented: $showingResponsesView, onDismiss: {
            onResumeStory()
        }) {
            QuestionResponsesView(
                questionText: questionText,
                storyId: storyId,
                userId: userId,
                stickerId: stickerId
            )
            .onAppear {
                onPauseStory()
            }
        }
        .onAppear {
            loadResponseCount()
            checkIfUserHasResponded()
            checkIfUserIsAuthor()
        }
    }

    private var responseSubtitle: String {
        if isAuthor, responseCount > 0 {
            return String(format: NSLocalizedString("question.responses", comment: "Responses count"), responseCount)
        }

        if !isAuthor, hasResponded {
            return NSLocalizedString("question.alreadyAsked", comment: "Already asked")
        }

        return isAuthor
            ? NSLocalizedString("question.tapToSee", comment: "Tap to see questions")
            : NSLocalizedString("question.tapToAnswer", comment: "Tap to ask a question")
    }

    private func loadResponseCount() {
        questionResponsesCollection()
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    DispatchQueue.main.async {
                        self.responseCount = documents.count
                    }
                }
            }
    }

    private func checkIfUserHasResponded() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        questionResponsesCollection()
            .whereField("userId", isEqualTo: currentUserId)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    self.hasResponded = !(snapshot?.documents.isEmpty ?? true)
                }
            }
    }

    private func checkIfUserIsAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        DispatchQueue.main.async {
            self.isAuthor = currentUserId == userId
        }
    }

    private func questionResponsesCollection() -> CollectionReference {
        Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("questionResponses").document(stickerId)
            .collection("responses")
    }
}



// MARK: - ✅ VISTA DE ENTRADA DE RESPUESTA
struct QuestionResponseInputView: View {
    let questionText: String
    let storyId: String
    let userId: String
    let stickerId: String
    let onResponseSubmitted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var responseText = ""
    @State private var isLoading = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("question.answer.title")
                        .font(.custom("Poppins-SemiBold", size: 24))
                        .foregroundStyle(.primary)

                    Text("question.answer.subtitle")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Label("question.promptLabel", systemImage: "questionmark.bubble.fill")
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    Text(questionText)
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("question.yourAnswer")
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    TextField(NSLocalizedString("question.answerPlaceholder", comment: "Write your question"), text: $responseText, axis: .vertical)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .disabled(isLoading)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                Button(action: submitResponse) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.85)
                        }

                        Text("question.sendAnswer")
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isTextFieldFocused = true
        }
    }



    private func submitResponse() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true

        let response = QuestionResponse(
            userId: currentUserId,
            response: responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let responsesRef = Firestore.firestore()
            .collection("users").document(userId)
            .collection("stories").document(storyId)
            .collection("questionResponses").document(stickerId)
            .collection("responses")

        responsesRef.document(response.id).setData([
                "userId": response.userId,
                "response": response.response,
                "timestamp": Timestamp(date: response.timestamp),
                "isAnonymous": response.isAnonymous
            ]) { error in
                DispatchQueue.main.async {
                    isLoading = false
                    if error == nil {
                        // Actualizar contador de respuestas
                        responsesRef.getDocuments { snapshot, error in
                                let count = snapshot?.documents.count ?? 0
                                onResponseSubmitted(count)
                            }
                    } else {
                    }
                }
            }
    }
}

// MARK: - ✅ INTERACTIVE LOCATION STICKER
struct InteractiveLocationSticker: View {
    let locationName: String
    let coordinate: CLLocationCoordinate2D?
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void
    @State private var showingLocationMap = false

    var body: some View {
        Button(action: {
            onPauseStory() // ✅ PAUSAR HISTORIA
            showingLocationMap = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                Text(locationName.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Color.clear.liquidGlass(in: Capsule(style: .continuous))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingLocationMap) {
            LocationMapView(
                locationName: locationName,
                coordinate: coordinate,
                isPresented: $showingLocationMap
            )
        }
        .onChange(of: showingLocationMap) { _, isPresented in
            if !isPresented {
                onResumeStory() // ✅ REANUDAR HISTORIA CUANDO SE CIERRA
            }
        }
        .onAppear { }
    }
}

// MARK: - ✅ INTERACTIVE MENTION STICKER
struct InteractiveMentionSticker: View {
    let username: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text("@")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(0.7)

                Text(username.uppercased())
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Color.clear.liquidGlass(in: Capsule(style: .continuous))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ✅ INTERACTIVE HASHTAG STICKER
struct InteractiveHashtagSticker: View {
    let hashtag: String
    let onPauseStory: () -> Void
    let onResumeStory: () -> Void
    @State private var showingHashtagExplore = false

    var body: some View {
        Button(action: {
            onPauseStory() // ✅ PAUSAR HISTORIA
            showingHashtagExplore = true
        }) {
            StickerHashtagCardView(hashtag: hashtag)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingHashtagExplore) {
            ExploreView(initialSearchQuery: "#\(hashtag)", isDismissable: true)
        }
        .onChange(of: showingHashtagExplore) { _, isPresented in
            if !isPresented {
                onResumeStory() // ✅ REANUDAR HISTORIA CUANDO SE CIERRA
            }
        }
        .onAppear {
        }
    }
}
