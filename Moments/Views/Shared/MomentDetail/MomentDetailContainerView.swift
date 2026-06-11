import SwiftUI

/// Punto de entrada único para detalle de momento. Delega en la vista especializada según contexto.
struct MomentDetailContainerView: View {
    let context: MomentDetailContext

    var body: some View {
        switch context {
        case .single(let moment):
            MomentDetailView(moment: moment)

        case .profileCarousel(let moments, let initialIndex, let topContentInset, let onDismiss):
            ModernMomentDetailView(
                moments: moments,
                initialIndex: initialIndex,
                topContentInset: topContentInset,
                onDismiss: onDismiss
            )

        case .map(let moments, let initialIndex, let locationName, let momentAvailability, let isPresented):
            LocationMomentDetailView(
                locationMoments: moments,
                initialIndex: initialIndex,
                locationName: locationName,
                momentAvailability: momentAvailability,
                isPresented: isPresented
            )
        }
    }
}
