import MapKit

/// Stable viewport identity: suppress camera noise without rounding every pan to a kilometre.
enum MapViewportQuery {
    static func key(for region: MKCoordinateRegion) -> String {
        let latitudeZoom = (log2(max(region.span.latitudeDelta, 0.00001)) * 4).rounded()
        let longitudeZoom = (log2(max(region.span.longitudeDelta, 0.00001)) * 4).rounded()
        let latitudeStep = max(0.0001, pow(2, latitudeZoom / 4) / 12)
        let longitudeStep = max(0.0001, pow(2, longitudeZoom / 4) / 12)
        let latitude = (region.center.latitude / latitudeStep).rounded()
        let longitude = (region.center.longitude / longitudeStep).rounded()
        return "\(latitude)|\(longitude)|\(latitudeZoom)|\(longitudeZoom)"
    }
}
