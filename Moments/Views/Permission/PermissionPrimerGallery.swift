import SwiftUI

#if DEBUG

/// Galería de todas las pantallas de permisos, una por página, para poder verlas
/// seguidas y grabarlas sin abrir una preview por vista.
///
/// Solo se compila en DEBUG: no entra en las builds de App Store.
///
/// Cómo usarla:
/// - Preview de Xcode: la de abajo (`#Preview "Permisos — galería"`).
/// - En el simulador o en el dispositivo, que es lo mejor para grabar:
///   monta `PermissionPrimerGallery()` como vista raíz temporalmente.
///
/// Desliza en horizontal para pasar de una a otra. El botón de arriba a la
/// derecha alterna entre el estado normal y el denegado de cada pantalla.
struct PermissionPrimerGallery: View {
    @State private var selection = 0

    /// Todas las pantallas y todos sus estados como páginas seguidas: cada permiso
    /// aparece primero en normal y justo después en denegado. Así se graba del tirón
    /// deslizando, sin parar a cambiar de estado. Mismas combinaciones que las
    /// previews "Primer"/"Denied"/"Always" de cada archivo.
    private var pages: [(name: String, view: AnyView)] {
        [
            ("Cámara — Normal", AnyView(cameraView(isDenied: false))),
            ("Cámara — Denegado", AnyView(cameraView(isDenied: true))),

            ("Micrófono — Normal", AnyView(
                MicrophonePermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
            )),
            ("Micrófono — Denegado", AnyView(
                MicrophonePermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
            )),

            ("Fotos — Normal", AnyView(
                PhotosPermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
            )),
            ("Fotos — Denegado", AnyView(
                PhotosPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
            )),

            ("Ubicación — Normal", AnyView(
                LocationPermissionView(stage: .primer, accessLevel: .whenInUse, primaryAction: {}, secondaryAction: {})
            )),
            ("Ubicación — Siempre", AnyView(
                LocationPermissionView(stage: .primer, accessLevel: .always, primaryAction: {}, secondaryAction: {})
            )),
            ("Ubicación — Denegado", AnyView(
                LocationPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
            )),

            ("Notificaciones — Normal", AnyView(
                NotificationsPermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
            )),
            ("Notificaciones — Denegado", AnyView(
                NotificationsPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
            )),

            ("Seguimiento — Normal", AnyView(
                TrackingPermissionView(stage: .primer, primaryAction: {})
            )),
            ("Seguimiento — Denegado", AnyView(
                TrackingPermissionView(stage: .denied, primaryAction: {})
            ))
        ]
    }

    private func cameraView(isDenied: Bool) -> some View {
        CameraPermissionsview(
            title: NSLocalizedString(isDenied ? "permission.camera.denied.title" : "permission.camera.primer.title", comment: ""),
            description: NSLocalizedString(isDenied ? "permission.camera.denied.subtitle" : "permission.camera.primer.subtitle", comment: ""),
            primaryActionTitle: NSLocalizedString(isDenied ? "permission.camera.denied.openSettings" : "permission.camera.primer.allow", comment: ""),
            secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: ""),
            showsShutterUI: !isDenied,
            isDenied: isDenied
        ) {} secondaryAction: {} panorama: {
            Image(.pic1).resizable()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    page.view
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            chrome
        }
    }

    /// Controles de la galería. Se pueden ocultar para dejar la pantalla limpia al
    /// grabar. Ojo: solo la barra captura toques — si el contenedor ocupara toda la
    /// pantalla se comería el botón de estado y el deslizamiento entre páginas.
    @State private var showsChrome = true

    private var chrome: some View {
        Group {
            if showsChrome {
                HStack(spacing: 10) {
                    Text("\(selection + 1)/\(pages.count)  ·  \(pages[selection].name)")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsChrome = false }
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.opacity)
            } else {
                // Zona pequeña arriba para recuperar la barra sin estorbar al swipe.
                Color.clear
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showsChrome = true }
                    }
            }
        }
    }
}

#Preview("Permisos — galería") {
    PermissionPrimerGallery()
}

#endif
