import SwiftUI

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
            VStack {
                summaryPill
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .offset(y: appearAnimation ? 0 : -20)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 100) // Debajo del header
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
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
    
    private var summaryPill: some View {
        Button(action: {
            // ✅ Marcar como leídas y limpiar badge inmediatamente
            NotificationService.shared.markAllAsRead()
            NotificationBadgeService.shared.clearNotificationBadge()
            
            dismissPopup()
            
            // ✅ Navegación inteligente: Si solo hay mensajes, ir al chat
            if unreadMessages > 0 && unreadNotifications == 0 {
                NotificationCenter.default.post(name: NSNotification.Name("ShowMessages"), object: nil)
            } else {
                NotificationCenter.default.post(name: NSNotification.Name("OpenNotifications"), object: nil)
            }
        }) {
            HStack(spacing: 16) {
                // Info Badge
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "6B73FF"), Color(hex: "00A896")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(NSLocalizedString("feed.summary.highlights", comment: "Novedades"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.trailing, 4)
                
                Divider()
                    .frame(height: 16)
                    .background(Color.primary.opacity(0.1))
                
                // Estadísticas
                HStack(spacing: 15) {
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
                }
                
                // Botón cerrar sutil
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1),
                                Color(hex: "6B73FF").opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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

// Vista auxiliar para cada item del resumen
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
                .foregroundColor(.primary)
        }
    }
}
