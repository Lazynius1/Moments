import SwiftUI

/// Contexto de presentación unificado para detalle de momento desde feed, perfil, mapa o explore.
enum MomentDetailContext {
    case single(Moment)
    case profileCarousel(
        moments: [Moment],
        initialIndex: Int,
        topContentInset: CGFloat = 0,
        onDismiss: () -> Void = {}
    )
    case map(
        moments: [Moment],
        initialIndex: Int,
        locationName: String,
        momentAvailability: Binding<[String: Bool]>,
        isPresented: Binding<Bool>
    )
}
