import SwiftUI
import UIKit

// MARK: - ScreenshotProtectedView
// El contenido se renderiza DENTRO de un UITextField con isSecureTextEntry = true.
// El OS excluye automáticamente de screenshots y grabaciones todo lo que esté
// en la jerarquía de vistas de ese UITextField.
// En uso normal: el contenido se ve con normalidad.
// En screenshot/grabación: el OS lo muestra en negro.

struct ScreenshotProtectedView<Content: View>: View {
    let isProtected: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isProtected {
            SecureContentRepresentable(content: content)
        } else {
            content()
        }
    }
}

// MARK: - SecureContentRepresentable
private struct SecureContentRepresentable<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.textContentType = .none
        // Eliminar comportamiento de texto/teclado
        field.inputView = UIView()
        field.inputAccessoryView = UIView()
        field.tintColor = .clear

        let hostingVC = UIHostingController(rootView: content())
        hostingVC.view.backgroundColor = .clear
        context.coordinator.hostingVC = hostingVC

        // El contenido SwiftUI va dentro del subview interno del UITextField
        // para quedar dentro de su jerarquía segura
        let target: UIView = field.subviews.first ?? field
        target.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: target.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: target.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: target.trailingAnchor)
        ])

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.hostingVC?.rootView = content()
    }

    // sizeThatFits (iOS 16+) — le dice a SwiftUI exactamente cuánto mide el contenido
    // para que el layout no se rompa
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        guard let hostingVC = context.coordinator.hostingVC else { return nil }
        let targetSize = CGSize(
            width: proposal.width ?? UIScreen.main.bounds.width,
            height: proposal.height ?? .greatestFiniteMagnitude
        )
        return hostingVC.sizeThatFits(in: targetSize)
    }

    class Coordinator {
        var hostingVC: UIHostingController<Content>?
    }
}

// MARK: - View Extension
extension View {
    /// Protege esta vista de screenshots y grabaciones de pantalla.
    /// El contenido aparece normal en la app pero sale negro en capturas.
    func screenshotProtected(when isProtected: Bool = true) -> some View {
        ScreenshotProtectedView(isProtected: isProtected) { self }
    }
}
