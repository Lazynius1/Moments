import Foundation

/// Índice ligero de momentos con vídeo para Reels sin pasar el feed completo a cada celda.
@MainActor
final class VideoMomentsIndex: ObservableObject {
    static let shared = VideoMomentsIndex()

    private(set) var videoMoments: [VideoMoment] = []

    private init() {}

    func rebuild(from moments: [Moment]) {
        videoMoments = moments.videoMoments
    }

    func reelsStartIndex(for momentId: String?) -> Int {
        guard let momentId else { return 0 }
        return videoMoments.firstIndex { $0.moment.id == momentId } ?? 0
    }
}
