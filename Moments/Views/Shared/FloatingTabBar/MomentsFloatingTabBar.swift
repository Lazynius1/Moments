import SwiftUI
import UIKit
import FirebaseAuth

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

    /// Paperplane (+ fill si hay no leídos) con puntito IG rojo cuando unread > 0.
    private var messagesTabImage: UIImage {
        let base = UIImage(systemName: messagesSymbolName, withConfiguration: symbolConfig) ?? UIImage()
        let tint = colorScheme == .dark ? UIColor.white : UIColor(Color(hex: "0B1215"))
        let tinted = base.withTintColor(tint, renderingMode: .alwaysOriginal)
        guard badgeService.unreadMessagesCount > 0 else { return tinted }
        return Self.withUnreadDot(tinted)
    }

    private var tabImages: [UIImage] {
        [
            UIImage(systemName: "house.fill", withConfiguration: symbolConfig) ?? UIImage(),
            messagesTabImage,
            UIImage(systemName: "camera.aperture", withConfiguration: symbolConfig) ?? UIImage(),
            UIImage(systemName: "magnifyingglass", withConfiguration: symbolConfig) ?? UIImage(),
            profileSegmentImage
                ?? FloatingTabProfileSegmentRenderer.personPlaceholder(colorScheme: colorScheme),
        ]
    }

    /// Puntito estilo Instagram (7pt) abajo-trailing — lejos de la punta del paperplane.
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
        MomentsFloatingSegmentedTabBar(
            selection: tabSelection,
            images: tabImages,
            onInteraction: { minimize.expand() },
            onReselect: { handleReselect($0) }
        )
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
