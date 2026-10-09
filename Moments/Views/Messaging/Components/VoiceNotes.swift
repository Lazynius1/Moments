import Foundation
import AVFoundation
import UIKit
import SwiftUI

struct RecordedVoiceNote {
    let data: Data
    let waveform: [Float]
}

struct VoiceRecordingSegment {
    let recording: RecordedVoiceNote
    let duration: TimeInterval
}

struct VoiceRecordingDraft {
    var segments: [VoiceRecordingSegment]
    var recording: RecordedVoiceNote?
    var trimRange: Range<TimeInterval>? = nil

    var fullDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    var duration: TimeInterval {
        normalizedTrimRange.map { $0.upperBound - $0.lowerBound } ?? fullDuration
    }

    var normalizedTrimRange: Range<TimeInterval>? {
        guard let trimRange, fullDuration > 0 else { return nil }
        let lowerBound = min(fullDuration, max(0, trimRange.lowerBound))
        let upperBound = min(fullDuration, max(lowerBound, trimRange.upperBound))
        guard upperBound > lowerBound else { return nil }
        return lowerBound..<upperBound
    }

    var waveform: [Float] {
        recording?.waveform ?? ChatVoiceWaveformSamples.resampled(
            segments.flatMap(\.recording.waveform),
            count: ChatVoiceWaveformSamples.storedSampleCount
        )
    }
}

enum VoiceRecordingComposer {
    static func compose(_ segments: [VoiceRecordingSegment]) async -> RecordedVoiceNote? {
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 {
            return segments[0].recording
        }

        let fileManager = FileManager.default
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        var temporaryURLs: [URL] = []
        defer {
            for url in temporaryURLs {
                try? fileManager.removeItem(at: url)
            }
        }

        var insertionTime = CMTime.zero
        do {
            for segment in segments {
                let segmentURL = fileManager.temporaryDirectory
                    .appendingPathComponent("voice_segment_\(UUID().uuidString).m4a")
                try segment.recording.data.write(to: segmentURL, options: .atomic)
                temporaryURLs.append(segmentURL)

                let asset = AVURLAsset(url: segmentURL)
                guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    return nil
                }
                let duration = try await asset.load(.duration)
                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: insertionTime
                )
                insertionTime = CMTimeAdd(insertionTime, duration)
            }

            let outputURL = fileManager.temporaryDirectory
                .appendingPathComponent("voice_composed_\(UUID().uuidString).m4a")
            temporaryURLs.append(outputURL)
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ) else { return nil }

            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            exporter.shouldOptimizeForNetworkUse = true
            try await exporter.export(to: outputURL, as: .m4a)
            let data = try Data(contentsOf: outputURL)
            guard !data.isEmpty else { return nil }

            return RecordedVoiceNote(
                data: data,
                waveform: ChatVoiceWaveformSamples.resampled(
                    segments.flatMap(\.recording.waveform),
                    count: ChatVoiceWaveformSamples.storedSampleCount
                )
            )
        } catch {
            return nil
        }
    }

    static func trim(
        _ recording: RecordedVoiceNote,
        fullDuration: TimeInterval,
        to requestedRange: Range<TimeInterval>?
    ) async -> VoiceRecordingSegment? {
        guard fullDuration > 0 else { return nil }
        guard let requestedRange else {
            return VoiceRecordingSegment(recording: recording, duration: fullDuration)
        }

        let lowerBound = min(fullDuration, max(0, requestedRange.lowerBound))
        let upperBound = min(fullDuration, max(lowerBound, requestedRange.upperBound))
        let trimmedDuration = upperBound - lowerBound
        guard trimmedDuration > 0 else { return nil }

        let tolerance = 0.025
        if lowerBound <= tolerance, upperBound >= fullDuration - tolerance {
            return VoiceRecordingSegment(recording: recording, duration: fullDuration)
        }

        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory
            .appendingPathComponent("voice_trim_source_\(UUID().uuidString).m4a")
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("voice_trimmed_\(UUID().uuidString).m4a")
        defer {
            try? fileManager.removeItem(at: sourceURL)
            try? fileManager.removeItem(at: outputURL)
        }

        do {
            try recording.data.write(to: sourceURL, options: .atomic)
            let asset = AVURLAsset(url: sourceURL)
            let assetDuration = try await asset.load(.duration).seconds
            let exportLowerBound = min(assetDuration, lowerBound)
            let exportUpperBound = min(assetDuration, max(exportLowerBound, upperBound))
            let exportDuration = exportUpperBound - exportLowerBound
            guard exportDuration > 0 else { return nil }
            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else { return nil }

            let start = CMTime(seconds: exportLowerBound, preferredTimescale: 600)
            let duration = CMTime(seconds: exportDuration, preferredTimescale: 600)
            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            exporter.shouldOptimizeForNetworkUse = true
            exporter.timeRange = CMTimeRange(start: start, duration: duration)
            try await exporter.export(to: outputURL, as: .m4a)

            let data = try Data(contentsOf: outputURL)
            guard !data.isEmpty else { return nil }
            let waveform = ChatVoiceWaveformSamples.cropped(
                recording.waveform,
                fullDuration: fullDuration,
                range: exportLowerBound..<exportUpperBound
            )
            return VoiceRecordingSegment(
                recording: RecordedVoiceNote(data: data, waveform: waveform),
                duration: exportDuration
            )
        } catch {
            return nil
        }
    }
}

enum ChatVoiceWaveformSamples {
    static let storedSampleCount = 48

    static func resampled(_ source: [Float], count: Int) -> [Float] {
        guard count > 0, !source.isEmpty else { return [] }
        return (0..<count).map { index in
            let lower = index * source.count / count
            let upper = max(lower + 1, (index + 1) * source.count / count)
            let slice = source[lower..<min(upper, source.count)]
            let average = slice.reduce(Float.zero, +) / Float(max(slice.count, 1))
            let peak = slice.max() ?? average
            return min(1, max(0.12, average * 0.7 + peak * 0.3))
        }
    }

    static func cropped(
        _ source: [Float],
        fullDuration: TimeInterval,
        range: Range<TimeInterval>
    ) -> [Float] {
        guard !source.isEmpty, fullDuration > 0 else { return [] }
        let lowerFraction = min(1, max(0, range.lowerBound / fullDuration))
        let upperFraction = min(1, max(lowerFraction, range.upperBound / fullDuration))
        let lowerIndex = min(source.count - 1, Int(floor(lowerFraction * Double(source.count))))
        let upperIndex = min(source.count, max(lowerIndex + 1, Int(ceil(upperFraction * Double(source.count)))))
        return resampled(
            Array(source[lowerIndex..<upperIndex]),
            count: storedSampleCount
        )
    }
}

// MARK: - Audio Recording Manager
final class AudioRecordingManager: NSObject, ObservableObject {
    static let shared = AudioRecordingManager()

    @Published var audioPower: Float = 0.0

    private var powerTimer: Timer?
    private var audioRecorder: AVAudioRecorder?
    private let audioSession = MomentsAudioSessionLease()
    private var recordingStartTask: Task<Void, Never>?
    private var recordingGeneration = UUID()
    private var recordingURL: URL?
    private var recordedPowerLevels: [Float] = []
    private var stopCompletion: ((RecordedVoiceNote?) -> Void)?

    private override init() {
        super.init()
    }

    /// Si el micrófono ya está autorizado, `completion(true)` se llama sin mostrar diálogo.
    func startRecording(completion: @escaping (Bool) -> Void) {
        recordingStartTask?.cancel()
        recordingGeneration = UUID()
        let generation = recordingGeneration
        requestMicrophonePermission { [weak self] granted in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard granted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.recordingStartTask = Task { @MainActor in
                guard self.recordingGeneration == generation else { completion(false); return }
                let activated = await self.audioSession.activate(
                    category: .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetoothHFP]
                )
                await MainActor.run {
                    guard !Task.isCancelled, self.recordingGeneration == generation else { completion(false); return }
                    let started = activated && self.beginRecording()
                    if !started { self.audioSession.deactivate() }
                    completion(started)
                }
            }
        }
    }

    func stopRecording(completion: @escaping (RecordedVoiceNote?) -> Void) {
        recordingGeneration = UUID()
        recordingStartTask?.cancel()
        recordingStartTask = nil
        powerTimer?.invalidate()
        powerTimer = nil
        audioPower = 0.0

        guard let recorder = audioRecorder, recorder.isRecording else {
            audioSession.deactivate()
            completion(nil)
            return
        }

        stopCompletion = completion
        recorder.stop()
    }

    // MARK: - Private

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        @unknown default:
            completion(false)
        }
    }

    private func beginRecording() -> Bool {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_voice_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: fileURL)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                return false
            }
            audioRecorder = recorder
            recordingURL = fileURL
            recordedPowerLevels.removeAll(keepingCapacity: true)
            startPowerMonitoring()
            return true
        } catch {
            return false
        }
    }

    private func startPowerMonitoring() {
        powerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let decibels = recorder.averagePower(forChannel: 0)
            let level = self.normalizedPowerLevel(fromDecibels: decibels)
            DispatchQueue.main.async {
                self.recordedPowerLevels.append(level)
                self.audioPower = Float(level)
            }
        }
    }

    private func normalizedPowerLevel(fromDecibels decibels: Float) -> Float {
        if decibels < -60.0 { return 0.0 }
        if decibels >= 0.0 { return 1.0 }
        return (decibels + 60.0) / 60.0
    }

    private func deliverRecordingResult(success: Bool) {
        powerTimer?.invalidate()
        powerTimer = nil
        audioSession.deactivate()
        let completion = stopCompletion
        stopCompletion = nil
        audioRecorder = nil

        guard success, let url = recordingURL else {
            recordingURL = nil
            recordedPowerLevels.removeAll(keepingCapacity: false)
            completion?(nil)
            return
        }

        defer { recordingURL = nil }
        let data = try? Data(contentsOf: url)
        if let data, data.count > 512 {
            let waveform = ChatVoiceWaveformSamples.resampled(
                recordedPowerLevels,
                count: ChatVoiceWaveformSamples.storedSampleCount
            )
            completion?(RecordedVoiceNote(data: data, waveform: waveform))
        } else {
            completion?(nil)
        }
        recordedPowerLevels.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: url)
    }
}

extension AudioRecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        deliverRecordingResult(success: flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        deliverRecordingResult(success: false)
    }
}

// MARK: - Simple Proximity Manager (Limpio)
class SimpleProximityManager: ObservableObject {
    @Published var isNearEar = false
    private var wasProximityEnabled = false
    
    func startMonitoring() {
        wasProximityEnabled = UIDevice.current.isProximityMonitoringEnabled
        UIDevice.current.isProximityMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        UIDevice.current.isProximityMonitoringEnabled = wasProximityEnabled
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func proximityChanged() {
        isNearEar = UIDevice.current.proximityState
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Voice message spacing

enum VoiceMessageLayout {
    // Barras genéricas (editor de música, sticker de voz, compositor).
    static let barWidth: CGFloat = 3.5
    static let barSpacing: CGFloat = 2.5
    static let waveformHeight: CGFloat = 30

    // Tarjeta del chat: ancho máximo de burbuja; la fila (play, onda, velocidad) va centrada
    // en vertical y el tiempo ocupa la franja inferior sin descentrarla.
    static let horizontalPadding: CGFloat = 12
    /// Fila central: play, onda y velocidad comparten este centro vertical.
    static let rowHeight: CGFloat = 24
    static let timeLabelHeight: CGFloat = 13
    /// Margen igual arriba y abajo de la fila; abajo aloja el tiempo.
    static let rowVerticalInset: CGFloat = 19
    static let timeBottomInset: CGFloat = 4
    static let cardHeight: CGFloat = rowVerticalInset * 2 + rowHeight

    static let playButtonWidth: CGFloat = 28
    static let playIconSize: CGFloat = 22
    /// Zona táctil mínima del play y del arrastre de la onda.
    static let minTouchTarget: CGFloat = 44
    static let outerSpacing: CGFloat = 10
    static let speedControlWidth: CGFloat = 34

    static let cardBarWidth: CGFloat = 2.5
    static let cardBarSpacing: CGFloat = 2
    static let cardBarMaxHeight: CGFloat = 22
    static let cardBarMinHeight: CGFloat = 3
    static let progressHeadSize: CGFloat = 11

    /// Mismo ancho máximo que una burbuja de texto del chat.
    static func bubbleWidth(containerWidth: CGFloat, isOutgoing: Bool = true) -> CGFloat {
        ChatBubbleLayoutWidth.capped(
            ChatBubbleLayoutWidth.maxTextBubbleWidth(chatListWidth: containerWidth),
            chatListWidth: containerWidth,
            gutter: isOutgoing ? 64 : 88
        )
    }

    /// Inicio horizontal de la onda dentro del contenido (para alinear el tiempo).
    static var waveformLeadingOffset: CGFloat {
        playButtonWidth + outerSpacing
    }

    static func availableWaveformWidth(containerWidth: CGFloat, includesSpeedControl: Bool, isOutgoing: Bool = true) -> CGFloat {
        let innerWidth = bubbleWidth(containerWidth: containerWidth, isOutgoing: isOutgoing) - horizontalPadding * 2
        let trailingBlock = includesSpeedControl ? outerSpacing + speedControlWidth : 0
        return max(80, innerWidth - waveformLeadingOffset - trailingBlock)
    }

    static func waveformBarCount(for trackWidth: CGFloat) -> Int {
        let unit = cardBarWidth + cardBarSpacing
        guard unit > 0 else { return 32 }
        return max(16, min(60, Int(((trackWidth + cardBarSpacing) / unit).rounded(.down))))
    }

    static func waveformTrackWidth(containerWidth: CGFloat, includesSpeedControl: Bool, isOutgoing: Bool = true) -> CGFloat {
        let target = availableWaveformWidth(
            containerWidth: containerWidth,
            includesSpeedControl: includesSpeedControl,
            isOutgoing: isOutgoing
        )
        let barCount = waveformBarCount(for: target)
        return CGFloat(barCount) * cardBarWidth + CGFloat(max(barCount - 1, 0)) * cardBarSpacing
    }
}

enum ChatVoiceWaveformGenerator {
    static func levels(seed: String, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var hash = seed.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        return (0..<count).map { index in
            hash = hash &* 1_103_515_245 &+ 12_345 &+ UInt64(index)
            let normalized = Float(hash % 10_000) / 10_000
            return 0.2 + normalized * 0.6
        }
    }
}

// MARK: - Waveform Visualization Components

struct VisualWaveformView: View {
    let levels: [Float]
    let color: Color
    let activeColor: Color
    let progress: Double
    var height: CGFloat = VoiceMessageLayout.waveformHeight
    var barWidth: CGFloat = VoiceMessageLayout.barWidth
    var spacing: CGFloat = VoiceMessageLayout.barSpacing
    var minBarHeight: CGFloat = 6

    var body: some View {
        // Alineación central del HStack: barras simétricas respecto a la línea media.
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<levels.count, id: \.self) { index in
                let level = levels[index]
                let isActive = Double(index) / Double(levels.count) <= progress

                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(isActive ? activeColor : color)
                    .frame(width: barWidth, height: max(minBarHeight, CGFloat(level) * height))
                    .animation(.easeInOut(duration: 0.1), value: isActive)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: level), value: level)
            }
        }
    }
}

struct LiveWaveformView: View {
    @ObservedObject var manager = AudioRecordingManager.shared
    @State private var levels: [Float] = Array(repeating: 0.1, count: 20)
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: max(4, CGFloat(levels[index]) * 35))
            }
        }
        .onReceive(manager.$audioPower) { power in
            withAnimation(.linear(duration: 0.05)) {
                levels.removeFirst()
                levels.append(power)
            }
        }
    }
}

// MARK: - Audio Message con Proximidad Simple
struct GlassmorphicAudioMessage: View {
    let messageId: String
    let audioUrl: String?
    let duration: Double
    let waveformSamples: [Float]?
    let isCurrentUser: Bool
    let isSending: Bool
    let progress: Double?
    let adaptiveColors: AdaptiveColors
    var groupPosition: ChatMessageGroupPosition = .single
    var senderId: String = ""

    /// El reproductor vive fuera de la celda: la nota sigue sonando al hacer scroll.
    @ObservedObject private var playback = ChatVoicePlaybackController.shared
    @State private var isAudioAvailable = true
    @State private var isCheckingAvailability = true
    @State private var showErrorMessage = false
    @State private var isScrubbing = false
    @State private var scrubFraction: Double?
    @State private var wasPlayingBeforeScrub = false
    @State private var waveformLevels: [Float] = ChatVoiceWaveformGenerator.levels(
        seed: "voice",
        count: VoiceMessageLayout.waveformBarCount(
            for: VoiceMessageLayout.waveformTrackWidth(containerWidth: 393, includesSpeedControl: true)
        )
    )

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.chatOutgoingBubbleColor) private var chatOutgoingBubbleColor
    @Environment(\.chatListContainerWidth) private var chatListContainerWidth

    private var layoutContainerWidth: CGFloat {
        ChatBubbleLayoutWidth.containerWidth(chatListWidth: chatListContainerWidth)
    }

    private var isPlaying: Bool {
        playback.isPlayingMessage(messageId)
    }

    private var currentTime: Double {
        playback.position(for: messageId)
    }

    private var playbackRate: Float {
        playback.playbackRate
    }

    /// Tuyos: mismo color sólido saliente que el texto. Del otro: glass como el resto.
    private var contentColor: Color {
        if isCurrentUser {
            return chatBubbleTextColor(for: chatOutgoingBubbleColor)
        }
        return adaptiveColors.messageTextColor
    }

    /// Progreso reproducido: en recibidos, el color del chat legible sobre la burbuja.
    private var accentColor: Color {
        if isCurrentUser {
            return contentColor
        }
        return adaptiveColors.receivedAccent(from: chatOutgoingBubbleColor)
    }

    /// Play/pausa y velocidad: en recibidos, gris neutro secundario.
    private var controlColor: Color {
        if isCurrentUser {
            return contentColor
        }
        return adaptiveColors.messageTextColor.opacity(colorScheme == .dark ? 0.7 : 0.6)
    }

    private var waveformInactiveColor: Color {
        if isCurrentUser {
            return contentColor.opacity(colorScheme == .dark ? 0.22 : 0.28)
        }
        return adaptiveColors.primary.opacity(colorScheme == .dark ? 0.28 : 0.22)
    }

    private var durationLabelColor: Color {
        if isCurrentUser {
            return contentColor.opacity(0.9)
        }
        return adaptiveColors.timestampColor
    }

    private var bubbleStrokeColor: Color {
        if isCurrentUser {
            return contentColor.opacity(0.12)
        }
        return adaptiveColors.messageBubbleStroke
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            side: isCurrentUser ? .trailing : .leading,
            position: groupPosition,
            cornerRadius: 18,
            joinedRadius: ChatTextBubbleMetrics.joinedRadius
        )
    }

    private var showsSpeedControl: Bool {
        !isSending && duration >= 8
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isCurrentUser {
            bubbleShape
                .fill(chatOutgoingBubbleColor)
        } else {
            bubbleShape
                .fill(adaptiveColors.messageBubbleBackground)
                .background(
                    bubbleShape
                        .fill(.ultraThinMaterial)
                )
        }
    }

    var body: some View {
        // Fila central: play, onda y velocidad centrados en la misma línea, y la fila centrada en la tarjeta.
        HStack(alignment: .center, spacing: VoiceMessageLayout.outerSpacing) {
                playButton

                if isCheckingAvailability {
                    loadingWaveformPlaceholder
                    Spacer(minLength: 0)
                } else if isAudioAvailable {
                    scrubbableWaveform
                    Spacer(minLength: 0)
                    if showsSpeedControl {
                        speedButton
                    }
                } else {
                    unavailableRow
                    Spacer(minLength: 0)
                }
            }
        .frame(height: VoiceMessageLayout.rowHeight)
        .padding(.horizontal, VoiceMessageLayout.horizontalPadding)
        .padding(.vertical, VoiceMessageLayout.rowVerticalInset)
        .overlay(alignment: .bottomLeading) {
            bottomLabel
                .frame(height: VoiceMessageLayout.timeLabelHeight, alignment: .leading)
                .padding(.leading, VoiceMessageLayout.horizontalPadding + VoiceMessageLayout.waveformLeadingOffset)
                .padding(.bottom, VoiceMessageLayout.timeBottomInset)
                .allowsHitTesting(false)
        }
        .frame(width: VoiceMessageLayout.bubbleWidth(containerWidth: layoutContainerWidth, isOutgoing: isCurrentUser), alignment: .leading)
        .background(bubbleBackground)
        // Misma forma que el relleno para que el borde siga las esquinas unidas.
        .overlay(bubbleShape.stroke(bubbleStrokeColor, lineWidth: 0.5))
        .onAppear {
            playback.bubbleAppeared(messageId)
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        .onChange(of: audioUrl) { _, _ in
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        .onChange(of: isSending) { _, _ in
            refreshWaveformLevels()
            checkAudioAvailability()
        }
        // Salir de pantalla no para el audio: solo avisa para mostrar la mini barra.
        .onDisappear {
            playback.bubbleDisappeared(messageId)
        }
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            ZStack {
                if isCheckingAvailability {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(controlColor)
                } else {
                    Image(systemName: getPlayButtonIcon())
                        .font(.system(size: VoiceMessageLayout.playIconSize, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }

                if isSending, let uploadProgress = progress {
                    MediaProgressRing(progress: uploadProgress, size: 30, lineWidth: 2)
                }
            }
            .foregroundStyle(controlColor)
            // Zona táctil de 44 pt aunque el hueco visual sea de 28 × 24.
            .frame(width: VoiceMessageLayout.minTouchTarget, height: VoiceMessageLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, -(VoiceMessageLayout.minTouchTarget - VoiceMessageLayout.playButtonWidth) / 2)
        .padding(.vertical, -(VoiceMessageLayout.minTouchTarget - VoiceMessageLayout.rowHeight) / 2)
        .disabled(!isAudioAvailable || isCheckingAvailability)
        .accessibilityLabel(Text(isPlaying
            ? NSLocalizedString("chat.voice.pause", comment: "Pause voice note")
            : NSLocalizedString("chat.voice.play", comment: "Play voice note")))
    }

    private var waveformTrackWidth: CGFloat {
        VoiceMessageLayout.waveformTrackWidth(containerWidth: layoutContainerWidth, includesSpeedControl: showsSpeedControl, isOutgoing: isCurrentUser)
    }

    private var loadingWaveformPlaceholder: some View {
        let trackWidth = waveformTrackWidth
        let barCount = VoiceMessageLayout.waveformBarCount(for: trackWidth)

        return HStack(alignment: .center, spacing: VoiceMessageLayout.cardBarSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule(style: .continuous)
                    .fill(waveformInactiveColor)
                    .frame(width: VoiceMessageLayout.cardBarWidth, height: VoiceMessageLayout.cardBarMinHeight + 1)
            }
        }
        .frame(width: trackWidth, height: VoiceMessageLayout.rowHeight)
    }

    /// Onda + cabezal arrastrable. El cabezal va sobre la línea media, en `displayedProgress`.
    private var scrubbableWaveform: some View {
        let trackWidth = waveformTrackWidth
        let headSize = VoiceMessageLayout.progressHeadSize
        let touchHeight = VoiceMessageLayout.minTouchTarget

        return ZStack(alignment: .leading) {
            VisualWaveformView(
                levels: waveformLevels,
                color: waveformInactiveColor,
                activeColor: accentColor,
                progress: displayedProgress,
                height: VoiceMessageLayout.cardBarMaxHeight,
                barWidth: VoiceMessageLayout.cardBarWidth,
                spacing: VoiceMessageLayout.cardBarSpacing,
                minBarHeight: VoiceMessageLayout.cardBarMinHeight
            )
            .frame(width: trackWidth, height: touchHeight, alignment: .leading)

            Circle()
                .fill(accentColor)
                .frame(width: headSize, height: headSize)
                .scaleEffect(isScrubbing ? 1.25 : 1)
                .offset(x: trackWidth * CGFloat(displayedProgress) - headSize / 2)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isScrubbing), value: isScrubbing)
        }
        .frame(width: trackWidth, height: touchHeight, alignment: .leading)
        .contentShape(Rectangle())
        // Toque: salta directamente a ese punto.
        .onTapGesture(coordinateSpace: .local) { location in
            seekToFraction(fraction(forX: location.x, trackWidth: trackWidth))
        }
        // Arrastre: el progreso visual sigue al dedo y el seek se aplica al soltar.
        .gesture(
            ChatHorizontalPanGesture(
                direction: .both,
                onChanged: { value in
                    if !isScrubbing {
                        beginScrub()
                    }
                    scrubFraction = fraction(forX: value.location.x, trackWidth: trackWidth)
                },
                onEnded: { _, _ in
                    endScrub()
                }
            )
        )
        // Mantiene la fila en 24 pt; la zona táctil de 44 pt desborda en vertical.
        .padding(.vertical, -(touchHeight - VoiceMessageLayout.rowHeight) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("chat.audio.scrub.accessibility"))
        .accessibilityValue(Text(String(
            format: NSLocalizedString("chat.audio.scrub.value", comment: "Elapsed of total voice message duration"),
            MomentsFormat.spokenDuration(currentTime),
            MomentsFormat.spokenDuration(duration)
        )))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = min(5, duration / 10)
            switch direction {
            case .increment:
                seekToFraction((currentTime + step) / duration)
            case .decrement:
                seekToFraction((currentTime - step) / duration)
            @unknown default:
                break
            }
        }
    }

    private var unavailableRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            Text(NSLocalizedString("chat.audio.unavailable", comment: "Audio message unavailable"))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(durationLabelColor)
        }
    }

    /// Debajo de la onda: «Cargando», tiempo o nada si el audio no está disponible.
    @ViewBuilder
    private var bottomLabel: some View {
        if isCheckingAvailability {
            Text(NSLocalizedString("chat.loading", comment: "Loading audio message"))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(durationLabelColor)
        } else if isAudioAvailable {
            timeLabel
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var timeLabel: some View {
        Text(formatDuration(displayedTimeSeconds))
            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
            .monospacedDigit()
            .foregroundStyle(durationLabelColor)
            .accessibilityLabel(
                Text(
                    String(
                        format: NSLocalizedString(
                            "chat.audio.duration.accessibility",
                            comment: "Voice message duration for accessibility"
                        ),
                        MomentsFormat.spokenDuration(displayedTimeSeconds)
                    )
                )
            )
    }

    @ViewBuilder
    private var speedButton: some View {
        Button(action: cyclePlaybackRate) {
            Text(speedLabel)
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(controlColor)
                // Ancho fijo (el reservado en el layout) para que no salte entre 1× y 1.5×.
                .frame(width: VoiceMessageLayout.speedControlWidth)
                .padding(.vertical, 4)
                .background(controlColor.opacity(colorScheme == .dark ? 0.15 : 0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var speedLabel: String {
        switch playbackRate {
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default: return "1×"
        }
    }

    private func refreshWaveformLevels() {
        let seed = audioUrl ?? messageId
        let trackWidth = waveformTrackWidth
        let barCount = VoiceMessageLayout.waveformBarCount(for: trackWidth)
        if let waveformSamples, !waveformSamples.isEmpty {
            waveformLevels = ChatVoiceWaveformSamples.resampled(waveformSamples, count: barCount)
        } else {
            waveformLevels = ChatVoiceWaveformGenerator.levels(seed: seed, count: barCount)
        }
    }
    
    private func getPlayButtonIcon() -> String {
        if !isAudioAvailable {
            return "exclamationmark.triangle.fill"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }
    
    private func checkAudioAvailability() {
        if isSending {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }

        guard let audioUrl = audioUrl, let url = URL(string: audioUrl) else {
            isAudioAvailable = false
            isCheckingAvailability = false
            return
        }

        if url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }

        if let cachedURL = PersistentAudioCache.shared.cachedURL(for: url.absoluteString),
           FileManager.default.fileExists(atPath: cachedURL.path) {
            isAudioAvailable = true
            isCheckingAvailability = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isCheckingAvailability = false
                
                if error != nil {
                    self.isAudioAvailable = false
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self.isAudioAvailable = true
                    } else {
                        self.isAudioAvailable = false
                    }
                } else {
                    self.isAudioAvailable = false
                }
            }
        }.resume()
    }
    
    private func togglePlayback() {
        guard isAudioAvailable else {
            showErrorMessage = true
            return
        }

        if isPlaying {
            playback.pause()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let audioUrl, let url = URL(string: audioUrl) else {
            isAudioAvailable = false
            return
        }
        playback.play(
            messageId: messageId,
            url: url,
            duration: duration,
            senderId: senderId,
            onFailure: {
                isAudioAvailable = false
                showErrorMessage = true
            }
        )
    }

    private func resumeAfterScrub() {
        guard isAudioAvailable, wasPlayingBeforeScrub else { return }
        startPlayback()
    }

    private func cyclePlaybackRate() {
        playback.cyclePlaybackRate()
    }

    /// Seek del reproductor: si la nota está activa mueve el player; si no, guarda la posición.
    private func seekToFraction(_ fraction: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(1, fraction))
        playback.seek(messageId: messageId, to: clamped * duration)
    }

    private func fraction(forX x: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        return Double(max(0, min(1, x / trackWidth)))
    }

    /// Inicio del arrastre: pausa para reanudar al soltar.
    private func beginScrub() {
        isScrubbing = true
        scrubFraction = displayedProgress
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            playback.pause()
        }
        HapticManager.shared.lightImpact()
    }

    /// Fin del arrastre: aplica el seek en la posición soltada y reanuda si sonaba.
    private func endScrub() {
        guard isScrubbing else { return }
        if let scrubFraction {
            seekToFraction(scrubFraction)
        }
        isScrubbing = false
        scrubFraction = nil
        if wasPlayingBeforeScrub {
            resumeAfterScrub()
        }
        wasPlayingBeforeScrub = false
    }

    private var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    private var displayedProgress: Double {
        if let scrubFraction {
            return scrubFraction
        }
        return playbackProgress
    }

    /// Parado al inicio: duración total. Reproduciendo, en pausa a mitad o arrastrando: transcurrido.
    private var displayedTimeSeconds: Double {
        guard duration > 0 else { return 0 }
        if let scrubFraction {
            return scrubFraction * duration
        }
        if isPlaying || currentTime > 0.01 {
            return min(duration, currentTime)
        }
        return duration
    }

    private func formatDuration(_ time: Double) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
