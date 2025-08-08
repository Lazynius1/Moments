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
                        // ✅ SIN frame fijo - que se adapte al contenido
                        ModernAdLoadingView()
                    } else if let nativeAd = nativeAdManager.nativeAd {
                        // ✅ SIN frame fijo - que se adapte al contenido
                        ModernNativeAdCardViewWithMediaView(nativeAd: nativeAd)
                    } else if nativeAdManager.hasError {
                        EmptyView()
                    }
                }
                .onAppear {
                    nativeAdManager.loadAd()
                    // Lógica para mostrar la pre-alerta de ATT
                    if #available(iOS 14, *) {
                        let status = ATTrackingManager.trackingAuthorizationStatus
                        if status == .notDetermined {
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
                .frame(height: 400)
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
            
            // ⭐ MediaView MÁS GRANDE (era 160, ahora 240)
            mediaView.heightAnchor.constraint(equalToConstant: 240),
            
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
        
        print("   - ✅ MediaView: 240px altura")
        print("   - ✅ Contenedor total: ~400px altura")
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

            Text("Para poder seguir ofreciéndote esta aplicación de forma gratuita, necesitamos mostrarte anuncios. Al permitir el seguimiento, nos ayudas a personalizar los anuncios para que sean más interesantes para ti.")
                .font(.custom("Poppins-Regular", size: 15))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal)

            Button {
                isPresented = false
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
                // No solicitamos el permiso ATT si el usuario no acepta la pre-alerta
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
