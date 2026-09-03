import Foundation

/// Índice ligero de momentos con vídeo para Reels sin pasar el feed completo a cada celda.
@MainActor
final class VideoMomentsIndex: ObservableObject {
    static let shared = VideoMomentsIndex()

    @Published private(set) var videoMoments: [VideoMoment] = []

    private init() {}

    func rebuild(from moments: [Moment]) {
        videoMoments = moments.videoMoments
    }

    /// `nil` si el momento no está en la cola — **no** caer a 0 (abriría otro vídeo).
    func reelsStartIndex(for momentId: String?) -> Int? {
        guard let momentId, !momentId.isEmpty else { return nil }
        return videoMoments.firstIndex { $0.moment.id == momentId }
    }
}
