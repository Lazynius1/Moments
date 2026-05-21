import Foundation
import CoreLocation

struct MapsLocationAnnotation: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
}

extension Moment {
    var mapAvailabilityKey: String {
        if let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return "\(authorId)|\(Int(timestamp.timeIntervalSince1970))|\(content)"
    }

    var mapHasVideoMedia: Bool {
        if let mediaItems, mediaItems.contains(where: { $0.type == .video }) {
            return true
        }
        if let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty {
            return true
        }
        return false
    }

    var mapHasRenderableMedia: Bool {
        if let mediaItems, mediaItems.contains(where: { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }

        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return true
        }

        if let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty {
            return true
        }

        return false
    }

    var mapPreferredImageURL: String? {
        if let mediaItems {
            if let firstImage = mediaItems.first(where: { $0.type == .image }) {
                let imageURL = firstImage.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !imageURL.isEmpty { return imageURL }
            }

            if let firstVideo = mediaItems.first(where: { $0.type == .video }) {
                if let thumb = firstVideo.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
                    return thumb
                }
                let fallback = firstVideo.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallback.isEmpty { return fallback }
            }
        }

        if let thumbnailUrl = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }

        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }

        return nil
    }

    var mapPreferredVideoThumbnailURL: String? {
        if let mediaItems, let firstVideo = mediaItems.first(where: { $0.type == .video }) {
            if let thumb = firstVideo.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
                return thumb
            }
            let fallback = firstVideo.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty { return fallback }
        }

        if let thumbnailUrl = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnailUrl.isEmpty {
            return thumbnailUrl
        }

        if let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }

        return nil
    }
}

struct CombinedMapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let locationTitle: String?
    let moment: Moment?
    let moments: [Moment]

    var primaryMoment: Moment? {
        moment ?? moments.first
    }

    var count: Int {
        if !moments.isEmpty { return moments.count }
        return moment == nil ? 0 : 1
    }
}
