import SwiftUI
import FirebaseAuth
import UIKit

private struct FeedStoryRingAvatar<Avatar: View>: View {
    let avatarSize: CGFloat
    let lineWidth: CGFloat
    @ViewBuilder let avatar: () -> Avatar
    let ring: StorySegmentedRing

    private var outerSize: CGFloat {
        StoryRingLayout.outerFrameSize(avatarSize: avatarSize, lineWidth: lineWidth)
    }

    var body: some View {
        ZStack {
            ring
                .mask(StoryRingLayout.ringGapMask(avatarSize: avatarSize))

            avatar()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
        }
        .frame(width: outerSize, height: outerSize)
    }
}

struct RealStoryCircle: View {
    let userId: String
    let fallbackUsername: String
    let hasStory: Bool
    let hasUnseenStory: Bool
    let storyCount: Int
    let storyViewedStatus: [Bool]
    let storyAudiences: [String?]
    let isOwnStory: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private let avatarSize = StoryRingLayout.feedHeaderAvatarSize
    private let lineWidth = StoryRingLayout.feedHeaderLineWidth

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                FeedStoryRingAvatar(
                    avatarSize: avatarSize,
                    lineWidth: lineWidth,
                    avatar: { AsyncProfileImageView(userId: userId) },
                    ring: StorySegmentedRing(
                        storyCount: storyCount,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseenStory,
                        storyViewedStatus: storyViewedStatus,
                        storyAudiences: storyAudiences,
                        isOwnStory: isOwnStory,
                        colorScheme: colorScheme,
                        ringSize: StoryRingLayout.ringStrokeDiameter(
                            avatarSize: avatarSize,
                            lineWidth: lineWidth
                        ),
                        lineWidth: lineWidth,
                        hapticsEnabled: true
                    )
                )
            }
            .buttonStyle(.momentsPress(scale: 0.94, haptic: .none))

            LiveUsernameContent(userId: userId, fallbackUsername: fallbackUsername) { username in
                Text(username)
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .frame(width: 64)
            }
        }
        .frame(width: 64)
    }
}

// ✅ NOTA: StorySegmentedRing y StorySegment ahora están en un archivo compartido
// Moments/Views/story/StorySegmentedRing.swift

/// ///
//Progeso subida Stories
///
struct YourStoryCircleWithProgress: View {
    let hasStory: Bool
    let storyCount: Int
    let storyAudiences: [String?]
    let colorScheme: ColorScheme
    @ObservedObject var storyUploadService: BackgroundStoryUploadService
    let action: () -> Void

    private let avatarSize = StoryRingLayout.feedHeaderAvatarSize
    private let lineWidth = StoryRingLayout.feedHeaderLineWidth

    var body: some View {
        VStack(spacing: 3) {
            Button(action: {
                // Si hay upload en progreso y falló, reintentar
                if let uploadingStory = storyUploadService.uploadingStory,
                   uploadingStory.status == .failed {
                    storyUploadService.retryUpload(uploadingStory)
                } else {
                    // ✅ SIMPLE: Siempre ejecutar la acción que se pasa
                    action()
                }
            }) {
                ZStack {
                    FeedStoryRingAvatar(
                        avatarSize: avatarSize,
                        lineWidth: lineWidth,
                        avatar: {
                            AsyncProfileImageView(userId: Auth.auth().currentUser?.uid ?? "")
                        },
                        ring: StorySegmentedRing(
                            storyCount: storyCount,
                            hasStory: hasStory,
                            hasUnseenStory: false,
                            storyViewedStatus: Array(repeating: true, count: storyCount),
                            storyAudiences: storyAudiences,
                            isOwnStory: true,
                            colorScheme: colorScheme,
                            ringSize: StoryRingLayout.ringStrokeDiameter(
                                avatarSize: avatarSize,
                                lineWidth: lineWidth
                            ),
                            lineWidth: lineWidth,
                            hapticsEnabled: true
                        )
                    )

                    if let uploadingStory = storyUploadService.uploadingStory {
                        StoryUploadCircleOverlay(
                            uploadingStory: uploadingStory,
                            colorScheme: colorScheme
                        )
                    }
                }
            }
            .buttonStyle(.momentsPress(scale: 0.94, haptic: .none))

            if let uploadingStory = storyUploadService.uploadingStory {
                StoryUploadStatusLabel(uploadingStory: uploadingStory)
            } else {
                Text(NSLocalizedString("stories.yourStory", comment: "Your story label"))
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 64)
            }
        }
        .frame(width: 64)
        .scaleEffect(storyUploadService.uploadingStory?.status == .failed ? 0.95 : 1.0)
        .animation(
            MotionPolicy.animation(MotionPolicy.Spring.row, value: storyUploadService.uploadingStory?.status),
            value: storyUploadService.uploadingStory?.status
        )
    }
}

struct StoryUploadStatusLabel: View {
    @ObservedObject var uploadingStory: UploadingStory

    var body: some View {
        Text(labelText)
            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
            .foregroundColor(Color.primary.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 64)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: uploadingStory.status)
    }

    private var labelText: String {
        switch status {
        case .initializing:
            return NSLocalizedString("feed.uploading.initializing", value: "Iniciando...", comment: "Initializing upload status")
        case .uploading, .processing:
            return NSLocalizedString("feed.uploading.uploading", comment: "Uploading files status")
        case .completed, .moderated:
            return NSLocalizedString("feed.uploading.published", comment: "Moment published status")
        case .failed:
            return NSLocalizedString("feed.uploading.retry", comment: "Retry upload")
        }
    }

    private var status: UploadStatus {
        uploadingStory.status
    }
}

struct StoryUploadCircleOverlay: View {
    @ObservedObject var uploadingStory: UploadingStory
    let colorScheme: ColorScheme

    private let avatarSize = StoryRingLayout.feedHeaderAvatarSize
    private let lineWidth = StoryRingLayout.feedHeaderLineWidth
    private var progressRingSize: CGFloat {
        StoryRingLayout.ringStrokeDiameter(avatarSize: avatarSize, lineWidth: lineWidth)
    }

    @State private var renderedProgress: Double = 0
    @State private var arrowOffset: CGFloat = 0
    @State private var arrowOpacity: Double = 1
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkRotation: Double = -15
    @State private var checkmarkOpacity: Double = 0
    @State private var completionPulse = false
    @State private var completionAnimationScheduled = false
    @State private var rippleScale: CGFloat = 0.2
    @State private var rippleOpacity: Double = 0
    @State private var auraOffset: CGFloat = 0
    @State private var auraOpacity: Double = 0
    @State private var auraScale: CGFloat = 1
    @State private var auraBlur: CGFloat = 0
    @State private var isPulsing = false // 🔄 Estado para el anillo pulsante

    var body: some View {
        ZStack {
            if uploadingStory.status == .initializing {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "6A11CB"), Color(hex: "007AFF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: progressRingSize, height: progressRingSize)
                    .scaleEffect(isPulsing ? 1.08 : 0.94)
                    .opacity(isPulsing ? 0.9 : 0.4)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
            } else {
                Circle()
                    .stroke(trackColor, lineWidth: 3)
                    .frame(width: progressRingSize, height: progressRingSize)

                Circle()
                    .trim(from: 0, to: max(0.04, min(renderedProgress, 1.0)))
                    .stroke(
                        progressGradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: progressRingSize, height: progressRingSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.22), value: renderedProgress)
            }

            Circle()
                .fill((colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).opacity(0.42))
                .frame(width: avatarSize, height: avatarSize)

            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: progressRingSize, height: progressRingSize)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)

            statusGlyph
        }
        .scaleEffect(completionPulse ? 1.06 : 1.0)
        .contentShape(Circle())
        .onAppear {
            syncRenderedProgress(animated: false)
            updateArrowAnimation(for: uploadingStory.status)
            if uploadingStory.status == .completed || uploadingStory.status == .moderated {
                handleCompletion()
            }
        }
        .onChange(of: uploadingStory.uploadProgress) { _, _ in
            syncRenderedProgress()
        }
        .onChange(of: uploadingStory.status) { _, newStatus in
            updateArrowAnimation(for: newStatus)
            if newStatus == .completed || newStatus == .moderated {
                handleCompletion()
            } else {
                resetCompletionState()
            }
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch uploadingStory.status {
        case .initializing:
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        case .completed, .moderated:
            if checkmarkOpacity > 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(checkmarkScale)
                    .rotationEffect(.degrees(checkmarkRotation))
                    .opacity(checkmarkOpacity)
            } else {
                uploadArrow
            }
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        case .uploading, .processing:
            ZStack {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: auraOffset)
                    .scaleEffect(auraScale)
                    .opacity(auraOpacity)
                    .blur(radius: auraBlur)

                uploadArrow
            }
        }
    }

    private var uploadArrow: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .offset(y: arrowOffset)
            .opacity(arrowOpacity)
    }

    private func syncRenderedProgress(animated: Bool = true) {
        let targetProgress = min(max(uploadingStory.uploadProgress, 0), 1)
        guard animated else {
            renderedProgress = targetProgress
            return
        }

        let delta = abs(targetProgress - renderedProgress)
        let duration = min(0.5, max(0.14, delta * 1.05))
        withAnimation(.linear(duration: duration)) {
            renderedProgress = targetProgress
        }
    }

    private func updateArrowAnimation(for status: UploadStatus) {
        switch status {
        case .initializing:
            arrowOffset = 0
            arrowOpacity = 0.6
            auraOffset = 0
            auraOpacity = 0
            auraScale = 1
            auraBlur = 0
        case .uploading, .processing:
            arrowOpacity = 1
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                arrowOffset = -3
            }

            auraOffset = 10
            auraOpacity = 0.6
            auraScale = 0.8
            auraBlur = 1.0
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                auraOffset = -18
                auraOpacity = 0
                auraScale = 1.3
                auraBlur = 3.0
            }
        case .completed, .moderated:
            break
        case .failed:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                arrowOffset = 0
                arrowOpacity = 1
                auraOffset = 0
                auraOpacity = 0
                auraScale = 1
                auraBlur = 0
            }
        }
    }

    private func handleCompletion() {
        guard !completionAnimationScheduled else { return }
        completionAnimationScheduled = true
        HapticManager.shared.notification(.success)

        withAnimation(.linear(duration: 0.45)) {
            renderedProgress = 1.0
        }

        arrowOffset = 0
        arrowOpacity = 1
        withAnimation(.easeIn(duration: 0.28)) {
            arrowOffset = -26
            arrowOpacity = 0
        }

        rippleScale = 0.2
        rippleOpacity = 0.8
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1.6
            rippleOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            checkmarkScale = 0
            checkmarkRotation = -15
            checkmarkOpacity = 0
            withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) {
                checkmarkScale = 1
                checkmarkRotation = 0
                checkmarkOpacity = 1
                completionPulse = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                    completionPulse = false
                }
            }
        }
    }

    private func resetCompletionState() {
        completionAnimationScheduled = false
        checkmarkScale = 0
        checkmarkRotation = -15
        checkmarkOpacity = 0
        completionPulse = false
        rippleScale = 0.2
        rippleOpacity = 0
    }

    private var progressGradient: LinearGradient {
        switch uploadingStory.status {
        case .failed:
            return LinearGradient(
                colors: [Color(hex: "FF453A"), Color(hex: "FF8A3D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            let progress = max(0, min(renderedProgress, 1))
            let startColor = interpolateColor(
                from: Color(hex: "6A11CB"),
                to: Color(hex: "34C759"),
                fraction: progress
            )
            let endColor = interpolateColor(
                from: Color(hex: "007AFF"),
                to: Color(hex: "1EA84C"),
                fraction: progress
            )
            return LinearGradient(
                colors: [startColor, endColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func interpolateColor(from color1: Color, to color2: Color, fraction: Double) -> Color {
        let f = CGFloat(max(0.0, min(1.0, fraction)))

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        let uiColor1 = UIColor(color1)
        let uiColor2 = UIColor(color2)
        let success1 = uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let success2 = uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        guard success1 && success2 else { return color2 }

        let r = r1 + (r2 - r1) * f
        let g = g1 + (g2 - g1) * f
        let b = b1 + (b2 - b1) * f
        let a = a1 + (a2 - a1) * f

        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
}
