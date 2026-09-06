import SwiftUI
import UIKit
import FirebaseAuth

/// Medidas de la pill flotante. Overlays en safe area (menú, toasts) usan `overlayBottomPadding`.
enum MomentsFloatingTabBarMetrics {
    static let barHeight: CGFloat = 54
    static let chromePadding: CGFloat = 4
    static let physicalBottomInset: CGFloat = 18
    static let overlayGap: CGFloat = 8

    static var heightFromPhysicalBottom: CGFloat {
        barHeight + chromePadding * 2 + physicalBottomInset
    }

    static func overlayBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(20, heightFromPhysicalBottom - safeAreaBottom + overlayGap)
    }
}

/// Floating pill Moments — Home · Mensajes · Creator · Explorar · Perfil.
/// UISegmentedControl (gota arrastrable) + glass tinted. Perfil = UIImage (foto+ring).
struct MomentsFloatingTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatorView: Bool
    @Binding var previousSelectedTab: Int
    @ObservedObject var minimize: TabBarMinimizeController
    @ObservedObject private var badgeService = NotificationBadgeService.shared
    @Environment(\.colorScheme) private var colorScheme

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

    /// Paperplane (+ fill si hay no leídos) con puntito rojo cuando unread > 0.
    private var messagesTabImage: UIImage {
        let base = UIImage(systemName: messagesSymbolName, withConfiguration: symbolConfig) ?? UIImage()
        let tint = colorScheme == .dark ? UIColor.white : UIColor(Color(hex: "0B1215"))
        let tinted = base.withTintColor(tint, renderingMode: .alwaysOriginal)
        guard badgeService.unreadMessagesCount > 0 else { return tinted }
        return Self.withUnreadDot(tinted)
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
        var indices: Set<Int> = [4] // El avatar/ring mantiene sus colores propios.
        if badgeService.unreadMessagesCount > 0 {
            indices.insert(1) // Mantiene el punto rojo de mensajes no leídos.
        }
        return indices
    }

    /// Puntito (7pt) abajo-trailing — lejos de la punta del paperplane.
    private static func withUnreadDot(_ image: UIImage) -> UIImage {
        let pad: CGFloat = 4
        let dot: CGFloat = 7
        let canvas = CGSize(
            width: image.size.width + pad + 2,
            height: image.size.height + pad + 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: 0, y: 0))
            let rect = CGRect(
                x: canvas.width - dot,
                y: canvas.height - dot,
                width: dot,
                height: dot
            )
            UIColor(red: 1, green: 59 / 255, blue: 48 / 255, alpha: 1).setFill() // #FF3B30
            UIBezierPath(ovalIn: rect).fill()
        }.withRenderingMode(.alwaysOriginal)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
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
                    onInteraction: { minimize.expand() },
                    onReselect: { handleReselect($0) }
                )
            }
        }
        .frame(height: 54)
        .padding(4)
        .background {
            Color.clear
                .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(1 - (minimize.progress * 0.15), anchor: .bottom)
        .padding(.horizontal, 20)
        // Entre safe area y home indicator (~18pt de aire).
        .padding(.bottom, 18)
        .opacity(minimize.isHidden ? 0 : 1)
        .allowsHitTesting(!minimize.isHidden)
        .animation(
            .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0),
            value: minimize.isHidden
        )
        .onAppear { refreshProfileSegmentImage() }
        .onChange(of: colorScheme) { _, _ in refreshProfileSegmentImage() }
        .onChange(of: currentUserId) { _, _ in refreshProfileSegmentImage() }
        // El upload ya posta `StoryUploaded` (el feed lo usa); la tab bar no escuchaba.
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StoryUploaded"))) { _ in
            refreshProfileSegmentImage(forceRefresh: true)
        }
        .onDisappear {
            profileRenderTask?.cancel()
        }
    }

    /// El control nunca se queda en Creator (2): abre creator y restaura.
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

    private func refreshProfileSegmentImage(forceRefresh: Bool = false) {
        let userId = currentUserId
        let scheme = colorScheme
        profileRenderTask?.cancel()
        profileRenderTask = Task { @MainActor in
            let image = await FloatingTabProfileSegmentRenderer.render(
                userId: userId,
                colorScheme: scheme,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            profileSegmentImage = image
        }
    }
}

/// Tabbar nativa SwiftUI para iOS 18.x. Evita el chrome interno de
/// UISegmentedControl, que en iOS 18 vuelve a dibujar una segunda cápsula.
private struct MomentsFloatingSwiftUITabBar: View {
    @Binding var selection: Int
    let images: [UIImage]
    let selectedTintColor: UIColor
    let accessibilityLabels: [String]
    let preservesImageColors: Set<Int>
    let onInteraction: () -> Void
    let onReselect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
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
                                .padding(.vertical, 3)
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
