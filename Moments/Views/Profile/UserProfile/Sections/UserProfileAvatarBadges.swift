import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

//SISTEMA DE BADGES //
struct UserModernAvatarWithBadges: View {
    let userProfile: AppUser?
    let onOpenStories: () -> Void
    let storyRingRefreshTrigger: Int
    @Binding var showProfileImageFullscreen: Bool
    let size: CGFloat
    /// Long-press con historia → preview (gesto solo aquí; no toca StoryRingAvatarView).
    var onPreviewStory: ((CGRect) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    @State private var hasActiveStory = false
    @State private var isPressing = false
    @State private var anchorCapture = FeedStoryCircleAnchorCapture()

    var body: some View {
        ZStack {
            // Sin `onTap` → sin `Button` interno; el press classifier (como el feed) maneja tap + long-press.
            StoryRingAvatarView(
                userId: userProfile?.id ?? "",
                size: size,
                lineWidth: 3,
                refreshTrigger: storyRingRefreshTrigger,
                isOwnStory: false
            )

            // ✅ NUEVO: Badge principal en esquina superior derecha
            if let primaryBadge = userProfile?.primaryBadge {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: primaryBadge.swiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.3, height: size * 0.3)

                    Text(primaryBadge.emoji)
                        .font(.system(size: size * 0.15))
                }
                .offset(x: size * 0.375, y: -size * 0.375)
                .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                .allowsHitTesting(false)
            }

            // ✅ NUEVO: Corona Plus en esquina superior izquierda (se oculta si hay tema activo o si está desactivado)
            if userProfile?.isPlusSubscriber == true,
               userProfile?.showPlusBadge == true,
               userProfile?.selectedProfileTheme == nil || userProfile?.selectedProfileTheme == "default" {
                ZStack {
                    Circle()
                        .fill(UserProfileColors.cardBackground)
                        .frame(width: size * 0.27, height: size * 0.27)

                    Image(systemName: "crown.fill")
                        .font(.system(size: size * 0.13, weight: .bold))
                        .foregroundStyle(Color(hex: "FFD700"))
                }
                .offset(x: -size * 0.375, y: -size * 0.375)
                .shadow(color: UserProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Circle())
        .scaleEffect(isPressing ? 0.94 : 1)
        .opacity(isPressing ? 0.88 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .background {
            FeedStoryCircleAnchorProbe(capture: anchorCapture)
            FeedStoryRingScrollTouchFix()
        }
        .modifier(FeedStoryCirclePressModifier(
            isPressing: $isPressing,
            onTap: {
                if hasActiveStory {
                    onOpenStories()
                } else {
                    showProfileImageFullscreen = true
                }
            },
            onLongPress: {
                if hasActiveStory, let onPreviewStory {
                    let frame = anchorCapture.resolvedFrame
                    onPreviewStory(frame.width > 1 ? frame : .zero)
                } else {
                    showProfileImageFullscreen = true
                }
            }
        ))
        .onAppear { resolveHasStory() }
        .onChange(of: userProfile?.id) { _, _ in resolveHasStory() }
        .onChange(of: storyRingRefreshTrigger) { _, _ in resolveHasStory(forceRefresh: true) }
    }

    private func resolveHasStory(forceRefresh: Bool = false) {
        guard let userId = userProfile?.id, !userId.isEmpty,
              let viewerId = Auth.auth().currentUser?.uid, !viewerId.isEmpty else {
            hasActiveStory = false
            return
        }

        StoryRingResolverService.shared.resolve(
            viewerId: viewerId,
            authorId: userId,
            privacyService: PrivacyService(),
            useCache: !forceRefresh
        ) { snapshot in
            DispatchQueue.main.async {
                hasActiveStory = snapshot.hasStory
            }
        }
    }
}

// ✅ NUEVO: Vista de badges para el usuario visitado
struct UserProfileBadgesView: View {
    let userProfile: AppUser
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if userProfile.isPlusSubscriber || userProfile.isSupporter {
            HStack(spacing: 8) {
                // Plus Badge (se oculta si hay tema activo o si está desactivado)
                if userProfile.isPlusSubscriber,
                   userProfile.showPlusBadge,
                   userProfile.selectedProfileTheme == nil || userProfile.selectedProfileTheme == "default" {
                    UserPlusBadgeInline()
                }

                // Support Badge
                if let primaryBadge = userProfile.primaryBadge {
                    UserSupportBadgeInline(badge: primaryBadge)
                }
            }
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: userProfile.isPlusSubscriber), value: userProfile.isPlusSubscriber)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: userProfile.primaryBadge?.id), value: userProfile.primaryBadge?.id)
        }
    }
}

// ✅ NUEVO: Plus Badge Inline para UserProfile
struct UserPlusBadgeInline: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)

            Text("userProfile.plus")
                .font(.system(size: legacyPoppinsSize(9), weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Support Badge Inline para UserProfile
struct UserSupportBadgeInline: View {
    let badge: UserBadge

    var body: some View {
        HStack(spacing: 4) {
            Text(badge.emoji)
                .font(.system(size: 10))

            Text(badge.name.uppercased())
                .font(.system(size: legacyPoppinsSize(8), weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: badge.swiftUIColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Indicador de nivel supporter para UserProfile
struct UserSupporterLevelIndicator: View {
    let level: SupporterLevel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            Text(level.emoji)
                .font(.system(size: 10))

            ForEach(0..<levelStars, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(hex: "FFD700"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(UserProfileColors.cardBackground)
        .clipShape(Capsule())
    }

    private var levelStars: Int {
        switch level {
        case .none: return 0
        case .supporter: return 1
        case .earlyAdopter: return 2
        case .champion: return 3
        case .vip: return 4
        }
    }
}

// MARK: - ✅ NUEVO: Indicador de refresh moderno
struct UserModernRefreshIndicator: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(UserProfileColors.materialBackground)
                    .frame(width: 32, height: 32)
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [UserProfileColors.accent, UserProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .scaleEffect(pulseScale)
            }

            Text("userProfile.updating")
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(UserProfileColors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(UserProfileColors.materialBackground)
        .clipShape(Capsule())
        .shadow(color: UserProfileColors.shadowColor, radius: 8, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}
