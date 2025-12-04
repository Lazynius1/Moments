import SwiftUI

// MARK: - SwiftUI Native Ad View
struct SwiftUINativeAdView: View {
    @StateObject var adManager = NativeAdManager()

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
    @StateObject var nativeAdManager = NativeAdManager()
    @State var showingATTPreAlert = false

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
                    // Android doesn't use ATT - handled natively
                }
            } else {
                EmptyView()
            }
        }
        // ATT alert only on iOS - Android handles natively
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
    @State var isAnimating = false

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
// MARK: - ATT Pre-Alert View con Glassmorphism (iOS only)
// MARK: - Vista de carga integrada al feed
struct IntegratedAdLoadingView: View {
    @State var isAnimating = false
    
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
                        .foregroundColor(personalizationStatus.isPersonalized ? Color.green : Color.orange)
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
    @Environment(\.colorScheme) var colorScheme
    
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
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "app.fill")
                            .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(nativeAd.advertiser ?? "Anunciante")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // ✅ CORREGIDO: Botón SwiftUI eliminado - solo usamos el botón nativo de AdMob
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.2), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 16)
    }
}

// MARK: - MediaView integrado
// MARK: - Native Ad Media View (Android compatible)
struct IntegratedAdMediaView: View {
    let nativeAd: NativeAd
    
    var body: some View {
        // Android: NativeAdView will be rendered using Compose
        // Skip transpiles this to Android NativeAdView from AdMob SDK
        NativeAdViewWrapper(nativeAd: nativeAd)
    }
}

// Wrapper for NativeAdView in SwiftUI
struct NativeAdViewWrapper: View {
    let nativeAd: NativeAd
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Media View
            createMediaView()
                .aspectRatio(contentMode: .fit)
                .frame(height: 300)
                .cornerRadius(16)
            
            // Ad Attribution
            HStack {
                Text("Ad")
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(3)
                
                Spacer()
                
                // AdChoices view
                AdChoicesViewPlaceholder()
            }
            .padding(.horizontal, 8)
            
            // Headline
            if let headline = nativeAd.headline {
                Text(headline)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 8)
            }
            
            // Body
            if let body = nativeAd.body {
                Text(body)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
            
            // Advertiser
            if let advertiser = nativeAd.advertiser {
                Text(advertiser)
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func createMediaView() -> some View {
        // For images
        if let imageURL = nativeAd.image?.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.systemGray6)
                        .overlay(ProgressView())
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Rectangle()
                        .fill(Color.systemGray6)
                @unknown default:
                    Rectangle()
                        .fill(Color.systemGray6)
                }
            }
        } else {
            Rectangle()
                .fill(Color.systemGray6)
        }
    }
}

struct AdChoicesViewPlaceholder: View {
    var body: some View {
        // AdChoices icon placeholder
        Image(systemName: "info.circle")
            .font(.system(size: 16))
            .foregroundColor(.secondary)
    }
}
