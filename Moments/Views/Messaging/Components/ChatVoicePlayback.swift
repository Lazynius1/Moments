import Foundation
import AVFoundation
import Combine
import SwiftUI

// MARK: - Reproductor de notas de voz del chat

struct ChatVoiceQueueItem {
    let messageId: String
    let url: URL
    let duration: Double
    let senderId: String
}

/// Un único reproductor para todo el chat. Vive fuera de las celdas para que la nota siga
/// sonando aunque su burbuja salga de pantalla al hacer scroll (la lista recicla las celdas).
/// Las burbujas y la mini barra solo leen su estado.
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

    /// Lo fija el chat: devuelve la nota de voz que va justo después de un mensaje, si la hay.
    var nextVoiceNoteProvider: ((String) -> ChatVoiceQueueItem?)?
    /// Lo fija el chat: se llama al empezar una nota nueva (para preparar la siguiente).
    var onActiveMessageChanged: ((String) -> Void)?

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
        currentTime = 0
        duration = 0
        updateActiveBubbleVisibility()
    }

    /// Al salir del chat: además de parar, se olvidan las posiciones guardadas.
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
        duration = knownDuration
        currentTime = savedPositions.removeValue(forKey: messageId) ?? 0
        if duration > 0, currentTime >= duration - 0.05 { currentTime = 0 }
        updateActiveBubbleVisibility()
        onActiveMessageChanged?(messageId)
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

        // Como WhatsApp: si el siguiente mensaje también es una nota de voz, sigue con ella.
        if let finishedMessageId,
           let next = nextVoiceNoteProvider?(finishedMessageId),
           next.messageId != finishedMessageId {
            savedPositions.removeValue(forKey: next.messageId)
            releasePlayer()
            play(messageId: next.messageId, url: next.url, duration: next.duration, senderId: next.senderId, onFailure: {})
            return
        }

        releasePlayer()
        activeMessageId = nil
        activeSenderId = nil
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

/// Barra compacta arriba del chat mientras suena (o está en pausa) una nota de voz
/// cuya burbuja no está en pantalla. Tocarla lleva al mensaje.
struct ChatVoiceMiniPlayerBar: View {
    @ObservedObject var playback: ChatVoicePlaybackController
    let senderName: String
    let adaptiveColors: AdaptiveColors
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if playback.isPlaying {
                    playback.pause()
                } else if let messageId = playback.activeMessageId {
                    playback.resume(messageId: messageId)
                }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(adaptiveColors.userAccentColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(playback.isPlaying
                ? NSLocalizedString("chat.voice.pause", comment: "Pause voice note")
                : NSLocalizedString("chat.voice.play", comment: "Play voice note")))

            VStack(alignment: .leading, spacing: 2) {
                Text(senderName)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundStyle(adaptiveColors.messageTextColor)
                    .lineLimit(1)
                Text("\(formatTime(playback.currentTime)) / \(formatTime(playback.duration))")
                    .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(adaptiveColors.timestampColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("chat.voice.miniPlayer.jump"))

            Button(action: playback.cyclePlaybackRate) {
                Text(speedLabel)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(adaptiveColors.messageTextColor)
                    .frame(width: 38)
                    .padding(.vertical, 5)
                    .background(adaptiveColors.messageTextColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: playback.stop) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(adaptiveColors.messageTextColor.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("chat.voice.miniPlayer.close"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(adaptiveColors.messageBubbleBackground)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(adaptiveColors.userAccentColor)
                    .frame(width: proxy.size.width * progress, height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, y: 4)
    }

    private func formatTime(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
