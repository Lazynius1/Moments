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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.shouldShowSummary = shouldShow
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
    
    @State private var offset: CGFloat = -30
    
    var body: some View {
        if isPresented {
            VStack(spacing: 0) {
                // Banner rojo compacto debajo de los iconos
                HStack(spacing: 8) {
                    // Me gusta
                    if unreadNotifications > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("\(unreadNotifications)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Mensajes
                    if unreadMessages > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("\(unreadMessages)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // ✅ Seguidores (solo si hay solicitudes pendientes)
                    if unreadNotifications > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text("\(unreadNotifications)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Botón de cerrar
                    Button(action: dismissPopup) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .offset(y: offset)
                .onTapGesture {
                    dismissPopup()
                    NotificationCenter.default.post(name: NSNotification.Name("OpenNotifications"), object: nil)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                }
                
                // Auto-dismiss después de 4 segundos
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    dismissPopup()
                }
            }
        }
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = -30
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
}
