import SwiftUI
import CoreMotion
import UIKit

struct SidebarMenuView: View {
    @EnvironmentObject private var authService: AuthService
    @Binding var isShowingSidebar: Bool
    @Binding var selectedTab: Int

    @State private var dragOffset: CGFloat = 0.0

    enum Destination: String, CaseIterable {
        case explore = "Explorar"
        case moments = "Momentos"
        case messages = "Mensajes"
        case notifications = "Notificaciones"
        case blockedUsers = "Usuarios Bloqueados"
        case settings = "Configuración"
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = geometry.size.width * 0.7
            ZStack {
                // Fondo difuminado
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
                    .opacity(isShowingSidebar ? 0.8 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSidebar()
                    }

                // Barra lateral
                VStack(alignment: .leading, spacing: 0) {
                    // Encabezado
                    HStack {
                        Text("Menú")
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            closeSidebar()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: "00A896").opacity(0.7), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                    // Separador
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 10)

                    // Elementos del menú
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Destination.allCases, id: \.self) { destination in
                                menuItem(for: destination)
                                    .opacity(isShowingSidebar ? 1.0 : 0)
                                    .scaleEffect(isShowingSidebar ? 1.0 : 0.9)
                                    .animation(
                                        .spring(response: 0.4, dampingFraction: 0.9)
                                            .delay(Double(Destination.allCases.firstIndex(of: destination)!) * 0.1),
                                        value: isShowingSidebar
                                    )
                            }
                        }
                        .padding(.top, 10)
                    }
                    Spacer()
                }
                .frame(width: sidebarWidth)
                .background(
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        LinearGradient(
                            colors: [
                                Color(hex: "00A896").opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.blue.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.softLight)
                    }
                    .innerShadow(radius: 20, opacity: 0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    Color(hex: "00A896").opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.black.opacity(0.5), radius: 15, x: 10, y: 0)
                .offset(x: isShowingSidebar ? dragOffset : -sidebarWidth)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                dragOffset = max(value.translation.width, -sidebarWidth)
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -100 {
                                closeSidebar()
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: isShowingSidebar)
            }
        }
        .ignoresSafeArea()
        .onChange(of: isShowingSidebar) { newValue in
            if !newValue {
                dragOffset = 0
            }
        }
    }

    // Construye cada elemento del menú
    @ViewBuilder
    private func menuItem(for destination: Destination) -> some View {
        Group {
            if destination == .blockedUsers || destination == .settings || destination == .notifications {
                NavigationLink(destination: destinationView(for: destination)) {
                    menuItemContent(for: destination, isSelected: false)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    closeSidebar()
                })
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        isShowingSidebar = false
                        switch destination {
                        case .explore:
                            selectedTab = 1
                        case .moments:
                            selectedTab = 2
                        case .messages:
                            selectedTab = 3
                        default:
                            break
                        }
                    }
                }) {
                    menuItemContent(for: destination, isSelected: selectedTab == tabIndex(for: destination))
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .scaleEffect(selectedTab == tabIndex(for: destination) ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: selectedTab)
    }

    // Contenido visual de cada elemento del menú
    private func menuItemContent(for destination: Destination, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForDestination(destination))
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .white : Color(hex: "00A896"))
            Text(destination.rawValue)
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(isSelected ? .white : .white.opacity(0.9))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if isSelected {
                    LinearGradient(
                        colors: [Color(hex: "00A896").opacity(0.7), Color(hex: "00A896").opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .innerShadow(radius: 10, opacity: 0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.white.opacity(0.8) : Color(hex: "00A896").opacity(0.7),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
    }

    // Obtiene el índice de la pestaña correspondiente a cada destino
    private func tabIndex(for destination: Destination) -> Int {
        switch destination {
        case .explore: return 1
        case .moments: return 2
        case .messages: return 3
        default: return 0
        }
    }

    // Cierra la barra lateral con animación
    private func closeSidebar() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            isShowingSidebar = false
            dragOffset = 0
        }
    }

    // Vista de destino para NavigationLink
    private func destinationView(for destination: Destination) -> some View {
        switch destination {
        case .blockedUsers:
            return AnyView(BlockedUsersView())
        case .settings:
            return AnyView(SettingsView())
        case .notifications:
            return AnyView(NotificationsView())
        default:
            return AnyView(EmptyView())
        }
    }

    // Ícono correspondiente a cada destino
    private func iconForDestination(_ destination: Destination) -> String {
        switch destination {
        case .explore: return "magnifyingglass"
        case .moments: return "plus.circle.fill"
        case .messages: return "message.fill"
        case .notifications: return "bell.fill"
        case .blockedUsers: return "hand.raised.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// Motion Manager para detectar inclinación
class MotionManager: ObservableObject {
    static let shared = MotionManager()
    private let motionManager = CMMotionManager()

    func startMonitoring(tiltHandler: @escaping (Double) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { data, error in
            if let attitude = data?.attitude {
                let tilt = attitude.roll // Inclinación en eje X
                tiltHandler(tilt)
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// Custom InnerShadow modifier
extension View {
    func innerShadow(radius: CGFloat, opacity: Double) -> some View {
        self
            .overlay(
                ZStack {
                    Rectangle()
                        .fill(.clear)
                        .shadow(color: Color.black.opacity(opacity), radius: radius, x: 0, y: 0)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .blendMode(.multiply)
                }
            )
    }
}

struct VisualEffectView: UIViewRepresentable {
    let effect: UIBlurEffect

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}


struct SidebarMenuView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarMenuView(
            isShowingSidebar: .constant(true),
            selectedTab: .constant(0)
        )
        .environmentObject(AuthService())
        .background(Color.black)
    }
}
