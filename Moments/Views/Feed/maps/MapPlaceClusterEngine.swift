import Foundation
import CoreLocation
import MapKit

struct MapPlaceCluster: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let displayName: String
    let moments: [Moment]
    let stories: [MapStoryPreview]
    let friends: [MapFriendActivityPin]

    var momentCount: Int { moments.count }
    var storyCount: Int { stories.count }
    var totalCount: Int { momentCount + storyCount }

    var primaryStory: MapStoryPreview? {
        stories.sorted { $0.timestamp > $1.timestamp }.first
    }

    var primaryMoment: Moment? {
        moments.sorted { $0.timestamp > $1.timestamp }.first
    }

    var latestTimestamp: Date {
        let momentDate = moments.map(\.timestamp).max() ?? .distantPast
        let storyDate = stories.map(\.timestamp).max() ?? .distantPast
        let friendDate = friends.map(\.latestTimestamp).max() ?? .distantPast
        return max(momentDate, storyDate, friendDate)
    }

    /// Story de hace menos de 1 h → el pin "late".
    var hasFreshStory: Bool {
        guard let story = primaryStory else { return false }
        return Date().timeIntervalSince(story.timestamp) < 3600
    }

    /// Contenido más viejo de 7 días → pin atenuado.
    var isStale: Bool {
        Date().timeIntervalSince(latestTimestamp) > 7 * 24 * 3600
    }

    var isAggregate: Bool {
        id == MapPlaceClusterEngine.aggregateClusterId
    }

    static func == (lhs: MapPlaceCluster, rhs: MapPlaceCluster) -> Bool {
        lhs.id == rhs.id
    }
}

struct MapPlaceLayout {
    let placeClusters: [MapPlaceCluster]
    let standaloneFriends: [MapFriendActivityPin]

    static let empty = MapPlaceLayout(placeClusters: [], standaloneFriends: [])
}

enum MapPlaceClusterEngine {
    static let aggregateClusterId = "region-aggregate"

    private struct MutableCluster {
        var id: String
        var coordinate: CLLocationCoordinate2D
        var displayName: String
        var moments: [Moment] = []
        var stories: [MapStoryPreview] = []
        var friends: [MapFriendActivityPin] = []
        var latestTimestamp: Date = .distantPast
    }

    static func build(
        moments: [Moment],
        stories: [MapStoryPreview],
        friendPins: [MapFriendActivityPin],
        filter: MapDiscoverContentFilter,
        region: MKCoordinateRegion
    ) -> MapPlaceLayout {
        switch filter {
        case .friends:
            return MapPlaceLayout(placeClusters: [], standaloneFriends: friendPins)
        case .places, .all:
            break
        }

        let mergeRadius = mergeRadiusMeters(for: region)
        let coordPrecision = coordinatePrecision(for: region)
        var clusters: [MutableCluster] = []

        func upsertMoment(_ moment: Moment, coordinate: CLLocationCoordinate2D, name: String) {
            let key = clusterKey(name: name, coordinate: coordinate, precision: coordPrecision)
            if let index = clusters.firstIndex(where: { existing in
                existing.id == key || shouldMerge(existing.coordinate, coordinate, radius: mergeRadius, name: existing.displayName, otherName: name)
            }) {
                clusters[index].moments.append(moment)
                if moment.timestamp > clusters[index].latestTimestamp {
                    clusters[index].latestTimestamp = moment.timestamp
                }
                if clusters[index].displayName.isEmpty, !name.isEmpty {
                    clusters[index].displayName = name
                }
            } else {
                clusters.append(
                    MutableCluster(
                        id: key,
                        coordinate: coordinate,
                        displayName: name,
                        moments: [moment],
                        latestTimestamp: moment.timestamp
                    )
                )
            }
        }

        func upsertStory(_ story: MapStoryPreview, coordinate: CLLocationCoordinate2D, name: String) {
            let key = clusterKey(name: name, coordinate: coordinate, precision: coordPrecision)
            if let index = clusters.firstIndex(where: { existing in
                existing.id == key || shouldMerge(existing.coordinate, coordinate, radius: mergeRadius, name: existing.displayName, otherName: name)
            }) {
                clusters[index].stories.append(story)
                if story.timestamp > clusters[index].latestTimestamp {
                    clusters[index].latestTimestamp = story.timestamp
                }
                if clusters[index].displayName.isEmpty, !name.isEmpty {
                    clusters[index].displayName = name
                }
            } else {
                clusters.append(
                    MutableCluster(
                        id: key,
                        coordinate: coordinate,
                        displayName: name,
                        stories: [story],
                        latestTimestamp: story.timestamp
                    )
                )
            }
        }

        for moment in moments {
            guard let coordinate = moment.locationCoordinate?.toCLLocationCoordinate2D,
                  CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let name = normalizedLocationName(moment.location)
            upsertMoment(moment, coordinate: coordinate, name: name)
        }

        let storiesForMap = filter == .places ? [] : stories
        for story in storiesForMap {
            guard let coordinate = story.coordinate, CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let name = normalizedLocationName(story.locationName)
            upsertStory(story, coordinate: coordinate, name: name)
        }

        var absorbedFriendIds = Set<String>()
        if filter == .all {
            for pin in friendPins {
                guard let index = clusters.firstIndex(where: { cluster in
                    shouldMerge(cluster.coordinate, pin.coordinate, radius: mergeRadius, name: cluster.displayName, otherName: "")
                        || cluster.moments.contains(where: { $0.authorId == pin.authorId })
                        || cluster.stories.contains(where: { $0.authorId == pin.authorId })
                }) else { continue }

                clusters[index].friends.append(pin)
                absorbedFriendIds.insert(pin.authorId)
                if pin.latestTimestamp > clusters[index].latestTimestamp {
                    clusters[index].latestTimestamp = pin.latestTimestamp
                }
            }
        }

        let standaloneFriends = filter == .places ? [] : friendPins.filter { !absorbedFriendIds.contains($0.authorId) }

        // Pasada final: fusionar clusters que quedaron casi superpuestos
        // (p. ej. contenido con nombre de lugar vs. sin nombre a pocos metros).
        var merged: [MutableCluster] = []
        for cluster in clusters {
            if let index = merged.firstIndex(where: { existing in
                shouldMerge(
                    existing.coordinate,
                    cluster.coordinate,
                    radius: mergeRadius,
                    name: existing.displayName,
                    otherName: cluster.displayName
                )
            }) {
                merged[index].moments.append(contentsOf: cluster.moments)
                merged[index].stories.append(contentsOf: cluster.stories)
                merged[index].friends.append(contentsOf: cluster.friends)
                if cluster.latestTimestamp > merged[index].latestTimestamp {
                    merged[index].latestTimestamp = cluster.latestTimestamp
                }
                if merged[index].displayName.isEmpty, !cluster.displayName.isEmpty {
                    merged[index].displayName = cluster.displayName
                }
            } else {
                merged.append(cluster)
            }
        }

        let placeClusters = merged
            .filter { !$0.moments.isEmpty || !$0.stories.isEmpty }
            .map { mutable in
                MapPlaceCluster(
                    id: mutable.id,
                    coordinate: mutable.coordinate,
                    displayName: resolvedDisplayName(mutable.displayName, moments: mutable.moments, stories: mutable.stories),
                    moments: mutable.moments.sorted { $0.timestamp > $1.timestamp },
                    stories: mutable.stories.sorted { $0.timestamp > $1.timestamp },
                    friends: mutable.friends
                )
            }
            .sorted { $0.latestTimestamp > $1.latestTimestamp }

        return MapPlaceLayout(placeClusters: placeClusters, standaloneFriends: standaloneFriends)
    }

    static func aggregateRegionCluster(
        title: String,
        moments: [Moment],
        stories: [MapStoryPreview],
        center: CLLocationCoordinate2D
    ) -> MapPlaceCluster {
        MapPlaceCluster(
            id: aggregateClusterId,
            coordinate: center,
            displayName: title,
            moments: moments.sorted { $0.timestamp > $1.timestamp },
            stories: stories.sorted { $0.timestamp > $1.timestamp },
            friends: []
        )
    }

    static func cluster(for friend: MapFriendActivityPin, moments: [Moment], stories: [MapStoryPreview]) -> MapPlaceCluster {
        let authorMoments = moments.filter { $0.authorId == friend.authorId }.sorted { $0.timestamp > $1.timestamp }
        let authorStories = stories.filter { $0.authorId == friend.authorId }.sorted { $0.timestamp > $1.timestamp }
        return MapPlaceCluster(
            id: "friend-\(friend.authorId)",
            coordinate: friend.coordinate,
            displayName: friend.username,
            moments: authorMoments,
            stories: authorStories,
            friends: [friend]
        )
    }

    static func jitteredCoordinate(for base: CLLocationCoordinate2D, seed: String, index: Int) -> CLLocationCoordinate2D {
        let hash = abs(seed.hashValue &+ index &* 31)
        let angle = Double(hash % 360) * (.pi / 180)
        let radius = 0.00018 + Double(hash % 40) * 0.000004
        return CLLocationCoordinate2D(
            latitude: base.latitude + cos(angle) * radius,
            longitude: base.longitude + sin(angle) * radius
        )
    }

    private static func normalizedLocationName(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func resolvedDisplayName(_ name: String, moments: [Moment], stories: [MapStoryPreview]) -> String {
        if !name.isEmpty {
            return name.capitalized
        }
        if let momentName = moments.compactMap({ $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            return momentName
        }
        if let storyName = stories.compactMap({ $0.locationName?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            return storyName
        }
        return NSLocalizedString("maps.place.unnamed", comment: "Unnamed map place")
    }

    private static func clusterKey(name: String, coordinate: CLLocationCoordinate2D, precision: Int) -> String {
        let factor = pow(10.0, Double(precision))
        let lat = (coordinate.latitude * factor).rounded() / factor
        let lon = (coordinate.longitude * factor).rounded() / factor
        if !name.isEmpty {
            return "place|\(name)|\(lat)|\(lon)"
        }
        return "coord|\(lat)|\(lon)"
    }

    private static func coordinatePrecision(for region: MKCoordinateRegion) -> Int {
        let delta = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if delta > 0.12 { return 3 }
        if delta > 0.04 { return 4 }
        return 5
    }

    private static func mergeRadiusMeters(for region: MKCoordinateRegion) -> CLLocationDistance {
        let delta = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if delta > 0.12 { return 450 }
        if delta > 0.04 { return 180 }
        return 90
    }

    private static func shouldMerge(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D,
        radius: CLLocationDistance,
        name: String,
        otherName: String
    ) -> Bool {
        if !name.isEmpty, !otherName.isEmpty, name == otherName {
            return true
        }
        let left = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let right = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return left.distance(from: right) <= radius
    }
}
