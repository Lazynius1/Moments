import SwiftUI
import GoogleMobileAds
import UIKit

// MARK: - Story Native Ad View
struct StoryNativeAdView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var storyAdManager = StoryNativeAdManager()
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    let storyCount: Int
    let storyIndex: Int
    let screenSize: CGSize
    
    @State private var progress: Double = 0.0
    @State private var adTimer: Timer?
    @State private var debugTimer: Timer?
    @State private var hasAppeared = false
    private let adDuration: Double = 7.0

    var body: some View {
        Group {
            if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
                if storyAdManager.isLoading && hasAppeared {
                    StoryAdLoadingView(
                        storyCount: storyCount,
                        storyIndex: storyIndex,
                        progress: progress,
                        onNext: cleanupAndNext,
                        onPrevious: onPrevious,
                        onClose: onClose
                    )
                    
                } else if let nativeAd = storyAdManager.nativeAd, hasAppeared {
                    StoryAdContentViewWithMediaView(
                        nativeAd: nativeAd,
                        storyCount: storyCount,
                        storyIndex: storyIndex,
                        progress: progress,
                        screenSize: screenSize,
                        onNext: cleanupAndNext,
                        onPrevious: onPrevious,
                        onClose: onClose
                    )
                    .onAppear {
                        startAdTimer()
                    }
                    
                } else if storyAdManager.hasError && hasAppeared {
                    ZStack {
                        Color.red.opacity(0.3)
                        
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            
                            Text("Error cargando anuncio")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Saltando en 2 segundos...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            cleanupAndNext()
                        }
                    }
                    
                } else {
                    if hasAppeared {
                        StoryAdLoadingView(
                            storyCount: storyCount,
                            storyIndex: storyIndex,
                            progress: progress,
                            onNext: cleanupAndNext,
                            onPrevious: onPrevious,
                            onClose: onClose
                        )
                        .onAppear {
                            if !storyAdManager.isLoading && storyAdManager.nativeAd == nil && !storyAdManager.hasError {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    self.storyAdManager.loadStoryAd()
                                }
                            }
                        }
                    } else {
                        Color.black
                    }
                }
            } else {
                Color.clear.onAppear {
                    onNext()
                }
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            
            hasAppeared = true
            
            if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.storyAdManager.loadStoryAd()
                }
                
                debugTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    if self.storyAdManager.isLoading {
                        self.cleanupAndNext()
                    }
                }
            }
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func cleanupAndNext() {
        cleanup()
        onNext()
    }
    
    private func cleanup() {
        adTimer?.invalidate()
        adTimer = nil
        debugTimer?.invalidate()
        debugTimer = nil
        storyAdManager.cleanup()
    }
    
    private func startAdTimer() {
        guard adTimer == nil else { return }
        
        progress = 0.0
        adTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            progress += 0.05 / adDuration
            if progress >= 1.0 {
                cleanupAndNext()
            }
        }
    }
}

// MARK: - Story Ad Content View with MediaView
struct StoryAdContentViewWithMediaView: View {
    let nativeAd: NativeAd
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let screenSize: CGSize
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var mediaViewKey = UUID()
    
    var body: some View {
        ZStack {
            StoryAdMediaViewRepresentable(nativeAd: nativeAd)
                .id(mediaViewKey)
                .frame(width: screenSize.width, height: screenSize.height)
                .clipped()
            
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 30)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<storyCount, id: \.self) { index in
                            GlassmorphicProgressBar(
                                progress: getProgressForSegment(index: index),
                                isActive: index == storyIndex
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                    .storyGlassmorphic()
                                
                                Image(systemName: "megaphone.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Patrocinado")
                                    .foregroundColor(.white)
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                
                                Text("Anuncio")
                                    .foregroundColor(.white.opacity(0.8))
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 40, height: 40)
                                .storyGlassmorphic()
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Los elementos del anuncio ahora se muestran solo desde UIKit (StoryAdMediaViewRepresentable)
                // para cumplir con las reglas de Google AdMob sin duplicación
            }
            
            storyTouchAreas
        }
    }
    
    private var storyTouchAreas: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onPrevious() }
                
                Spacer()
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }
            }
            .frame(height: geometry.size.height * 0.85)
        }
    }
    
    private func getProgressForSegment(index: Int) -> Double {
        if index < storyIndex { return 1.0 }
        else if index == storyIndex { return progress }
        else { return 0.0 }
    }
}

// MARK: - MediaView UIViewRepresentable
struct StoryAdMediaViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = .black
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
        
        // AdChoices (REQUERIDO por Google)
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
        
        // Icon
        let iconView = UIImageView()
        if let iconImage = nativeAd.icon?.image {
            iconView.image = iconImage
        }
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.iconView = iconView
        
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
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                videoController.isMuted = false
            }
        }
        
        // Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        // nativeAdView.addSubview(callToActionButton) // ✅ QUITADO: CTA Button
        nativeAdView.addSubview(iconView)
        nativeAdView.addSubview(advertiserLabel)
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.addSubview(adAttributionView)
        
        // Constraints - Layout vertical DENTRO del NativeAdView (como FeedNativeAd)
        NSLayoutConstraint.activate([
            // MediaView - parte superior (más grande para parecer historia)
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            mediaView.heightAnchor.constraint(equalToConstant: 500), // Más alto para parecer historia
            
            // Ad Attribution - debajo del media (sin superposición)
            adAttributionView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adAttributionView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            adAttributionView.widthAnchor.constraint(equalToConstant: 25),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            // Ad Attribution Label constraints
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices - debajo del media (sin superposición)
            adChoicesView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            
            // ✅ HÍBRIDO: Texto en horizontal, video en vertical - SIN SUPERPOSICIONES
            // Headline - debajo de los elementos de atribución
            headlineLabel.topAnchor.constraint(equalTo: adAttributionView.bottomAnchor, constant: 12),
            headlineLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            headlineLabel.heightAnchor.constraint(equalToConstant: 30),
            
            // Body - debajo del headline, horizontal
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8),
            bodyLabel.heightAnchor.constraint(equalToConstant: 25),
            
            // Icon - debajo del body, horizontal (no superpuesto)
            iconView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 8),
            iconView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            
            // Advertiser - debajo del icono
            advertiserLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
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
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // Actualizar si es necesario
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {}
        func videoControllerDidPauseVideo(_ videoController: VideoController) {}
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {}
        func videoControllerDidMuteVideo(_ videoController: VideoController) {}
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {}
        func videoController(_ videoController: VideoController, didFailWithError error: Error) {}
    }
}

// MARK: - Story Ad Loading View
struct StoryAdLoadingView: View {
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 30)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<storyCount, id: \.self) { index in
                            GlassmorphicProgressBar(
                                progress: getProgressForSegment(index: index),
                                isActive: index == storyIndex
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 38, height: 38)
                                    .storyGlassmorphic()
                                
                                Image(systemName: "megaphone.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Patrocinado")
                                    .foregroundColor(.white)
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                
                                Text("Cargando...")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.custom("Poppins-Regular", size: 11))
                            }
                        }
                        
                        Spacer()
                        
                        Button("Saltar") {
                            onNext()
                        }
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                        
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 40, height: 40)
                                .storyGlassmorphic()
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Preparando anuncio...")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 5)
                        
                        Text("Esto solo tomará unos segundos")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    }
                    
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 180)
                            .shimmer(isAnimating: isAnimating)
                        
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 20)
                                .shimmer(isAnimating: isAnimating)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 16)
                                .frame(width: 200)
                                .shimmer(isAnimating: isAnimating)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            
            storyTouchAreas
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var storyTouchAreas: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onPrevious() }
                
                Spacer()
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }
            }
            .frame(height: geometry.size.height * 0.85)
        }
    }
    
    private func getProgressForSegment(index: Int) -> Double {
        if index < storyIndex { return 1.0 }
        else if index == storyIndex { return progress }
        else { return 0.0 }
    }
}

// MARK: - Shimmer Effect Extension
extension View {
    func shimmer(isAnimating: Bool) -> some View {
        self.modifier(ShimmerModifier(isAnimating: isAnimating))
    }
}

struct ShimmerModifier: ViewModifier {
    let isAnimating: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(45))
                    .offset(x: phase)
                    .clipped()
            )
            .onAppear {
                if isAnimating {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
            }
    }
}

// MARK: - Helpers para verificar estado Plus
struct PlusStatusHelper {
    static func shouldShowAds(for user: AppUser?) -> Bool {
        guard let user = user else { return true }
        return !(user.isPlusSubscriber && user.hasActivePlusSubscription)
    }

    static func isActivePlus(for user: AppUser?) -> Bool {
        guard let user = user else { return false }
        return user.isPlusSubscriber && user.hasActivePlusSubscription
    }
}

// MARK: - Story Native Ad Manager
@MainActor
class StoryNativeAdManager: NSObject, ObservableObject {
    @Published var nativeAd: NativeAd?
    @Published var isLoading = false
    @Published var hasError = false

    private var adLoader: AdLoader?

    func loadStoryAd() {
        guard !isLoading else { return }
        
        if let preloadedAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
            DispatchQueue.main.async {
                self.nativeAd = preloadedAd
                self.isLoading = false
                self.hasError = false
            }
            AdMobConfiguration.shared.clearPreloadedNativeAd()
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.hasError = false
            self.nativeAd = nil
        }

        let adUnitID = AdMobConfiguration.getNativeAdUnitId()
        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .any

        let rootVC = UIApplication.shared.topViewController()
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [mediaOptions]
        )

        adLoader?.delegate = self
        let request = AdMobConfiguration.shared.createAdRequest()
        adLoader?.load(request)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if self.isLoading {
                self.isLoading = false
                self.hasError = true
            }
        }
    }
    
    func cleanup() {
        adLoader?.delegate = nil
        adLoader = nil
        
        if nativeAd != nil {
            nativeAd = nil
        }
        
        isLoading = false
        hasError = false
    }
    
    var hasReadyAd: Bool {
        return nativeAd != nil && !isLoading && !hasError
    }
    
    func forceReload() {
        DispatchQueue.main.async {
            self.cleanup()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadStoryAd()
        }
    }
}

// MARK: - AdLoaderDelegate
extension StoryNativeAdManager: AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.hasError = true
            self.nativeAd = nil
        }
    }
}

// MARK: - NativeAdLoaderDelegate
extension StoryNativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        DispatchQueue.main.async {
            if nativeAd.mediaContent.hasVideoContent {
                nativeAd.mediaContent.videoController.isMuted = false
            }
            
            self.nativeAd = nativeAd
            self.isLoading = false
            self.hasError = false
        }
    }
}

// MARK: - ✅ NUEVO: Anuncio integrado para historias
struct IntegratedStoryAdView: View {
    let nativeAd: NativeAd
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let screenSize: CGSize
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var adTimer: Timer?
    @State private var timeRemaining: Double = 10.0
    
    // Duración dinámica basada en el tipo de contenido (consistente con historias normales)
    private var adDuration: Double {
        if nativeAd.mediaContent.hasVideoContent {
            return 30.0 // 30 segundos para videos (más razonable para anuncios)
        } else {
            return 10.0 // 10 segundos para fotos (como las historias normales)
        }
    }
    
    var body: some View {
        ZStack {
            // Fondo negro como las historias
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Media del anuncio (Pantalla completa e inmersiva)
                ZStack(alignment: .bottom) {
                    IntegratedStoryMediaView(nativeAd: nativeAd)
                        .frame(width: screenSize.width, height: screenSize.height)
                    
                    // ✅ Gradiente protector cinemático
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 250)
                    .allowsHitTesting(false)
                    
                    // ✅ Contenido del anuncio arriba del gradiente
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nativeAd.headline ?? "")
                                .font(.custom("Poppins-Bold", size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                            
                            if let body = nativeAd.body {
                                Text(body)
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(3)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        
                        // ✅ Botón de acción Premium
                        Button(action: {
                            // La interacción se maneja nativamente por AdMob
                        }) {
                            HStack {
                                Text(nativeAd.callToAction ?? "Más información")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }
                        .padding(.bottom, 60)
                    }
                }
            }
            .ignoresSafeArea()
            
            // ✅ Capa de Controles superior (Sobre el media)
            VStack(spacing: 0) {
                // Progress Bar estilo Story
                HStack(spacing: 4) {
                    ForEach(0..<storyCount, id: \.self) { index in
                        Capsule()
                            .fill(index == storyIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(height: 3)
                            .overlay(
                                index == storyIndex ?
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * (1 - timeRemaining / adDuration))
                                } : nil
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)
                
                // Header Nativo
                HStack(spacing: 12) {
                    // Icono del anunciante
                    if let icon = nativeAd.icon {
                        AsyncImage(url: URL(string: icon.imageURL?.absoluteString ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(.ultraThinMaterial)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nativeAd.advertiser ?? "Anunciante")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)
                        
                        Text("Patrocinado")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Botón cerrar
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Spacer()
            }
        }
        .onAppear {
            timeRemaining = adDuration
            startAdTimer()
        }
        .onDisappear {
            stopAdTimer()
        }
    }
    
    private func startAdTimer() {
        timeRemaining = adDuration
        
        adTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopAdTimer()
                onNext()
            }
        }
    }
    
    private func stopAdTimer() {
        adTimer?.invalidate()
        adTimer = nil
    }
}

// MARK: - ✅ NUEVO: MediaView integrado para historias
struct IntegratedStoryMediaView: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView - Totalmente inmersivo, sin bordes
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = .black
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
        
        // AdChoices (REQUERIDO por Google)
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
        
        // Icon
        let iconView = UIImageView()
        if let iconImage = nativeAd.icon?.image {
            iconView.image = iconImage
        }
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.iconView = iconView
        
        // Advertiser
        let advertiserLabel = UILabel()
        advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        advertiserLabel.font = UIFont(name: "Poppins-SemiBold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.advertiserView = advertiserLabel
        
        // Configurar video si existe
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
            videoController.play()
        }
        
        // Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        // nativeAdView.addSubview(callToActionButton) // ✅ QUITADO: CTA Button
        nativeAdView.addSubview(iconView)
        nativeAdView.addSubview(advertiserLabel)
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.addSubview(adAttributionView)
        
        // Constraints - Layout vertical DENTRO del NativeAdView (como FeedNativeAd)
        NSLayoutConstraint.activate([
            // MediaView - Pantalla completa real
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor),
            
            // Ad Attribution - Posicionado discretamente arriba
            adAttributionView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 110),
            adAttributionView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 16),
            adAttributionView.widthAnchor.constraint(equalToConstant: 25),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            // Ad Attribution Label constraints
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices - Arriba a la derecha
            adChoicesView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 110),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
            
            // Registramos los labels pero los mantenemos fuera de la vista 
            // ya que SwiftUI renderiza el texto cinemático
            headlineLabel.heightAnchor.constraint(equalToConstant: 0),
            bodyLabel.heightAnchor.constraint(equalToConstant: 0),
            iconView.heightAnchor.constraint(equalToConstant: 0),
            advertiserLabel.heightAnchor.constraint(equalToConstant: 0)
            
            // ✅ QUITADO: CTA Button constraints - No necesario, el tapping general funciona
            // callToActionButton.topAnchor.constraint(equalTo: advertiserLabel.bottomAnchor, constant: 16),
            // callToActionButton.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            // callToActionButton.heightAnchor.constraint(equalToConstant: 44),
            // callToActionButton.widthAnchor.constraint(equalToConstant: 150),
            // callToActionButton.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // Actualizar si es necesario
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidPauseVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {
        }
        
        func videoControllerDidMuteVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {
        }
    }
}
