import SwiftUI
import UIKit
import FirebaseAuth

/// Medidas de la pill flotante. Overlays en safe area (menú, toasts) usan `overlayBottomPadding`.
enum MomentsFloatingTabBarMetrics {
    static let barThickness: CGFloat = 54
    static let chromePadding: CGFloat = 4
    static let physicalEdgeInset: CGFloat = 18
    static let overlayGap: CGFloat = 8
    /// Altura de la pila vertical (5 tabs × ~52 + chrome).
    static let verticalStackHeight: CGFloat = 290

    static var barHeight: CGFloat { barThickness }

    static var heightFromPhysicalBottom: CGFloat {
        barThickness + chromePadding * 2 + physicalEdgeInset
    }

    static var widthFromPhysicalEdge: CGFloat {
        barThickness + chromePadding * 2 + physicalEdgeInset
    }

    /// Hueco inferior para overlays. Con rail vertical la pill ya no vive abajo.
    static func overlayBottomPadding(
        safeAreaBottom: CGFloat,
        verticalBarEdge: HorizontalEdge? = nil
    ) -> CGFloat {
        if verticalBarEdge != nil {
            return max(12, overlayGap)
        }
        return max(20, heightFromPhysicalBottom - safeAreaBottom + overlayGap)
    }
}

// MARK: - toolbarVerticalEdge → entorno Moments (iOS 27.1+)

private struct MomentsToolbarVerticalEdgeKey: EnvironmentKey {
    static let defaultValue: HorizontalEdge? = nil
}

extension EnvironmentValues {
    /// Borde del rail vertical del sistema. `nil` → chrome horizontal abajo.
    var momentsToolbarVerticalEdge: HorizontalEdge? {
        get { self[MomentsToolbarVerticalEdgeKey.self] }
        set { self[MomentsToolbarVerticalEdgeKey.self] = newValue }
    }
}

/// Propaga `toolbarVerticalEdge` a todo el árbol (pill + feed/overlays).
struct MomentsToolbarVerticalEdgeProvider<Content: View>: View {
    @ViewBuilder var content: (HorizontalEdge?) -> Content

    var body: some View {
        if #available(iOS 27.1, *) {
            MomentsToolbarVerticalEdgeProviderModern(content: content)
        } else {
            content(nil)
        }
    }
}

@available(iOS 27.1, *)
private struct MomentsToolbarVerticalEdgeProviderModern<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    @ViewBuilder var content: (HorizontalEdge?) -> Content

    var body: some View {
        content(edge)
            .environment(\.momentsToolbarVerticalEdge, edge)
    }
}

/// Floating pill Moments — Home · Mensajes · Creator · Explorar · Perfil.
/// Horizontal abajo por defecto; en iOS 27.1+ sigue `toolbarVerticalEdge`
/// (barra vertical del sistema en Duo / multitasking) → stack vertical en ese borde.
struct MomentsFloatingTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatorView: Bool
    @Binding var previousSelectedTab: Int
    @ObservedObject var minimize: TabBarMinimizeController
    @ObservedObject private var badgeService = NotificationBadgeService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.momentsViewportSize) private var momentsViewportSize
    @Environment(\.momentsDivisionRegions) private var divisionRegions
    @Environment(\.momentsToolbarVerticalEdge) private var verticalBarEdge

    @State private var profileSegmentImage: UIImage?
    @State private var profileRenderTask: Task<Void, Never>?

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var symbolConfig: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(font: .systemFont(ofSize: 23, weight: .medium))
    }

    private var messagesSymbolName: String {
        badgeService.unreadMessagesCount > 0 ? "paperplane.fill" : "paperplane"
    }

    /// Paperplane (+ fill si hay no leídos). El badge rojo va en overlay SwiftUI (animable).
    private var messagesTabImage: UIImage {
        let base = UIImage(systemName: messagesSymbolName, withConfiguration: symbolConfig) ?? UIImage()
        let tint = colorScheme == .dark ? UIColor.white : UIColor(Color(hex: "0B1215"))
        return base.withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    private var tabImages: [UIImage] {
        if #available(iOS 26.0, *) {
            return [
                UIImage(systemName: "house.fill", withConfiguration: symbolConfig) ?? UIImage(),
                messagesTabImage,
                UIImage(systemName: "camera.aperture", withConfiguration: symbolConfig) ?? UIImage(),
                UIImage(systemName: "magnifyingglass", withConfiguration: symbolConfig) ?? UIImage(),
                profileSegmentImage
                    ?? FloatingTabProfileSegmentRenderer.personPlaceholder(colorScheme: colorScheme),
            ]
        }

        return [
            tintedTabImage(named: "house.fill"),
            messagesTabImage,
            tintedTabImage(named: "camera.aperture"),
            tintedTabImage(named: "magnifyingglass"),
            profileSegmentImage
                ?? FloatingTabProfileSegmentRenderer.personPlaceholder(colorScheme: colorScheme),
        ]
    }

    private func tintedTabImage(named name: String) -> UIImage {
        let image = UIImage(systemName: name, withConfiguration: symbolConfig) ?? UIImage()
        let tint = colorScheme == .dark ? UIColor.white : UIColor(Color(hex: "0B1215"))
        return image.withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    private var selectedTabTintColor: UIColor {
        if #available(iOS 26.0, *) {
            return UIColor(Color.gray.opacity(0.25))
        }
        return colorScheme == .dark
            ? UIColor.white.withAlphaComponent(0.18)
            : UIColor.black.withAlphaComponent(0.12)
    }

    private var tabAccessibilityLabels: [String] {
        [
            NSLocalizedString("tabBar.home", comment: "Home tab title"),
            NSLocalizedString("messaging.title", comment: "Messages tab title"),
            NSLocalizedString("creator.title", comment: "Create tab title"),
            NSLocalizedString("tabBar.explore", comment: "Explore tab title"),
            NSLocalizedString("tabBar.profile", comment: "Profile tab title"),
        ]
    }

    private var preservedTabImageIndices: Set<Int> {
        // Solo el avatar/ring mantiene colores propios.
        [4]
    }

    var body: some View {
        MomentsFloatingTabBarChrome(
            selectedTab: $selectedTab,
            showCreatorView: $showCreatorView,
            previousSelectedTab: $previousSelectedTab,
            minimize: minimize,
            badgeService: badgeService,
            profileSegmentImage: $profileSegmentImage,
            profileRenderTask: $profileRenderTask,
            verticalBarEdge: verticalBarEdge,
            tabImages: tabImages,
            selectedTabTintColor: selectedTabTintColor,
            tabAccessibilityLabels: tabAccessibilityLabels,
            preservedTabImageIndices: preservedTabImageIndices,
            momentsViewportSize: momentsViewportSize,
            divisionRegions: divisionRegions,
            colorScheme: colorScheme,
            displayScale: displayScale,
            currentUserId: currentUserId,
            refreshProfileSegmentImage: refreshProfileSegmentImage
        )
    }

    private func refreshProfileSegmentImage(forceRefresh: Bool = false) {
        let userId = currentUserId
        let scheme = colorScheme
        profileRenderTask?.cancel()
        profileRenderTask = Task { @MainActor in
            let image = await FloatingTabProfileSegmentRenderer.render(
                userId: userId,
                colorScheme: scheme,
                displayScale: displayScale,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            profileSegmentImage = image
        }
    }
}

/// Chrome real de la pill (horizontal abajo o vertical en el borde del sistema).
private struct MomentsFloatingTabBarChrome: View {
    @Binding var selectedTab: Int
    @Binding var showCreatorView: Bool
    @Binding var previousSelectedTab: Int
    @ObservedObject var minimize: TabBarMinimizeController
    @ObservedObject var badgeService: NotificationBadgeService
    @Binding var profileSegmentImage: UIImage?
    @Binding var profileRenderTask: Task<Void, Never>?
    let verticalBarEdge: HorizontalEdge?
    let tabImages: [UIImage]
    let selectedTabTintColor: UIColor
    let tabAccessibilityLabels: [String]
    let preservedTabImageIndices: Set<Int>
    let momentsViewportSize: CGSize
    let divisionRegions: [CGRect]
    let colorScheme: ColorScheme
    let displayScale: CGFloat
    let currentUserId: String
    let refreshProfileSegmentImage: (Bool) -> Void

    private var usesVerticalChrome: Bool { verticalBarEdge != nil }

    var body: some View {
        ZStack(alignment: chromeAlignment) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            pillContent
                .opacity(minimize.isHidden ? 0 : 1)
                .allowsHitTesting(!minimize.isHidden)
        }
        .animation(
            .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0),
            value: minimize.isHidden
        )
        .animation(
            .interpolatingSpring(duration: 0.28, bounce: 0.05, initialVelocity: 0),
            value: usesVerticalChrome
        )
        .onAppear { refreshProfileSegmentImage(false) }
        .onChange(of: colorScheme) { _, _ in refreshProfileSegmentImage(false) }
        .onChange(of: currentUserId) { _, _ in refreshProfileSegmentImage(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StoryUploaded"))) { _ in
            refreshProfileSegmentImage(true)
        }
        .onDisappear {
            profileRenderTask?.cancel()
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        let tabs = tabStrip
            .frame(
                width: usesVerticalChrome ? MomentsFloatingTabBarMetrics.barThickness : nil,
                height: usesVerticalChrome
                    ? MomentsFloatingTabBarMetrics.verticalStackHeight
                    : MomentsFloatingTabBarMetrics.barThickness
            )
            .padding(MomentsFloatingTabBarMetrics.chromePadding)
            .background {
                Color.clear
                    .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
            }
            .overlay { messagesBadgeOverlay }
            .scaleEffect(
                1 - (minimize.progress * 0.15),
                anchor: scaleAnchor
            )

        if usesVerticalChrome {
            tabs
                .padding(.bottom, MomentsFloatingTabBarMetrics.physicalEdgeInset)
                .padding(
                    verticalBarEdge == .leading ? .leading : .trailing,
                    MomentsFloatingTabBarMetrics.physicalEdgeInset
                )
                .ignoresSafeArea(edges: verticalBarEdge == .leading ? .leading : .trailing)
        } else {
            tabs
                .frame(maxWidth: foldSafeBarWidth)
                .frame(maxWidth: .infinity, alignment: foldSafeBarAlignment)
                .padding(.horizontal, 20)
                .padding(.bottom, MomentsFloatingTabBarMetrics.physicalEdgeInset)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private var tabStrip: some View {
        if usesVerticalChrome {
            MomentsFloatingSwiftUITabBar(
                selection: tabSelection,
                images: tabImages,
                selectedTintColor: selectedTabTintColor,
                accessibilityLabels: tabAccessibilityLabels,
                preservesImageColors: preservedTabImageIndices,
                axis: .vertical,
                onInteraction: { minimize.expand() },
                onReselect: { handleReselect($0) }
            )
        } else if #available(iOS 26.0, *) {
            MomentsFloatingSegmentedTabBar(
                selection: tabSelection,
                images: tabImages,
                selectedTintColor: selectedTabTintColor,
                accessibilityLabels: tabAccessibilityLabels,
                preservesImageColors: preservedTabImageIndices,
                onInteraction: { minimize.expand() },
                onReselect: { handleReselect($0) }
            )
        } else {
            MomentsFloatingSwiftUITabBar(
                selection: tabSelection,
                images: tabImages,
                selectedTintColor: selectedTabTintColor,
                accessibilityLabels: tabAccessibilityLabels,
                preservesImageColors: preservedTabImageIndices,
                axis: .horizontal,
                onInteraction: { minimize.expand() },
                onReselect: { handleReselect($0) }
            )
        }
    }

    @ViewBuilder
    private var messagesBadgeOverlay: some View {
        if badgeService.unreadMessagesCount > 0 {
            let layout = usesVerticalChrome
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(0..<5, id: \.self) { index in
                    Group {
                        if index == 1 {
                            ZStack(alignment: .bottomTrailing) {
                                Color.clear
                                    .frame(width: 23, height: 23)
                                CollapsingMessagesUnreadBadge(
                                    count: badgeService.unreadMessagesCount
                                )
                                .offset(x: 5, y: 3)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var chromeAlignment: Alignment {
        switch verticalBarEdge {
        case .trailing: return .bottomTrailing
        case .leading: return .bottomLeading
        case .none: return .bottom
        }
    }

    private var scaleAnchor: UnitPoint {
        switch verticalBarEdge {
        case .trailing: return .bottomTrailing
        case .leading: return .bottomLeading
        case .none: return .bottom
        }
    }

    private var activeVerticalDivision: CGRect? {
        divisionRegions.first { region in
            region.height > region.width && region.intersects(
                CGRect(origin: .zero, size: momentsViewportSize)
            )
        }
    }

    private var foldSafeBarWidth: CGFloat? {
        guard let division = activeVerticalDivision else { return nil }
        let leadingWidth = max(0, division.minX)
        let trailingWidth = max(0, momentsViewportSize.width - division.maxX)
        return max(leadingWidth, trailingWidth) - 20
    }

    private var foldSafeBarAlignment: Alignment {
        guard let division = activeVerticalDivision else { return .center }
        let leadingWidth = max(0, division.minX)
        let trailingWidth = max(0, momentsViewportSize.width - division.maxX)
        return leadingWidth >= trailingWidth ? .leading : .trailing
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab == 2 ? previousSelectedTab : selectedTab },
            set: { newValue in
                if newValue == 2 {
                    openCreator()
                    return
                }
                guard newValue != selectedTab else { return }
                HapticManager.shared.selection()
                previousSelectedTab = selectedTab
                selectedTab = newValue
            }
        )
    }

    private func handleReselect(_ index: Int) {
        if index == 0 && (selectedTab == 0 || selectedTab == 2) {
            HapticManager.shared.lightImpact()
            NotificationCenter.default.post(name: NSNotification.Name("ScrollFeedToTop"), object: nil)
        }
    }

    private func openCreator() {
        HapticManager.shared.mediumImpact()
        showCreatorView = true
        DispatchQueue.main.async {
            selectedTab = previousSelectedTab
        }
    }
}

/// Tabbar nativa SwiftUI. Horizontal (abajo) o vertical (rail Duo / multitasking).
private struct MomentsFloatingSwiftUITabBar: View {
    @Binding var selection: Int
    let images: [UIImage]
    let selectedTintColor: UIColor
    let accessibilityLabels: [String]
    let preservesImageColors: Set<Int>
    var axis: Axis = .horizontal
    let onInteraction: () -> Void
    let onReselect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))

        layout {
            ForEach(images.indices, id: \.self) { index in
                let image: UIImage = images[index]
                let imageSize: CGFloat = index == 4 ? 42 : 23
                Button {
                    onInteraction()
                    if selection == index {
                        onReselect(index)
                    } else {
                        selection = index
                    }
                } label: {
                    ZStack {
                        if selection == index {
                            Capsule()
                                .fill(Color(uiColor: selectedTintColor))
                                .padding(axis == .vertical ? .horizontal : .vertical, 3)
                        }

                        if preservesImageColors.contains(index) {
                            Image(uiImage: image)
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageSize, height: imageSize)
                        } else {
                            Image(uiImage: image)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageSize, height: imageSize)
                                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(verbatim: accessibilityLabels.indices.contains(index)
                        ? accessibilityLabels[index]
                        : "Tab \(index + 1)")
                )
                .accessibilityAddTraits(selection == index ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
