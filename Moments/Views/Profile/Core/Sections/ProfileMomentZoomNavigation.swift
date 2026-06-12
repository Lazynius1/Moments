import SwiftUI
import UIKit

// MARK: - Zoom navigation (iOS 18+)

enum ProfileMomentZoomFeedKind: Hashable {
    case ownMoments
    case taggedMoments
    case userProfileMoments
    case userProfileTagged
    case savedMoments
}

struct ProfileMomentZoomDestination: Hashable {
    let zoomSourceID: String
    let initialIndex: Int
    let initialMomentId: String?
    let feedKind: ProfileMomentZoomFeedKind
    var restrictPlaybackToInitialIndex: Bool = false
}

/// Destino genérico para zoom fuera del perfil (explore, actividad, mapa, etc.).
struct MomentZoomDestination: Hashable {
    let zoomSourceID: String
    let initialIndex: Int
    let initialMomentId: String?
    let presentation: MomentZoomPresentationKind
    var restrictPlaybackToInitialIndex: Bool = false
}

enum MomentZoomPresentationKind: Hashable {
    case carousel
    case saved
    case single
    case map(locationName: String)
}

struct HighlightZoomDestination: Hashable {
    let zoomSourceID: String
    let highlightId: String
}

enum ProfileMomentZoomNavigation {
    static func sourceID(moment: Moment, gridIndex: Int) -> String {
        moment.id ?? "profile-grid-\(gridIndex)"
    }

    static func sourceID(moment: Moment, index: Int, prefix: String) -> String {
        moment.id ?? "\(prefix)-\(index)"
    }

    static func highlightSourceID(highlight: HighlightedStory, index: Int) -> String {
        highlight.id ?? "highlight-\(index)"
    }

    static func canvasBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    static func canvasUIColor(for colorScheme: ColorScheme) -> UIColor {
        colorScheme == .dark ? UIColor(hex: "0B1215") : UIColor(hex: "FAF9F6")
    }
}

typealias MomentZoomNavigation = ProfileMomentZoomNavigation
typealias MomentZoomSourceModifier = ProfileMomentZoomSourceModifier

/// NavigationStack pinta `systemBackground` (negro puro en dark). Lo sustituimos por el canvas del perfil.
private struct ProfileNavigationControllerBackgroundFix: UIViewRepresentable {
    let uiColor: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(uiColor: uiColor, from: uiView)
        }
    }

    private static func apply(uiColor: UIColor, from view: UIView) {
        var current: UIView? = view
        while let host = current {
            if let navigationController = host.next as? UINavigationController {
                navigationController.view.backgroundColor = uiColor
                navigationController.view.isOpaque = true
                navigationController.topViewController?.view.backgroundColor = .clear
                tintScrollViews(in: navigationController.view, color: .clear)
                return
            }
            current = host.superview
        }

        tintScrollViews(in: view, color: .clear)
    }

    private static func tintScrollViews(in view: UIView, color: UIColor) {
        if let scrollView = view as? UIScrollView {
            scrollView.backgroundColor = color
        }
        view.subviews.forEach { tintScrollViews(in: $0, color: color) }
    }
}

extension View {
    func profileGridNavigationChrome(colorScheme: ColorScheme) -> some View {
        scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func profileNavigationSurface(colorScheme: ColorScheme) -> some View {
        let canvas = ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
        let uiCanvas = ProfileMomentZoomNavigation.canvasUIColor(for: colorScheme)

        return background {
            canvas.ignoresSafeArea()
        }
        .background(ProfileNavigationControllerBackgroundFix(uiColor: uiCanvas))
    }

    func momentZoomNavigationChrome(colorScheme: ColorScheme) -> some View {
        profileGridNavigationChrome(colorScheme: colorScheme)
    }

    func momentZoomNavigationSurface(colorScheme: ColorScheme) -> some View {
        profileNavigationSurface(colorScheme: colorScheme)
    }
}

// MARK: - Destinations

struct ProfileMomentZoomDetailDestination: View {
    let destination: ProfileMomentZoomDestination
    let moments: [Moment]
    let namespace: Namespace.ID
    var onRemoveSavedMoment: ((Moment) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if destination.feedKind == .savedMoments {
                ModernSavedMomentsDetailView(
                    moments: moments,
                    initialIndex: destination.initialIndex,
                    onDismiss: { dismiss() },
                    onRemoveMoment: onRemoveSavedMoment
                )
            } else {
                ModernMomentDetailView(
                    moments: moments,
                    initialIndex: destination.initialIndex,
                    initialMomentId: destination.initialMomentId,
                    topContentInset: 0,
                    restrictPlaybackToInitialIndex: destination.restrictPlaybackToInitialIndex,
                    onDismiss: { dismiss() }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTransition(.zoom(sourceID: destination.zoomSourceID, in: namespace))
    }
}

struct MomentZoomDetailDestination: View {
    let destination: MomentZoomDestination
    let moments: [Moment]
    let namespace: Namespace.ID
    var onRemoveSavedMoment: ((Moment) -> Void)? = nil
    @Binding var mapDetailPresented: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
        destination: MomentZoomDestination,
        moments: [Moment],
        namespace: Namespace.ID,
        onRemoveSavedMoment: ((Moment) -> Void)? = nil,
        mapDetailPresented: Binding<Bool> = .constant(false)
    ) {
        self.destination = destination
        self.moments = moments
        self.namespace = namespace
        self.onRemoveSavedMoment = onRemoveSavedMoment
        self._mapDetailPresented = mapDetailPresented
    }

    var body: some View {
        Group {
            switch destination.presentation {
            case .carousel:
                ModernMomentDetailView(
                    moments: moments,
                    initialIndex: destination.initialIndex,
                    initialMomentId: destination.initialMomentId,
                    topContentInset: 0,
                    restrictPlaybackToInitialIndex: destination.restrictPlaybackToInitialIndex,
                    onDismiss: { dismissMapIfNeeded(); dismiss() }
                )
            case .saved:
                ModernSavedMomentsDetailView(
                    moments: moments,
                    initialIndex: destination.initialIndex,
                    onDismiss: { dismiss() },
                    onRemoveMoment: onRemoveSavedMoment
                )
            case .single:
                if let moment = moments.indices.contains(destination.initialIndex) ? moments[destination.initialIndex] : moments.first {
                    MomentDetailContainerView(context: .single(moment))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                                .ignoresSafeArea()
                        )
                }
            case .map(let locationName):
                LocationMomentDetailView(
                    locationMoments: moments,
                    initialIndex: destination.initialIndex,
                    locationName: locationName,
                    momentAvailability: .constant([:]),
                    isPresented: Binding(
                        get: { true },
                        set: { isPresented in
                            if !isPresented {
                                mapDetailPresented = false
                                dismiss()
                            }
                        }
                    )
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTransition(.zoom(sourceID: destination.zoomSourceID, in: namespace))
    }

    private func dismissMapIfNeeded() {
        if case .map = destination.presentation {
            mapDetailPresented = false
        }
    }
}

struct HighlightZoomDetailDestination: View {
    let destination: HighlightZoomDestination
    let highlight: HighlightedStory
    let namespace: Namespace.ID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HighlightViewer(highlight: highlight)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .navigationTransition(.zoom(sourceID: destination.zoomSourceID, in: namespace))
    }
}

struct ProfileMomentZoomSourceModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String?
    var cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        if let namespace, let sourceID {
            content.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

struct HighlightZoomSourceModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String?
    var size: CGFloat = 64

    func body(content: Content) -> some View {
        if let namespace, let sourceID {
            content.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: size / 2, style: .continuous))
            }
        } else {
            content
        }
    }
}

// MARK: - Zoom helpers

enum MomentZoomOpener {
    static func open(
        moment: Moment,
        moments: [Moment],
        initialIndex: Int,
        presentation: MomentZoomPresentationKind,
        destination: inout MomentZoomDestination?,
        snapshot: inout [Moment]
    ) {
        snapshot = moments
        destination = MomentZoomDestination(
            zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, index: initialIndex, prefix: presentationPrefix(presentation)),
            initialIndex: initialIndex,
            initialMomentId: moment.id,
            presentation: presentation
        )
        HapticManager.shared.lightImpact()
    }

    private static func presentationPrefix(_ presentation: MomentZoomPresentationKind) -> String {
        switch presentation {
        case .carousel: return "carousel"
        case .saved: return "saved"
        case .single: return "single"
        case .map: return "map"
        }
    }
}
