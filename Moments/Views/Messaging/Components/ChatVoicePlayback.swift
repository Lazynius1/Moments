import Foundation
import AVFoundation
import Combine
import SwiftUI

// MARK: - Reproductor de notas de voz del chat

/// Chat del que viene la nota que suena: lo que muestra la barra cuando se sale de él.
struct ChatVoiceConversation: Equatable {
    let id: String
    let title: String
    let isGroup: Bool
    let otherUserId: String?
    let groupImage: String
}

struct ChatVoiceQueueItem {
    let messageId: String
    let url: URL
    let duration: Double
    let senderId: String
}

/// Un único reproductor para toda la app. Vive fuera de las celdas para que la nota siga
/// sonando aunque su burbuja salga de pantalla al hacer scroll (la lista recicla las celdas)
/// o se salga del chat. Las burbujas y las mini barras solo leen su estado.
@MainActor
final class ChatVoicePlaybackController: ObservableObject {
    static let shared = ChatVoicePlaybackController()

    @Published private(set) var activeMessageId: String?
    @Published private(set) var activeSenderId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playbackRate: Float = 1.0
    /// Si la burbuja de la nota activa está en pantalla. La mini barra solo aparece cuando no.
    @Published private(set) var isActiveBubbleVisible = true
    /// Chat de la nota activa y chat que está en pantalla ahora (nil fuera de los chats).
    @Published private(set) var activeConversation: ChatVoiceConversation?
    @Published private(set) var presentedConversationId: String?
    /// Quién envió la nota activa (para la barra de fuera en grupos).
    @Published private(set) var activeSenderName = ""

    /// La nota sigue sonando fuera de su chat: se muestra la barra de la lista de chats.
    var isPlayingOutsideChat: Bool {
        guard activeMessageId != nil, let activeConversation else { return false }
        return presentedConversationId != activeConversation.id
    }

    /// Los fija el chat en pantalla. Al empezar una nota desde ese chat pasan a ser los de la
    /// nota activa, así la cola sigue con las notas de su chat aunque luego se entre en otro.
    /// Devuelve la nota de voz que va justo después de un mensaje, si la hay.
    var nextVoiceNoteProvider: ((String) -> ChatVoiceQueueItem?)?
    /// Se llama al empezar una nota nueva (para preparar la siguiente).
    var onActiveMessageChanged: ((String) -> Void)?
    /// Nombre que se muestra para un remitente.
    var senderNameProvider: ((String) -> String)?
    private var presentedConversation: ChatVoiceConversation?
    private var activeNextProvider: ((String) -> ChatVoiceQueueItem?)?
    private var activeOnMessageChanged: ((String) -> Void)?
    private var activeSenderNameProvider: ((String) -> String)?
    /// La nota nueva viene de la cola (fin de la anterior), no de tocarla en el chat en pantalla.
    private var isAdvancingQueue = false

    private var player: AVAudioPlayer?
    private var playbackFileURL: URL?
    private let audioSession = MomentsAudioSessionLease()
    private var loadTask: Task<Void, Never>?
    private var timer: Timer?
    private let proximityManager = SimpleProximityManager()
    private var cancellables: Set<AnyCancellable> = []
    private var interruptionObserver: NSObjectProtocol?
    private var activeURL: URL?
    /// Pausa momentánea al cambiar altavoz/auricular: no es el final de la nota.
    private var isSwitchingRoute = false
    /// Posición guardada de las notas que se pausaron o se cambiaron por otra.
    private var savedPositions: [String: Double] = [:]
    private var visibleMessageIds: Set<String> = []

    private init() {
        proximityManager.$isNearEar
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isNear in
                MainActor.assumeIsolated { self?.switchAudioRoute(toEarpiece: isNear) }
            }
            .store(in: &cancellables)

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: MomentsAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    // MARK: Chat en pantalla

    /// Al entrar en un chat. Si suena una nota de otro chat, sigue sonando (con su barra arriba).
    func attach(_ conversation: ChatVoiceConversation) {
        presentedConversation = conversation
        presentedConversationId = conversation.id
        if activeConversation?.id == conversation.id { activeConversation = conversation }
    }

    /// Al salir del chat: la nota sigue sonando y la barra pasa a la lista de chats.
    func detach(conversationId: String) {
        guard presentedConversationId == conversationId else { return }
        presentedConversation = nil
        presentedConversationId = nil
    }

    // MARK: Estado por mensaje

    func isPlayingMessage(_ messageId: String) -> Bool {
        isPlaying && activeMessageId == messageId
    }

    func position(for messageId: String) -> Double {
        activeMessageId == messageId ? currentTime : (savedPositions[messageId] ?? 0)
    }

    // MARK: Controles

    func play(
        messageId: String,
        url: URL,
        duration knownDuration: Double,
        senderId: String,
        onFailure: @escaping () -> Void
    ) {
        if activeMessageId != messageId {
            switchActiveMessage(to: messageId, senderId: senderId, duration: knownDuration)
        }

        activeURL = url
        loadTask?.cancel()
        isPlaying = true
        let startTime = currentTime
        loadTask = Task { @MainActor in
            do {
                let playbackURL: URL
                if let playbackFileURL { playbackURL = playbackFileURL }
                else if url.isFileURL { playbackURL = url }
                else { playbackURL = try await PersistentAudioCache.shared.localURL(for: url) }
                guard !Task.isCancelled,
                      await configurePlaybackSession(speaker: !proximityManager.isNearEar),
                      !Task.isCancelled, isPlaying, activeMessageId == messageId else { return }
                let player = try self.player ?? AVAudioPlayer(contentsOf: playbackURL)
                player.enableRate = true
                player.rate = playbackRate
                player.currentTime = startTime
                guard player.prepareToPlay(), player.play() else {
                    stop()
                    return
                }
                playbackFileURL = playbackURL
                self.player = player
                if duration <= 0 { duration = player.duration }
                proximityManager.startMonitoring()
                startProgressTimer()
            } catch {
                guard !Task.isCancelled else { return }
                stop()
                onFailure()
            }
        }
    }

    /// Reanuda la nota activa (botón de la mini barra, sin burbuja en pantalla).
    func resume(messageId: String) {
        guard activeMessageId == messageId, let activeURL else { return }
        play(messageId: messageId, url: activeURL, duration: duration, senderId: activeSenderId ?? "", onFailure: {})
    }

    func pause() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        if let player { currentTime = player.currentTime }
        isPlaying = false
        stopProgressTimer()
        proximityManager.stopMonitoring()
        audioSession.deactivate()
    }

    /// Para y olvida la nota activa (cerrar la mini barra o salir del chat).
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        if let activeMessageId, let player, player.currentTime > 0.01 {
            savedPositions[activeMessageId] = player.currentTime
        }
        releasePlayer()
        activeMessageId = nil
        activeSenderId = nil
        activeConversation = nil
        activeSenderName = ""
        activeNextProvider = nil
        activeOnMessageChanged = nil
        activeSenderNameProvider = nil
        currentTime = 0
        duration = 0
        updateActiveBubbleVisibility()
    }

    /// Para y además olvida las posiciones guardadas (otro chat, cerrar sesión).
    func reset() {
        stop()
        savedPositions.removeAll()
    }

    func seek(messageId: String, to time: Double) {
        let clamped = max(0, time)
        if activeMessageId == messageId {
            currentTime = duration > 0 ? min(duration, clamped) : clamped
            player?.currentTime = currentTime
        } else {
            savedPositions[messageId] = clamped
            objectWillChange.send()
        }
    }

    func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0: playbackRate = 1.5
        case 1.5: playbackRate = 2.0
        default: playbackRate = 1.0
        }
        player?.rate = playbackRate
    }

    // MARK: Visibilidad de burbujas

    func bubbleAppeared(_ messageId: String) {
        visibleMessageIds.insert(messageId)
        updateActiveBubbleVisibility()
    }

    func bubbleDisappeared(_ messageId: String) {
        visibleMessageIds.remove(messageId)
        updateActiveBubbleVisibility()
    }

    // MARK: Privado

    private func switchActiveMessage(to messageId: String, senderId: String, duration knownDuration: Double) {
        if let previous = activeMessageId, let player {
            savedPositions[previous] = player.currentTime
        }
        releasePlayer()
        activeMessageId = messageId
        activeSenderId = senderId
        if !isAdvancingQueue, let presentedConversation {
            activeConversation = presentedConversation
            activeNextProvider = nextVoiceNoteProvider
            activeOnMessageChanged = onActiveMessageChanged
            activeSenderNameProvider = senderNameProvider
        }
        activeSenderName = activeSenderNameProvider?(senderId) ?? ""
        duration = knownDuration
        currentTime = savedPositions.removeValue(forKey: messageId) ?? 0
        if duration > 0, currentTime >= duration - 0.05 { currentTime = 0 }
        updateActiveBubbleVisibility()
        activeOnMessageChanged?(messageId)
    }

    private func releasePlayer() {
        player?.stop()
        player = nil
        playbackFileURL = nil
        activeURL = nil
        isPlaying = false
        stopProgressTimer()
        proximityManager.stopMonitoring()
        audioSession.deactivate()
    }

    private func finishPlayback() {
        let finishedMessageId = activeMessageId
        if let finishedMessageId { savedPositions.removeValue(forKey: finishedMessageId) }

        // Si el siguiente mensaje también es una nota de voz, la reproducción sigue con ella.
        if let finishedMessageId,
           let next = activeNextProvider?(finishedMessageId),
           next.messageId != finishedMessageId {
            savedPositions.removeValue(forKey: next.messageId)
            releasePlayer()
            isAdvancingQueue = true
            play(messageId: next.messageId, url: next.url, duration: next.duration, senderId: next.senderId, onFailure: {})
            isAdvancingQueue = false
            return
        }

        releasePlayer()
        activeMessageId = nil
        activeSenderId = nil
        activeConversation = nil
        activeSenderName = ""
        currentTime = 0
        duration = 0
        updateActiveBubbleVisibility()
    }

    private func updateActiveBubbleVisibility() {
        let visible = activeMessageId.map { visibleMessageIds.contains($0) } ?? true
        if visible != isActiveBubbleVisible { isActiveBubbleVisible = visible }
    }

    private func configurePlaybackSession(speaker: Bool) async -> Bool {
        await audioSession.activate(
            category: speaker ? .playback : .playAndRecord,
            mode: speaker ? .default : .voiceChat,
            options: speaker ? [] : [.allowBluetoothHFP]
        )
    }

    /// Cambia altavoz / auricular durante la reproducción (usa el archivo, no `player.data`).
    private func switchAudioRoute(toEarpiece: Bool) {
        guard let player, isPlaying else { return }
        isSwitchingRoute = true
        player.pause()
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            defer { isSwitchingRoute = false }
            guard await configurePlaybackSession(speaker: !toEarpiece),
                  !Task.isCancelled, isPlaying else { return }
            player.play()
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                if player.isPlaying {
                    self.currentTime = player.currentTime
                } else if self.isPlaying, !self.isSwitchingRoute {
                    self.finishPlayback()
                }
            }
        }
        // `.common`: el progreso sigue avanzando mientras el usuario hace scroll.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Mini barra «reproduciendo»

/// Barra compacta de la nota de voz que suena (o está en pausa).
/// - En el chat (`avatar == nil`): arriba, cuando la burbuja no está en pantalla.
/// - Fuera del chat: sobre la lista de chats, con la foto del chat delante.
/// Tocar el nombre (o la foto) lleva al mensaje.
struct ChatVoiceMiniPlayerBar: View {
    @ObservedObject var playback: ChatVoicePlaybackController
    let senderName: String
    var subtitlePrefix: String?
    let adaptiveColors: AdaptiveColors
    var avatar: AnyView?
    let onTap: () -> Void

    @Environment(\.chatOutgoingBubbleColor) private var bubbleColor

    /// Mismo color que las burbujas enviadas del chat, con el texto legible encima (≡ burbuja).
    private var onBubble: Color { chatBubbleTextColor(for: bubbleColor) }

    private var progress: Double {
        guard playback.duration > 0 else { return 0 }
        return min(1, max(0, playback.currentTime / playback.duration))
    }

    private var speedLabel: String {
        switch playback.playbackRate {
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default: return "1×"
        }
    }

    private var timeLabel: String {
        let time = "\(formatTime(playback.currentTime)) / \(formatTime(playback.duration))"
        guard let subtitlePrefix, !subtitlePrefix.isEmpty else { return time }
        return "\(subtitlePrefix) · \(time)"
    }

    var body: some View {
        HStack(spacing: avatar == nil ? 12 : 10) {
            if let avatar {
                avatar
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(onBubble.opacity(0.35), lineWidth: 1.5))
                    .contentShape(Circle())
                    .onTapGesture(perform: onTap)
                    .accessibilityHidden(true)
            } else {
                playPauseButton
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(senderName)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundStyle(onBubble)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(onBubble.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("chat.voice.miniPlayer.jump"))

            if avatar != nil { playPauseButton }

            Button(action: playback.cyclePlaybackRate) {
                Text(speedLabel)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(onBubble)
                    .frame(width: 38)
                    .padding(.vertical, 5)
                    .background(onBubble.opacity(0.16))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: playback.stop) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(onBubble.opacity(0.72))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chat.voice.miniPlayer.close"))
        }
        .padding(.leading, avatar == nil ? 6 : 8)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .momentsChromeGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            style: .tinted,
            tint: bubbleColor.opacity(0.9)
        )
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(onBubble.opacity(0.85))
                    .frame(width: proxy.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
        }
    }

    private var playPauseButton: some View {
        Button {
            if playback.isPlaying {
                playback.pause()
            } else if let messageId = playback.activeMessageId {
                playback.resume(messageId: messageId)
            }
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(onBubble)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playback.isPlaying
            ? NSLocalizedString("chat.voice.pause", comment: "Pause voice note")
            : NSLocalizedString("chat.voice.play", comment: "Play voice note")))
    }

    private func formatTime(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Barra fuera del chat

/// Mientras sigue sonando una nota de un chat del que se ha salido: sobre la lista de chats
/// y arriba de cualquier otro chat. Desaparece al volver a ese chat (allí manda su mini barra).
struct ChatVoiceOutsideChatHost: View {
    @ObservedObject private var playback = ChatVoicePlaybackController.shared
    /// Abre el chat (`conversationId`) y salta a la nota (`messageId`).
    let onOpen: (String, String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if playback.isPlayingOutsideChat,
               let conversation = playback.activeConversation,
               let messageId = playback.activeMessageId {
                ChatVoiceMiniPlayerBar(
                    playback: playback,
                    senderName: conversation.title,
                    subtitlePrefix: conversation.isGroup ? playback.activeSenderName : nil,
                    adaptiveColors: AdaptiveColors(colorScheme: colorScheme),
                    avatar: AnyView(avatar(for: conversation)),
                    onTap: { onOpen(conversation.id, messageId) }
                )
                .environment(\.chatOutgoingBubbleColor, ChatWallpaper.cachedBubbleColor(conversationId: conversation.id))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : MotionPolicy.Spring.header, value: playback.isPlayingOutsideChat)
    }

    @ViewBuilder
    private func avatar(for conversation: ChatVoiceConversation) -> some View {
        if conversation.isGroup {
            GroupChatAvatar(name: conversation.title, image: conversation.groupImage, size: 34)
        } else if let userId = conversation.otherUserId, !userId.isEmpty {
            AsyncProfileImageView(userId: userId)
        } else {
            ProfileUnavailableAvatar(size: 34)
        }
    }
}
