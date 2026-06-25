import SwiftUI
import GoogleMobileAds
import UIKit
import AppTrackingTransparency
import AdSupport

// MARK: - SwiftUI Native Ad View
struct SwiftUINativeAdView: View {
    @StateObject private var adManager = NativeAdManager()

    var body: some View {
        VStack(spacing: 0) {
            if adManager.isLoading {
                ModernAdLoadingView()
            } else if let nativeAd = adManager.nativeAd {
                ModernNativeAdCardViewWithMediaView(nativeAd: nativeAd)
            } else if adManager.hasError {
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
    @State private var showingPrivacyConsent = false

    var body: some View {
        Group {
            if shouldShowAds {
                VStack(spacing: 0) {
                    if nativeAdManager.isLoading {
                        IntegratedAdLoadingView()
                    } else if let nativeAd = nativeAdManager.nativeAd {
                        IntegratedNativeAdView(nativeAd: nativeAd)
                    } else if nativeAdManager.hasError {
                        EmptyView()
                    }
                }
                .onAppear {
                    nativeAdManager.loadAd()
                    
                    // Verificar si necesitamos mostrar el flujo de privacidad (Intro + UMP + ATT)
                    if AdMobConfiguration.shared.shouldShowConsentFlow {
                        showingPrivacyConsent = true
                    }
                }
            } else {
                EmptyView()
            }
        }
        .fullScreenCover(isPresented: $showingPrivacyConsent) {
            PrivacyConsentView(isPresented: $showingPrivacyConsent) {
                // Callback: Usuario aceptó intro, iniciar flujo real
                AdMobConfiguration.shared.startConsentFlow {
                    nativeAdManager.loadAd()
                }
            }
            .presentationBackground(.clear)
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
                SwiftUINativeAdView()
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Vista de carga moderna
struct ModernAdLoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ad.common.ad")
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
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

            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(height: 240)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                    )
                    .shimmer(isAnimating: isAnimating)

                VStack(spacing: 10) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 150, height: 18)
                            .shimmer(isAnimating: isAnimating)
                        Spacer()
                    }

                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 220, height: 16)
                            .shimmer(isAnimating: isAnimating)
                        Spacer()
                    }

                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .frame(width: 150, height: 44)
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

// MARK: - Vista del anuncio nativo con MediaView
struct ModernNativeAdCardViewWithMediaView: View {
    let nativeAd: NativeAd

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ad.common.ad")
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
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

            FeedNativeAdMediaViewRepresentable(nativeAd: nativeAd)
                .frame(height: 500)
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

// MARK: - MediaView UIViewRepresentable para Feed
struct FeedNativeAdMediaViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.backgroundColor = UIColor.systemGray6
        mediaView.layer.cornerRadius = 16
        mediaView.clipsToBounds = true
        mediaView.mediaContent = nativeAd.mediaContent
        nativeAdView.mediaView = mediaView
        
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
        }
        
        // ✅ CORREGIDO: Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline ?? "Título del anuncio"
        headlineLabel.font = UIFont.systemFont(ofSize: legacyPoppinsSize(18), weight: .semibold) ?? UIFont.boldSystemFont(ofSize: 18)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel
        
        // ✅ CORREGIDO: Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body ?? "Descripción del anuncio"
        bodyLabel.font = UIFont.systemFont(ofSize: legacyPoppinsSize(15)) ?? UIFont.systemFont(ofSize: legacyPoppinsSize(15))
        bodyLabel.textColor = .white.withAlphaComponent(0.9)
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel
        
        // ✅ QUITADO: CTA Button - No necesario, el tapping general funciona
        // let callToActionButton = UIButton(type: .system)
        // callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        // callToActionButton.titleLabel?.font = UIFont.systemFont(ofSize: legacyPoppinsSize(16), weight: .semibold) ?? UIFont.boldSystemFont(ofSize: 16)
        // callToActionButton.setTitleColor(.white, for: .normal)
        // callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        // callToActionButton.layer.cornerRadius = 16
        // callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.callToActionView = callToActionButton
        
        
        // AdChoices (REQUERIDO - maneja la atribucion automaticamente)
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView
        
        // Agregar elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        nativeAdView.addSubview(adChoicesView)
        
        // Constraints sin superposiciones - NINGUN elemento sobre otro
        NSLayoutConstraint.activate([
            // MediaView - parte superior
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            mediaView.heightAnchor.constraint(equalToConstant: 300),
            
            // AdChoices - debajo del media, alineado a la derecha (NO superpuesto)
            adChoicesView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 12),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // Headline - debajo del media, al lado izquierdo
            headlineLabel.centerYAnchor.constraint(equalTo: adChoicesView.centerYAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: adChoicesView.leadingAnchor, constant: -8),
            
            // Body - debajo del headline
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            bodyLabel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {}
        func videoControllerDidPauseVideo(_ videoController: VideoController) {}
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {}
        func videoControllerDidMuteVideo(_ videoController: VideoController) {}
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {}
    }
}

// MARK: - ATT Pre-Alert View con Glassmorphism

// MARK: - Vista de carga integrada al feed
struct IntegratedAdLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                    .shimmer(isAnimating: isAnimating)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .frame(width: 120, height: 14)
                        .shimmer(isAnimating: isAnimating)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 12)
                        .shimmer(isAnimating: isAnimating)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("ad.common.ad")
                        .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                    
                    let personalizationStatus = AdMobConfiguration.shared.getAdPersonalizationStatus()
                    Text(personalizationStatus.isPersonalized ? "Personalizado" : "No personalizado")
                        .font(.system(size: legacyPoppinsSize(8)))
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
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 400)
                .shimmer(isAnimating: isAnimating)
            
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

// MARK: - Anuncio nativo integrado al feed
struct IntegratedNativeAdView: View {
    let nativeAd: NativeAd
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon = nativeAd.icon {
                    AsyncImage(url: URL(string: icon.imageURL?.absoluteString ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "app.fill")
                            .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nativeAd.advertiser ?? "Anunciante")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(.primary)
                    // Ad badge handled by UIKit's adAttributionView
                    
                    Text("ad.common.sponsored")
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            
            ZStack(alignment: .bottomLeading) {
                IntegratedAdMediaView(nativeAd: nativeAd)
                    .frame(height: 380) // Media 300 + headline/body ~80
                // UIKit handles headline/body display - no SwiftUI overlay needed
            }
            .cornerRadius(16) // Rounded corners without clipping content
            // ✅ CORREGIDO: Botón SwiftUI eliminado - solo usamos el botón nativo de AdMob
        }
        .background(colorScheme == .dark ? Color(hex: "121212") : Color.white)
        .cornerRadius(20)
        // ✅ Sistema de sombras multi-nivel (Efecto de profundidad premium)
        .shadow(color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.12), radius: 15, x: 0, y: 10)
        .shadow(color: colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.08), radius: 1, x: 0, y: 1)
        .padding(.horizontal, 8)
    }
}

// MARK: - MediaView integrado
struct IntegratedAdMediaView: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.backgroundColor = UIColor.systemGray6
        mediaView.layer.cornerRadius = 16
        mediaView.clipsToBounds = true
        mediaView.mediaContent = nativeAd.mediaContent
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.mediaView = mediaView
        
        // AdChoices (REQUERIDO - maneja la atribucion automaticamente)
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView
        
        // Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.font = UIFont.systemFont(ofSize: legacyPoppinsSize(16), weight: .semibold) ?? UIFont.boldSystemFont(ofSize: 16)
        headlineLabel.textColor = .label
        headlineLabel.numberOfLines = 2
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel
        
        // Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body
        bodyLabel.font = UIFont.systemFont(ofSize: legacyPoppinsSize(14)) ?? UIFont.systemFont(ofSize: legacyPoppinsSize(14))
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel
        
        // ✅ QUITADO: CTA Button - No necesario, el tapping general funciona
        // let callToActionButton = UIButton(type: .system)
        // callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        // callToActionButton.titleLabel?.font = UIFont.systemFont(ofSize: legacyPoppinsSize(16), weight: .semibold) ?? UIFont.boldSystemFont(ofSize: 16)
        // callToActionButton.setTitleColor(.white, for: .normal)
        // callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        // callToActionButton.layer.cornerRadius = 16
        // callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.callToActionView = callToActionButton
        
        
        // ✅ QUITADO: Advertiser - Redundante con header
        // let advertiserLabel = UILabel()
        // advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        // advertiserLabel.font = UIFont.systemFont(ofSize: legacyPoppinsSize(14), weight: .semibold) ?? UIFont.boldSystemFont(ofSize: 14)
        // advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        // advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.advertiserView = advertiserLabel
        
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
        }
        
        // Agregar elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        nativeAdView.addSubview(adChoicesView)
        
        // Constraints sin superposiciones - NINGUN elemento sobre otro
        NSLayoutConstraint.activate([
            // MediaView - parte superior
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor),
            mediaView.heightAnchor.constraint(equalToConstant: 300),
            
            // AdChoices - debajo del media, alineado a la derecha (NO superpuesto)
            adChoicesView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 12),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            
            // Headline - debajo del media, al lado izquierdo
            headlineLabel.centerYAnchor.constraint(equalTo: adChoicesView.centerYAnchor),
            headlineLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            headlineLabel.trailingAnchor.constraint(equalTo: adChoicesView.leadingAnchor, constant: -8),
            
            // Body - debajo del headline
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            bodyLabel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -12)
            
            // ✅ QUITADO: CTA Button constraints - No necesario, el tapping general funciona
            // callToActionButton.topAnchor.constraint(equalTo: advertiserLabel.bottomAnchor, constant: 16),
            // callToActionButton.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            // callToActionButton.heightAnchor.constraint(equalToConstant: 44),
            // callToActionButton.widthAnchor.constraint(equalToConstant: 150),
            // callToActionButton.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {}
        func videoControllerDidPauseVideo(_ videoController: VideoController) {}
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {}
        func videoControllerDidMuteVideo(_ videoController: VideoController) {}
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {}
    }
}
