import SwiftUI

@MainActor
class NotificationSummaryService: ObservableObject {
    static let shared = NotificationSummaryService()
    
    @Published var shouldShowSummary = false
    
    private let userDefaults = UserDefaults.standard
    private let lastAppCloseKey = "lastAppCloseTime"
    private let summaryThresholdMinutes: Double = 30
    
    private init() {}
    
    func checkShouldShowSummary(unreadNotifications: Int, unreadMessages: Int) {
        let lastCloseTime = userDefaults.double(forKey: lastAppCloseKey)
        let now = Date().timeIntervalSince1970
        let minutesSinceLastClose = (now - lastCloseTime) / 60
        
        let shouldShow = lastCloseTime > 0 &&
                        minutesSinceLastClose >= summaryThresholdMinutes &&
                        (unreadNotifications > 0 || unreadMessages > 0)
        
        if shouldShow {
            // Pequeño delay para que la UI principal respire
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.shouldShowSummary = true
                }
            }
        }
    }
    
    func markAppClosed() {
        userDefaults.set(Date().timeIntervalSince1970, forKey: lastAppCloseKey)
    }
}

struct NotificationSummaryPopup: View {
    @Binding var isPresented: Bool
    let unreadNotifications: Int
    let unreadMessages: Int
    let colorScheme: ColorScheme
    
    @State private var appearAnimation = false
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        if isPresented {
            VStack(alignment: .trailing) {
                summaryBubble
                    .scaleEffect(scale, anchor: .topTrailing)
                    .opacity(opacity)
                    .offset(y: appearAnimation ? 0 : -20)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            // El corazón termina aproximadamente en 60 pt dentro del header.
            // Cuatro puntos dejan respirar el icono sin romper el anclaje visual.
            .padding(.top, 64)
            .padding(.trailing, 20)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 1)) {
                    appearAnimation = true
                    scale = 1.0
                    opacity = 1.0
                }
                
                // Auto-dismiss después de un tiempo razonable
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    dismissPopup()
                }
            }
        }
    }
    
    private var summaryBubble: some View {
        let shape = NotificationSummaryBubbleShape()

        return Button(action: {
            // ✅ Marcar como leídas y limpiar badge inmediatamente
            NotificationService.shared.markAllAsRead()
            NotificationBadgeService.shared.clearNotificationBadge()
            
            dismissPopup()
            
            // ✅ Navegación inteligente: Si solo hay mensajes, ir al chat
            if unreadMessages > 0 && unreadNotifications == 0 {
                LegacyNavigationBridge.showMessages()
            } else {
                LegacyNavigationBridge.showNotifications()
            }
        }) {
            HStack(spacing: 14) {
                if unreadNotifications > 0 {
                    SummaryItemView(
                        icon: "heart.fill",
                        count: unreadNotifications,
                        colors: [Color.red, Color.pink]
                    )
                }

                if unreadMessages > 0 {
                    SummaryItemView(
                        icon: "bubble.left.fill",
                        count: unreadMessages,
                        colors: [Color.blue, Color(hex: "00D2FF")]
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            // Un único material, igual que la tab bar: sin cápsulas internas.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .momentsChromeGlass(in: shape, interactive: true, style: .tinted)
            .contentShape(shape)
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.momentsPress)
        .accessibilityElement(children: .combine)
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            appearAnimation = false
            scale = 0.9
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPresented = false
        }
    }

}

/// Bocadillo anclado al corazón del header. La cola se calcula desde el borde
/// derecho para conservar el mismo punto global aunque cambie el ancho.
private struct NotificationSummaryBubbleShape: Shape {
    private let cornerRadius: CGFloat = 24
    private let tailWidth: CGFloat = 14
    private let tailHeight: CGFloat = 8
    // Header iOS: trailing 12 + Nova 36 + spacing 20 + medio corazón 18.
    // El bocadillo termina a 20 del borde, por eso su anclaje local es 66.
    private let tailTrailingInset: CGFloat = 66

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + tailHeight
        let radius = min(cornerRadius, (rect.height - tailHeight) / 2)
        let halfTail = tailWidth / 2
        let minimumTailX = rect.minX + radius + halfTail
        let maximumTailX = rect.maxX - radius - halfTail
        let tailCenterX = min(max(rect.maxX - tailTrailingInset, minimumTailX), maximumTailX)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: bodyTop))
        path.addLine(to: CGPoint(x: tailCenterX - halfTail, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: tailCenterX, y: rect.minY),
            control: CGPoint(x: tailCenterX - halfTail * 0.45, y: bodyTop)
        )
        path.addQuadCurve(
            to: CGPoint(x: tailCenterX + halfTail, y: bodyTop),
            control: CGPoint(x: tailCenterX + halfTail * 0.45, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyTop + radius),
            control: CGPoint(x: rect.maxX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: bodyTop),
            control: CGPoint(x: rect.minX, y: bodyTop)
        )
        path.closeSubpath()
        return path
    }
}

// Vista auxiliar para cada item del resumen, directamente sobre el vidrio.
struct SummaryItemView: View {
    let icon: String
    let count: Int
    let colors: [Color]
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: colors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
}
