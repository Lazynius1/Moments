import SwiftUI
import GoogleMobileAds
import UIKit
import AppTrackingTransparency
import AdSupport

// MARK: - SwiftUI Native Ad View
struct NativeAdView: View {
    @StateObject private var adManager = NativeAdManager()

    var body: some View {
        VStack(spacing: 0) {
            if adManager.isLoading {
                // ✅ SIN frame fijo - que se adapte
                ModernAdLoadingView()
            } else if let nativeAd = adManager.nativeAd {
                // ✅ SIN frame fijo - que se adapte
                ModernNativeAdCardViewWithMediaView(nativeAd: nativeAd)
            } else if adManager.hasError {
                // Vista de error (opcional, o simplemente no mostrar nada)
                EmptyView()
            }
        }
        .onAppear {
            adManager.loadAd()
        }
    }
}

// MARK: - Smart Native Ad View para Plus Users
struct SmartNativeAdView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var nativeAdManager = NativeAdManager()
    @State private var showingATTPreAlert = false

    var body: some View {
        Group {
            if shouldShowAds {
                // Mostrar anuncio para usuarios no Plus
                VStack(spacing: 0) {
                    if nativeAdManager.isLoading {
                        // ✅ Vista de carga integrada al feed
                        IntegratedAdLoadingView()
                    } else if let nativeAd = nativeAdManager.nativeAd {
                        // ✅ Anuncio integrado al feed
                        IntegratedNativeAdView(nativeAd: nativeAd)
                    } else if nativeAdManager.hasError {
                        EmptyView()
                    }
                }
                .onAppear {
                    nativeAdManager.loadAd()
                    // Lógica para mostrar la pre-alerta de ATT
                    if #available(iOS 14, *) {
                        let status = ATTrackingManager.trackingAuthorizationStatus
                        let userDeclined = UserDefaults.standard.bool(forKey: "userDeclinedATTAlert")
                        
                        // Solo mostrar si no se ha determinado Y el usuario no la rechazó antes
                        if status == .notDetermined && !userDeclined {
                            showingATTPreAlert = true
                        }
                    }
                }
            } else {
                // Usuario Plus - no mostrar nada
                EmptyView()
            }
        }
        .sheet(isPresented: $showingATTPreAlert) {
            ATTPreAlertView(isPresented: $showingATTPreAlert)
        }
    }

    private var shouldShowAds: Bool {
        guard let user = authService.currentUser else { return true }
        return !user.shouldHideAds
    }
}

struct CleanNativeAdView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
                NativeAdView()
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Vista de carga moderna (mantener igual)
struct ModernAdLoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            // Header con "Anuncio"
            HStack {
                Text("Anuncio")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Contenido de carga MÁS GRANDE
            VStack(spacing: 16) {
                // ⭐ Imagen placeholder MÁS GRANDE
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(height: 240) // ⭐ AUMENTADO de 180 a 240
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 50)) // ⭐ AUMENTADO
                            .foregroundColor(.gray.opacity(0.5))
                    )
                    .shimmer(isAnimating: isAnimating)

                // Texto placeholder
                VStack(spacing: 10) { // ⭐ AUMENTADO spacing
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 150, height: 18) // ⭐ AUMENTADO
                            .shimmer(isAnimating: isAnimating)
                        Spacer()
                    }

                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 220, height: 16) // ⭐ AUMENTADO
                            .shimmer(isAnimating: isAnimating)
                        Spacer()
                    }

                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 150, height: 44) // ⭐ Botón placeholder más grande
                            .shimmer(isAnimating: isAnimating)
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 15)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - ✅ NUEVO: Vista del anuncio nativo con MediaView
struct ModernNativeAdCardViewWithMediaView: View {
    let nativeAd: NativeAd

    var body: some View {
        VStack(spacing: 12) {
            // Header con "Anuncio"
            HStack {
                Text("Anuncio")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // ✅ NUEVO: Contenido del anuncio usando MediaView
            FeedNativeAdMediaViewRepresentable(nativeAd: nativeAd)
                .frame(height: 500) // ⭐ AUMENTADO de 400 a 500 para cumplir requisitos de Google
                .padding(.horizontal, 15)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 15)
    }
}

// MARK: - ✅ ACTUALIZADO: MediaView UIViewRepresentable para Feed
struct FeedNativeAdMediaViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        print("🎯 Creando FeedNativeAd con tamaños optimizados")
        
        // Crear MediaView con tamaño optimizado
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = UIColor.systemGray6
        mediaView.layer.cornerRadius = 16
        mediaView.clipsToBounds = true
        
        // Configurar el MediaView con el anuncio
        mediaView.mediaContent = nativeAd.mediaContent
        
        // Si hay video, empezar muted (correcto para feed)
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
            print("   - ✅ Video configurado CON mute para feed")
        }
        
        // Crear stack view para el layout
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16 // ⭐ AUMENTADO spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Contenedor de texto
        let textContainer = UIView()
        textContainer.backgroundColor = .clear
        
        // Título con mejor tamaño
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline ?? "Título del anuncio"
        headlineLabel.font = UIFont(name: "Poppins-SemiBold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18) // ⭐ AUMENTADO
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 2
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Descripción con mejor tamaño
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body ?? "Descripción del anuncio"
        bodyLabel.font = UIFont(name: "Poppins-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15) // ⭐ AUMENTADO
        bodyLabel.textColor = .white.withAlphaComponent(0.8)
        bodyLabel.numberOfLines = 3
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Botón de llamada a la acción más grande
        let callToActionButton = UIButton(type: .system)
        callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        callToActionButton.titleLabel?.font = UIFont(name: "Poppins-SemiBold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16) // ⭐ AUMENTADO
        callToActionButton.setTitleColor(.white, for: .normal)
        callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        callToActionButton.layer.cornerRadius = 16 // ⭐ AUMENTADO
        callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Agregar elementos al contenedor de texto
        textContainer.addSubview(headlineLabel)
        textContainer.addSubview(bodyLabel)
        textContainer.addSubview(callToActionButton)
        
        // Agregar elementos al stack
        stackView.addArrangedSubview(mediaView)
        stackView.addArrangedSubview(textContainer)
        
        containerView.addSubview(stackView)
        
        // ✅ CONSTRAINTS OPTIMIZADOS para mejor tamaño
        NSLayoutConstraint.activate([
            // Stack view
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            
            // ⭐ MediaView MÁS GRANDE (era 240, ahora 300)
            mediaView.heightAnchor.constraint(equalToConstant: 300),
            
            // Título
            headlineLabel.topAnchor.constraint(equalTo: textContainer.topAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            
            // Descripción
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            
            // ⭐ Botón MÁS GRANDE
            callToActionButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 16),
            callToActionButton.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            callToActionButton.heightAnchor.constraint(equalToConstant: 44), // ⭐ AUMENTADO de 36 a 44
            callToActionButton.widthAnchor.constraint(equalToConstant: 150), // ⭐ AUMENTADO de 120 a 150
            callToActionButton.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor)
        ])
        
        print("   - ✅ MediaView: 300px altura")
        print("   - ✅ Contenedor total: ~500px altura")
        print("   - ✅ Botón CTA: 150x44px")
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Actualizar contenido si es necesario
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio en feed empezó")
        }
        
        func videoControllerDidPauseVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio en feed pausado")
        }
        
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {
            print("🎯 Video del anuncio en feed terminó")
        }
        
        func videoControllerDidMuteVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio en feed silenciado")
        }
        
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio en feed con sonido")
        }
    }
}

// MARK: - ATT Pre-Alert View (mantener igual)
struct ATTPreAlertView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(Color(hex: "00A896"))

            Text("Ayúdanos a mostrarte anuncios más relevantes")
                .font(.custom("Poppins-SemiBold", size: 20))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .foregroundColor(.white)

            Text("Para poder seguir ofreciéndote esta aplicación de forma gratuita, necesitamos mostrarte anuncios. Al permitir el seguimiento, nos ayudas a personalizar los anuncios para que sean más interesantes para ti. Si prefieres no permitir el seguimiento, seguirás viendo anuncios pero serán menos relevantes para tus intereses.")
                .font(.custom("Poppins-Regular", size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal)

            Button {
                isPresented = false
                // Limpiar la preferencia cuando acepta
                UserDefaults.standard.removeObject(forKey: "userDeclinedATTAlert")
                AdMobConfiguration.shared.requestATTAuthorization()
            } label: {
                Text("Permitir seguimiento")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "00A896"))
                    .cornerRadius(15)
            }
            .padding(.horizontal)

            Button {
                isPresented = false
                // Guardar que el usuario no quiere ver la alerta de nuevo
                UserDefaults.standard.set(true, forKey: "userDeclinedATTAlert")
            } label: {
                Text("No, gracias")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal)
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color(hex: "282C34"))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - ✅ NUEVO: Vista de carga integrada al feed
struct IntegratedAdLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con avatar y info
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                    .shimmer(isAnimating: isAnimating)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Nombre placeholder
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .frame(width: 120, height: 14)
                        .shimmer(isAnimating: isAnimating)
                    
                    // Subtítulo placeholder
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 12)
                        .shimmer(isAnimating: isAnimating)
                }
                
                Spacer()
                
                // Badge "Anuncio"
                VStack(spacing: 2) {
                    Text("Anuncio")
                        .font(.custom("Poppins-Medium", size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                    
                    // Indicador de personalización
                    let personalizationStatus = AdMobConfiguration.shared.getAdPersonalizationStatus()
                    Text(personalizationStatus.isPersonalized ? "Personalizado" : "No personalizado")
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(personalizationStatus.isPersonalized ? .green : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(personalizationStatus.isPersonalized ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Media placeholder (imagen/video)
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 400) // ✅ Tamaño fijo más grande para Google
                .shimmer(isAnimating: isAnimating)
            
            // Footer con botón
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 36)
                    .shimmer(isAnimating: isAnimating)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - ✅ NUEVO: Anuncio nativo integrado al feed
struct IntegratedNativeAdView: View {
    let nativeAd: NativeAd
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con avatar y info
            HStack(spacing: 12) {
                // Avatar del anunciante
                if let icon = nativeAd.icon {
                    AsyncImage(url: URL(string: icon.imageURL?.absoluteString ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(.ultraThinMaterial)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Nombre del anunciante
                    Text(nativeAd.advertiser ?? "Anunciante")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.primary)
                    
                    // Subtítulo
                    Text("Anuncio patrocinado")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Badge "Anuncio"
                Text("Anuncio")
                    .font(.custom("Poppins-Medium", size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Media del anuncio
            IntegratedAdMediaView(nativeAd: nativeAd)
                .frame(height: 400) // ✅ Tamaño fijo más grande para Google
            
            // Footer con botón de acción
            HStack {
                Button(action: {
                    // Acción del botón
                }) {
                    Text(nativeAd.callToAction ?? "Más información")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

// MARK: - ✅ NUEVO: MediaView integrado
struct IntegratedAdMediaView: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        print("🎯 Creando IntegratedAdMediaView con tamaño optimizado para Google")
        
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = UIColor.systemGray6
        mediaView.layer.cornerRadius = 8
        mediaView.clipsToBounds = true
        mediaView.mediaContent = nativeAd.mediaContent
        
        // ✅ CRÍTICO: Registrar el MediaView con el NativeAd para que Google lo detecte
        nativeAd.register(mediaView, clickableAssetViews: [:], nonclickableAssetViews: [:])
        
        print("   - ✅ MediaContent asignado: \(nativeAd.mediaContent.hasVideoContent ? "Video" : "Imagen")")
        print("   - ✅ MediaView registrado con NativeAd")
        
        // Configurar video si existe
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
            print("   - ✅ Video configurado CON mute para feed integrado")
        }
        
        containerView.addSubview(mediaView)
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            mediaView.topAnchor.constraint(equalTo: containerView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            // ✅ CRÍTICO: GARANTIZAR TAMAÑO MÍNIMO requerido por Google
            mediaView.heightAnchor.constraint(equalToConstant: 400), // Tamaño fijo más grande para Google
            mediaView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)   // Mínimo 150px, pero flexible
        ])
        
        print("   - ✅ MediaView: mínimo 300x150px (requerido por Google)")
        print("   - ✅ Aspect ratio: flexible pero respeta mínimos")
        print("   - ✅ Container size: \(containerView.frame.size)")
        print("   - ✅ MediaView size: \(mediaView.frame.size)")
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Actualizar si es necesario
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio integrado empezó")
        }
        
        func videoControllerDidPauseVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio integrado pausado")
        }
        
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {
            print("🎯 Video del anuncio integrado terminó")
        }
        
        func videoControllerDidMuteVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio integrado silenciado")
        }
        
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {
            print("🎯 Video del anuncio integrado con sonido")
        }
    }
}
