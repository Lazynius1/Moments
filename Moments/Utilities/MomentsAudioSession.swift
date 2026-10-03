import AVFoundation
import Synchronization

/// Serializa la sesión compartida fuera del hilo principal. Cada reproductor libera
/// únicamente su propia solicitud; una vista antigua no puede apagar otro audio.
enum MomentsAudioSession {
    static let interruptionNotification = Foundation.Notification.Name("MomentsAudioSessionInterrupted")
    private static let queue = DispatchQueue(label: "com.moments.audioSession", qos: .userInitiated)
    private struct Request {
        let owner: UUID
        let generation: UInt64
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
        var priority: Int { category == .playAndRecord || category == .record ? 2 : (category == .ambient ? 0 : 1) }
    }
    // Acceso exclusivo desde queue.
    nonisolated(unsafe) private static var requests: [Request] = []
    private static let observers = Mutex<[NSObjectProtocol]>([
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            interrupt()
        },
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            interrupt()
        },
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            interrupt()
        }
    ])

    private static func interrupt() {
        queue.async {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: interruptionNotification, object: nil)
            }
        }
    }

    static func prepareMutedPlayback() async {
        observers.withLock { _ in }
        await withCheckedContinuation { continuation in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                if requests.isEmpty && session.category == .soloAmbient {
                    try? session.setCategory(.ambient, mode: .default, options: [])
                }
                continuation.resume()
            }
        }
    }

    fileprivate static func activate(owner: UUID, generation: UInt64, category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                                     options: AVAudioSession.CategoryOptions, isCurrent: @escaping @Sendable () -> Bool) async -> Bool {
        observers.withLock { _ in }
        return await withCheckedContinuation { continuation in
            queue.async {
                guard isCurrent() else { continuation.resume(returning: false); return }
                let previous = requests
                requests.removeAll { $0.owner == owner }
                requests.append(Request(owner: owner, generation: generation, category: category, mode: mode, options: options))
                do {
                    try applyCurrentRequest()
                    continuation.resume(returning: true)
                } catch {
                    requests = previous
                    try? applyCurrentRequest()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    fileprivate static func deactivate(owner: UUID, throughGeneration: UInt64? = nil) {
        queue.async {
            let shouldRelease: (Request) -> Bool = { request in
                guard request.owner == owner else { return false }
                return throughGeneration.map { request.generation <= $0 } ?? true
            }
            guard requests.contains(where: shouldRelease) else { return }
            requests.removeAll(where: shouldRelease)
            try? applyCurrentRequest()
        }
    }

    private static func applyCurrentRequest() throws {
        let session = AVAudioSession.sharedInstance()
        // Una grabación conserva su ruta aunque se monte una preview de fondo.
        if let request = requests.enumerated().max(by: {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority < $1.element.priority
        })?.element {
            if session.category != request.category || session.mode != request.mode || session.categoryOptions != request.options {
                try session.setCategory(request.category, mode: request.mode, options: request.options)
            }
            try session.setActive(true)
        } else {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.ambient, mode: .default, options: [])
        }
    }
}

/// Se conserva junto al player. Invalidar la solicitud también impide que una
/// activación pendiente arranque después de cerrar o pausar su vista.
final class MomentsAudioSessionLease: Sendable {
    private let owner = UUID()
    private let generation = Mutex<UInt64>(0)
    private let observer = Mutex<NSObjectProtocol?>(nil)

    init() {
        observer.withLock { token in
            token = NotificationCenter.default.addObserver(
                forName: MomentsAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let releasedGeneration = self.generation.withLock { $0 &+= 1; return $0 }
                // Los handlers de UI pausan el player durante esta notificación.
                DispatchQueue.main.async { [self] in MomentsAudioSession.deactivate(owner: self.owner, throughGeneration: releasedGeneration) }
            }
        }
    }

    @discardableResult
    func activate(category: AVAudioSession.Category = .playback, mode: AVAudioSession.Mode = .default,
                  options: AVAudioSession.CategoryOptions = []) async -> Bool {
        guard !Task.isCancelled else { return false }
        let request = generation.withLock { $0 &+= 1; return $0 }
        let activated = await MomentsAudioSession.activate(owner: owner, generation: request, category: category, mode: mode, options: options) { [self] in
            generation.withLock { $0 == request }
        }
        guard generation.withLock({ $0 == request }) else { return false }
        if Task.isCancelled { deactivate(); return false }
        return activated
    }

    func deactivate() {
        let releasedGeneration = generation.withLock { $0 &+= 1; return $0 }
        MomentsAudioSession.deactivate(owner: owner, throughGeneration: releasedGeneration)
    }

    deinit {
        observer.withLock { if let token = $0 { NotificationCenter.default.removeObserver(token) } }
        MomentsAudioSession.deactivate(owner: owner)
    }
}
