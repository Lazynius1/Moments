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
    @State private var showingATTPreAlert = false

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
                    if #available(iOS 14, *) {
                        let status = ATTrackingManager.trackingAuthorizationStatus
                        let hasSeen = UserDefaults.standard.bool(forKey: "hasSeenATTPreAlert")
                        
                        if status == .notDetermined && !hasSeen {
                            showingATTPreAlert = true
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showingATTPreAlert) {
            ATTPreAlertView(isPresented: $showingATTPreAlert)
                .presentationBackground(.clear)
                .onDisappear {
                    UserDefaults.standard.set(true, forKey: "hasSeenATTPreAlert")
                }
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
        headlineLabel.font = UIFont(name: "Poppins-SemiBold", size: 18) ?? UIFont.boldSystemFont(ofSize: 18)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel
        
        // ✅ CORREGIDO: Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body ?? "Descripción del anuncio"
        bodyLabel.font = UIFont(name: "Poppins-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        bodyLabel.textColor = .white.withAlphaComponent(0.9)
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel
        
        // ✅ QUITADO: CTA Button - No necesario, el tapping general funciona
        // let callToActionButton = UIButton(type: .system)
        // callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        // callToActionButton.titleLabel?.font = UIFont(name: "Poppins-SemiBold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        // callToActionButton.setTitleColor(.white, for: .normal)
        // callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        // callToActionButton.layer.cornerRadius = 16
        // callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.callToActionView = callToActionButton
        
        
        // ✅ CORREGIDO: Ad Attribution personalizado (REQUERIDO por Google)
        let adAttributionView = UIView()
        adAttributionView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        adAttributionView.layer.cornerRadius = 3
        adAttributionView.translatesAutoresizingMaskIntoConstraints = false
        
        let adAttributionLabel = UILabel()
        adAttributionLabel.text = "Ad"
        adAttributionLabel.font = UIFont(name: "Poppins-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
        adAttributionLabel.textColor = .white
        adAttributionLabel.textAlignment = .center
        adAttributionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        adAttributionView.addSubview(adAttributionLabel)
        
        // ✅ CORREGIDO: Advertiser (REQUERIDO para atribución)
        let advertiserLabel = UILabel()
        advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        advertiserLabel.font = UIFont(name: "Poppins-SemiBold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.advertiserView = advertiserLabel
        
        // ✅ CORREGIDO: AdChoices (REQUERIDO para atribución)
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView
        
        // ✅ CORREGIDO: Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        // nativeAdView.addSubview(callToActionButton) // ✅ QUITADO: CTA Button
        nativeAdView.addSubview(advertiserLabel)
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.addSubview(adAttributionView)
        
        // ✅ CORREGIDO: Constraints sin superposiciones según Google AdMob
        NSLayoutConstraint.activate([
            // MediaView - parte superior (sin elementos superpuestos)
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            mediaView.heightAnchor.constraint(equalToConstant: 300),
            
            // Ad Attribution - debajo del media (no superpuesto)
            adAttributionView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adAttributionView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            adAttributionView.widthAnchor.constraint(equalToConstant: 25),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            // Ad Attribution Label constraints
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices - debajo del media (no superpuesto)
            adChoicesView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // Headline - debajo del Ad Attribution y AdChoices (sin superposiciones)
            headlineLabel.topAnchor.constraint(equalTo: adAttributionView.bottomAnchor, constant: 16),
            headlineLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // Body - debajo del headline
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            
            // Advertiser - debajo del body - AHORA ES EL ÚLTIMO ELEMENTO
            advertiserLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            advertiserLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            advertiserLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            advertiserLabel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
            
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

// MARK: - ATT Pre-Alert View con Glassmorphism
struct ATTPreAlertView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(hex: "00A896").opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 16) {
                Text(NSLocalizedString("attPreAlert.title", comment: "ATT Pre-Alert title"))
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                VStack(spacing: 12) {
                    Text(NSLocalizedString("attPreAlert.description", comment: "ATT Pre-Alert description"))
                        .font(.custom("Poppins-Regular", size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text(NSLocalizedString("attPreAlert.info", comment: "ATT Pre-Alert info message"))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "00A896").opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "00A896").opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 12) {
                Button {
                    isPresented = false
                    AdMobConfiguration.shared.requestATTAuthorization()
                } label: {
                    Text(NSLocalizedString("attPreAlert.continueButton", comment: "ATT Pre-Alert continue button"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color(hex: "00A896"))
                        )
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "00A896").opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 20)
    }
}

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
                    Text("Anuncio")
                        .font(.custom("Poppins-Medium", size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                    
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
                    HStack(spacing: 4) {
                        Text(nativeAd.advertiser ?? "Anunciante")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.primary)
                        
                        // ✅ Badge de Anuncio
                        Text("Ad")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    
                    Text("Patrocinado")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            
            ZStack(alignment: .bottomLeading) {
                IntegratedAdMediaView(nativeAd: nativeAd)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                // ✅ Gradiente protector
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .allowsHitTesting(false)
                
                // ✅ Caption estilo Moment
                VStack(alignment: .leading, spacing: 4) {
                    Text(nativeAd.headline ?? "")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(nativeAd.body ?? "")
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
            }
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
        
        // Ad Attribution personalizado (REQUERIDO por Google)
        let adAttributionView = UIView()
        adAttributionView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        adAttributionView.layer.cornerRadius = 3
        adAttributionView.translatesAutoresizingMaskIntoConstraints = false
        
        let adAttributionLabel = UILabel()
        adAttributionLabel.text = "Ad"
        adAttributionLabel.font = UIFont(name: "Poppins-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
        adAttributionLabel.textColor = .white
        adAttributionLabel.textAlignment = .center
        adAttributionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        adAttributionView.addSubview(adAttributionLabel)
        
        // AdChoices
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView
        
        // Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel
        
        // Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel
        
        // ✅ QUITADO: CTA Button - No necesario, el tapping general funciona
        // let callToActionButton = UIButton(type: .system)
        // callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        // callToActionButton.titleLabel?.font = UIFont(name: "Poppins-SemiBold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        // callToActionButton.setTitleColor(.white, for: .normal)
        // callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        // callToActionButton.layer.cornerRadius = 16
        // callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.callToActionView = callToActionButton
        
        
        // Advertiser
        let advertiserLabel = UILabel()
        advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        advertiserLabel.font = UIFont(name: "Poppins-SemiBold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.advertiserView = advertiserLabel
        
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
        }
        
        // Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        // nativeAdView.addSubview(callToActionButton) // ✅ QUITADO: CTA Button
        nativeAdView.addSubview(advertiserLabel)
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.addSubview(adAttributionView)
        
        // Constraints sin superposiciones
        NSLayoutConstraint.activate([
            // MediaView - parte superior
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            mediaView.heightAnchor.constraint(equalToConstant: 300),
            
            // Ad Attribution - debajo del media (no superpuesto)
            adAttributionView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adAttributionView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            adAttributionView.widthAnchor.constraint(equalToConstant: 25),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            // Ad Attribution Label constraints
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices - debajo del media (no superpuesto)
            adChoicesView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // Headline - debajo del Ad Attribution y AdChoices (sin superposiciones)
            headlineLabel.topAnchor.constraint(equalTo: adAttributionView.bottomAnchor, constant: 16),
            headlineLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // Body - debajo del headline
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            bodyLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            
            // Advertiser - debajo del body - AHORA ES EL ÚLTIMO ELEMENTO
            advertiserLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            advertiserLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            advertiserLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            advertiserLabel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
            
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
