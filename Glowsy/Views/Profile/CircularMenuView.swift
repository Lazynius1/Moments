import SwiftUI
import FirebaseAuth

struct CircularMenuView: View {
    let userId: String
    @Binding var isShowing: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowing = false
                }

            // Menú circular
            ZStack {
                ForEach(0..<menuItems.count, id: \.self) { index in
                    Button(action: {
                        menuItems[index].action()
                        isShowing = false
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: "00A896").opacity(0.5), lineWidth: 1)
                                )
                            Image(systemName: menuItems[index].icon)
                                .foregroundColor(.white)
                        }
                    }
                    .offset(x: cos(CGFloat(index) * .pi / 2) * 100, y: sin(CGFloat(index) * .pi / 2) * 100)
                }
            }
            .animation(.spring(), value: isShowing)
        }
    }

    private var menuItems: [(icon: String, action: () -> Void)] {
        if userId == Auth.auth().currentUser?.uid {
            // Menú para el propio perfil
            return [
                (icon: "gearshape.fill", action: { /* Navegar a ajustes */ }),
                (icon: "photo.on.rectangle.fill", action: { /* Añadir momento */ }),
                (icon: "plus.circle.fill", action: { /* Añadir historia */ }),
                (icon: "person.crop.circle.badge.plus", action: { /* Invitar amigos */ })
            ]
        } else {
            // Menú para el perfil de otro usuario
            return [
                (icon: "flag.fill", action: { /* Reportar usuario */ }),
                (icon: "paperplane.fill", action: { /* Enviar mensaje */ }),
                (icon: "person.fill.xmark", action: { /* Bloquear usuario */ }),
                (icon: "star.fill", action: { /* Añadir a favoritos */ })
            ]
        }
    }
}

struct CircularMenuView_Previews: PreviewProvider {
    static var previews: some View {
        CircularMenuView(userId: "123", isShowing: .constant(true))
    }
}
