import SwiftUI

struct PhotosPermissionView: View {
    var stage: PermissionPrimerStage = .primer
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    private var isDenied: Bool { stage == .denied }

    var body: some View {
        PermissionPrimerScaffold(
            stage: stage,
            iconSymbol: isDenied ? "photo.badge.exclamationmark" : "photo.on.rectangle",
            title: title,
            description: description,
            primaryActionTitle: primaryActionTitle,
            secondaryActionTitle: NSLocalizedString("permission.photos.primer.notNow", comment: "Not now"),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ) {
            PermissionPhoneFrame(
                screenBackground: Color(hex: "111318"),
                animated: false,
                appliesDeniedChrome: isDenied
            ) { size, _ in
                PhotoMosaicScreen(size: size, isActive: !isDenied)
            } island: { _, _ in
                EmptyView()
            }
        }
    }

    private var title: String {
        stage == .primer
            ? NSLocalizedString("permission.photos.primer.title", comment: "Photos primer title")
            : NSLocalizedString("permission.photos.denied.title", comment: "Photos denied title")
    }

    private var description: String {
        stage == .primer
            ? NSLocalizedString("permission.photos.primer.subtitle", comment: "Photos primer subtitle")
            : NSLocalizedString("permission.photos.denied.subtitle", comment: "Photos denied subtitle")
    }

    private var primaryActionTitle: String {
        stage == .primer
            ? NSLocalizedString("permission.photos.primer.allow", comment: "Allow photos")
            : NSLocalizedString("permission.photos.denied.openSettings", comment: "Open Settings")
    }
}

private struct PhotoMosaicScreen: View {
    let size: CGSize
    var isActive: Bool = true

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { timeline in
                    mosaic(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mosaic(at: 0)
                    .blur(radius: 2.5)
            }
        }
    }

    private func mosaic(at t: TimeInterval) -> some View {
        let travel = size.height * 0.8
        let scroll = isActive ? (sin(t * 0.35) + 1) / 2 * travel : travel * 0.35

        return Group {
            if let ui = UIImage(named: "PermissionGalleryPhotos") {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height * 1.8)
                    .offset(y: -scroll)
            } else {
                LinearGradient(
                    colors: [Color(hex: "2B2F3A"), Color(hex: "191B22")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}

#Preview("Primer") {
    PhotosPermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
}

#Preview("Denied") {
    PhotosPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
}
