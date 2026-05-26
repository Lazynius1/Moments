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
    var fillsContainer: Bool = false
    var cornerRadius: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isProtected {
            SecureContentRepresentable(
                fillsContainer: fillsContainer,
                cornerRadius: cornerRadius,
                content: content
            )
        } else {
            content()
        }
    }
}

// MARK: - SecureContentRepresentable
private struct SecureContentRepresentable<Content: View>: UIViewRepresentable {
    var fillsContainer: Bool = false
    var cornerRadius: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.backgroundColor = .clear
        // Eliminar comportamiento de texto/teclado
        field.inputView = UIView()
        field.inputAccessoryView = UIView()
        field.tintColor = .clear

        let finalContent = AnyView(
            Group {
                if fillsContainer {
                    content().ignoresSafeArea(.all)
                } else {
                    content()
                }
            }
        )
        let hostingVC = UIHostingController(rootView: finalContent)
        if #available(iOS 15.0, *) {
            // Further try to remove any internal safe area padding
            if fillsContainer {
                hostingVC.safeAreaRegions = []
            }
        }
        hostingVC.view.backgroundColor = .clear
        context.coordinator.hostingVC = hostingVC

        // El contenido SwiftUI va dentro del subview interno del UITextField
        // para quedar dentro de su jerarquía segura
        let target: UIView = field.subviews.first ?? field
        applyCanvasClippingIfNeeded(to: field)
        applyCanvasClippingIfNeeded(to: target)
        applyCanvasClippingIfNeeded(to: hostingVC.view)

        target.addSubview(hostingVC.view)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        
        if fillsContainer {
            hostingVC.view.insetsLayoutMarginsFromSafeArea = false
        }

        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: target.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: target.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: target.trailingAnchor)
        ])

        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        let finalContent = AnyView(
            Group {
                if fillsContainer {
                    content().ignoresSafeArea(.all)
                } else {
                    content()
                }
            }
        )
        context.coordinator.hostingVC?.rootView = finalContent
        applyCanvasClippingIfNeeded(to: uiView)
        if let target = uiView.subviews.first {
            applyCanvasClippingIfNeeded(to: target)
        }
        if let hostingView = context.coordinator.hostingVC?.view {
            applyCanvasClippingIfNeeded(to: hostingView)
        }
    }

    // sizeThatFits (iOS 16+) — le dice a SwiftUI exactamente cuánto mide el contenido
    // para que el layout no se rompa
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        if fillsContainer {
            return nil // Let SwiftUI handle the layout filling the available space
        }
        
        guard let hostingVC = context.coordinator.hostingVC else { return nil }
        let targetSize = CGSize(
            width: proposal.width ?? UIScreen.main.bounds.width,
            height: proposal.height ?? .greatestFiniteMagnitude
        )
        return hostingVC.sizeThatFits(in: targetSize)
    }

    private func applyCanvasClippingIfNeeded(to view: UIView) {
        guard let cornerRadius else { return }
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        view.layer.cornerRadius = cornerRadius
        if #available(iOS 13.0, *) {
            view.layer.cornerCurve = .continuous
        }
    }

    class Coordinator {
        var hostingVC: UIHostingController<AnyView>?
    }
}

// MARK: - View Extension
extension View {
    /// Protege esta vista de screenshots y grabaciones de pantalla.
    /// El contenido aparece normal en la app pero sale negro en capturas.
    func screenshotProtected(
        when isProtected: Bool = true,
        fillsContainer: Bool = false,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        ScreenshotProtectedView(
            isProtected: isProtected,
            fillsContainer: fillsContainer,
            cornerRadius: cornerRadius
        ) { self }
    }
}
