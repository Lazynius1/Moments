import SwiftUI
import Combine

struct FloatingMomentUploadOverlay: View {
    @EnvironmentObject private var uploadService: BackgroundMomentUploadService
    @Environment(\.colorScheme) private var colorScheme

    let topInset: CGFloat

    @State private var isVisible = false
    @State private var activeMoment: UploadingMoment? = nil
    @State private var isExpanded = false
    @State private var arrowBobOffset: CGFloat = 0
    @State private var completionPulse = false
    @State private var renderedProgress: Double = 0
    @State private var showsCompletionIcon = false
    @State private var completionAnimationScheduled = false
    @State private var refreshToken = false

    // Rocket Launch and Checkmark Bloom States
    @State private var arrowOffset: CGFloat = 0
    @State private var arrowOpacity: Double = 1.0
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkRotation: Double = -15
    @State private var checkmarkOpacity: Double = 0.0
    @State private var rippleScale: CGFloat = 0.2
    @State private var rippleOpacity: Double = 0.0

    // Ascending Aura States
    @State private var auraOffset: CGFloat = 0
    @State private var auraOpacity: Double = 0.0
    @State private var auraScale: CGFloat = 1.0
    @State private var auraBlur: CGFloat = 0

    private var extraUploadsCount: Int {
        max(0, uploadService.uploadingMoments.count - 1)
    }

    private var activeMomentChanges: AnyPublisher<Void, Never> {
        activeMoment?.objectWillChange.eraseToAnyPublisher() ?? Empty<Void, Never>().eraseToAnyPublisher()
    }

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 0)

                if isVisible, let moment = activeMoment {
                    uploadCluster(for: moment)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.top, topInset)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .allowsHitTesting(isVisible)
        .onReceive(activeMomentChanges) { _ in
            DispatchQueue.main.async {
                refreshToken.toggle()
                if let moment = activeMoment {
                    syncRenderedProgress(for: moment)
                }
            }
        }
        .onAppear {
            if let first = uploadService.uploadingMoments.first {
                activeMoment = first
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isVisible = true
                }
            }
        }
        .onChange(of: uploadService.uploadingMoments.count) { _, count in
            if let first = uploadService.uploadingMoments.first {
                activeMoment = first
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isVisible = true
                }
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if uploadService.uploadingMoments.isEmpty {
                        activeMoment = nil
                    }
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: uploadService.uploadingMoments.count)
    }

    private func uploadCluster(for moment: UploadingMoment) -> some View {
        HStack(spacing: 10) {
            if isExpanded {
                expandedPanel(for: moment)
                    .transition(.liquidGlassStretch)
            }

            compactOrb(for: moment)
        }
        .onAppear {
            syncRenderedProgress(for: moment, animated: false)
        }
    }

    private func compactOrb(for moment: UploadingMoment) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 58, height: 58)
                    .momentsChromeGlass(in: Circle(), interactive: true)

                Circle()
                    .stroke(trackColor, lineWidth: 4)
                    .frame(width: 58, height: 58)

                Circle()
                    .trim(from: 0, to: max(0.04, min(renderedProgress, 1.0)))
                    .stroke(
                        progressGradient(for: moment.status),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.22), value: renderedProgress)

                // Liquid Ripple Splash Effect
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 58, height: 58)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)

                orbIcon(for: moment)
            }

            if extraUploadsCount > 0 {
                Text("+\(extraUploadsCount)")
                    .font(.system(size: legacyPoppinsSize(10), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .offset(x: 5, y: -3)
            }
        }
        .contentShape(Circle())
        .scaleEffect(completionPulse ? 1.06 : 1.0)
        .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
        .onTapGesture {
            guard moment.status != .completed && moment.status != .moderated else { return }
            HapticManager.shared.lightImpact()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        }
        .onAppear {
            updateArrowAnimation(for: moment.status)
        }
        .onChange(of: moment.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
    }

    private func expandedPanel(for moment: UploadingMoment) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.clear)
                .frame(width: 238, height: 72)
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)

            HStack(spacing: 12) {
                thumbnailView(for: moment)

                VStack(alignment: .leading, spacing: 4) {
                    Text(moment.content.isEmpty ? NSLocalizedString("feed.uploading.newMoment", comment: "New moment text") : moment.content)
                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(detailText(for: moment))
                        .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)

                    progressCapsule(for: moment)
                }

                if moment.status == .failed {
                    failedActions(for: moment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 238, height: 72)
        }
        .frame(width: 238, height: 72, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.75)
        )
        .shadow(color: shadowColor.opacity(0.8), radius: 16, x: 0, y: 8)
        .onTapGesture {
            guard moment.status != .completed && moment.status != .moderated else { return }
            HapticManager.shared.selection()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        }
    }

    private func thumbnailView(for moment: UploadingMoment) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail = moment.currentMediaThumbnailImage ?? moment.thumbnailImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(iconMutedColor)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            if moment.mediaCount > 1 {
                Text("\(moment.currentMediaIndex + 1)/\(moment.mediaCount)")
                    .font(.system(size: legacyPoppinsSize(9), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.58)))
                    .offset(x: 4, y: 4)
            }
        }
    }

    private func progressCapsule(for moment: UploadingMoment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                        .frame(height: 6)

                    Capsule()
                        .fill(progressGradient(for: moment.status))
                        .frame(width: max(18, geometry.size.width * min(renderedProgress, 1.0)), height: 6)
                        .animation(.linear(duration: 0.22), value: renderedProgress)
                }
            }
            .frame(height: 6)

            HStack(spacing: 6) {
                Text(statusLabel(for: moment.status))
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundStyle(secondaryTextColor)

                Spacer(minLength: 4)

                Text("\(Int(renderedProgress * 100))%")
                    .font(.system(size: legacyPoppinsSize(10), weight: .semibold))
                    .foregroundStyle(primaryTextColor)
            }
        }
    }

    private func failedActions(for moment: UploadingMoment) -> some View {
        VStack(spacing: 8) {
            Button {
                HapticManager.shared.mediumImpact()
                uploadService.retryUpload(moment)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.orange.opacity(0.75)))
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.lightImpact()
                uploadService.cancelUpload(moment)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func orbIcon(for moment: UploadingMoment) -> some View {
        switch moment.status {
        case .initializing:
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconMutedColor)
        case .completed, .moderated:
            ZStack {
                if showsCompletionIcon {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(iconColor)
                        .scaleEffect(checkmarkScale)
                        .rotationEffect(.degrees(checkmarkRotation))
                        .opacity(checkmarkOpacity)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(iconColor)
                        .offset(y: arrowOffset)
                        .opacity(arrowOpacity)
                }
            }
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconColor)
                .transition(.scale.combined(with: .opacity))
        case .processing, .uploading:
            ZStack {
                // Ascending aura arrow
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(iconColor)
                    .offset(y: auraOffset)
                    .scaleEffect(auraScale)
                    .opacity(auraOpacity)
                    .blur(radius: auraBlur)

                // Main breathing arrow
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(iconColor)
                    .offset(y: arrowBobOffset)
            }
        }
    }

    private func handleStatusChange(_ status: UploadStatus) {
        updateArrowAnimation(for: status)

        switch status {
        case .initializing:
            resetAnimationStates()
        case .completed, .moderated:
            guard !completionAnimationScheduled else { return }
            completionAnimationScheduled = true
            HapticManager.shared.notification(.success)

            withAnimation(.linear(duration: 0.65)) {
                renderedProgress = 1.0
            }

            // 1. Rocket launch arrow up
            arrowOffset = 0
            arrowOpacity = 1.0
            withAnimation(.easeIn(duration: 0.35)) {
                arrowOffset = -35
                arrowOpacity = 0.0
            }

            // 2. Liquid splash ripple
            rippleScale = 0.2
            rippleOpacity = 0.8
            withAnimation(.easeOut(duration: 0.55)) {
                rippleScale = 1.6
                rippleOpacity = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Switch view to checkmark
                showsCompletionIcon = true

                // 3. Bloom checkmark with bounce
                checkmarkScale = 0.0
                checkmarkRotation = -15
                checkmarkOpacity = 0.0
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0)) {
                    checkmarkScale = 1.0
                    checkmarkRotation = 0
                    checkmarkOpacity = 1.0
                    completionPulse = true
                    isExpanded = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                        completionPulse = false
                    }
                }
            }
        case .failed:
            HapticManager.shared.notification(.error)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isExpanded = true
            }
            resetAnimationStates()
        case .uploading, .processing:
            resetAnimationStates()
        }
    }

    private func resetAnimationStates() {
        arrowOffset = 0
        arrowOpacity = 1.0
        checkmarkScale = 0.0
        checkmarkRotation = -15
        checkmarkOpacity = 0.0
        rippleScale = 0.2
        rippleOpacity = 0.0
        showsCompletionIcon = false
        completionAnimationScheduled = false
    }

    private func syncRenderedProgress(for moment: UploadingMoment, animated: Bool = true) {
        let targetProgress = min(max(moment.uploadProgress, 0), 1)

        if moment.status == .completed || moment.status == .moderated {
            if !completionAnimationScheduled {
                handleStatusChange(moment.status)
            }
            return
        }

        resetAnimationStates()

        guard animated else {
            renderedProgress = targetProgress
            return
        }

        let delta = abs(targetProgress - renderedProgress)
        let duration = min(0.55, max(0.14, delta * 1.1))
        withAnimation(.linear(duration: duration)) {
            renderedProgress = targetProgress
        }
    }

    private func updateArrowAnimation(for status: UploadStatus) {
        if status == .uploading || status == .processing {
            // Main arrow bobs gently
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                arrowBobOffset = -3
            }

            // Ascending aura loop
            auraOffset = 10
            auraOpacity = 0.6
            auraScale = 0.8
            auraBlur = 1.0

            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                auraOffset = -18
                auraOpacity = 0.0
                auraScale = 1.3
                auraBlur = 3.0
            }
        } else {
            arrowBobOffset = 0
            withAnimation(.spring(response: 0.3)) {
                auraOffset = 0
                auraOpacity = 0.0
                auraScale = 1.0
                auraBlur = 0
            }
        }
    }

    private func detailText(for moment: UploadingMoment) -> String {
        let fileDetail = String(
            format: NSLocalizedString("feed.uploading.files", comment: "Files count"),
            moment.mediaCount
        )

        switch moment.status {
        case .initializing:
            return NSLocalizedString("feed.uploading.initializing", value: "Iniciando...", comment: "Initializing upload status")
        case .uploading:
            if moment.mediaCount > 1 {
                return "\(statusText(for: moment)) · \(moment.currentMediaIndex + 1)/\(moment.mediaCount) · \(fileDetail)"
            }
            return "\(statusText(for: moment)) · \(fileDetail)"
        case .processing:
            return NSLocalizedString("feed.uploading.creating", comment: "Creating moment status")
        case .completed, .moderated:
            return NSLocalizedString("feed.uploading.available", comment: "Moment available status")
        case .failed:
            return moment.errorMessage ?? NSLocalizedString("feed.uploading.error", comment: "Upload error status")
        }
    }

    private func statusLabel(for status: UploadStatus) -> String {
        switch status {
        case .initializing:
            return NSLocalizedString("feed.uploading.initializing", value: "Iniciando...", comment: "Initializing upload status")
        case .uploading:
            return NSLocalizedString("feed.uploading.uploading", comment: "Uploading files status")
        case .processing:
            return NSLocalizedString("feed.uploading.processing", comment: "Processing upload status")
        case .completed, .moderated:
            return NSLocalizedString("feed.uploading.published", comment: "Moment published status")
        case .failed:
            return NSLocalizedString("feed.uploading.retry", comment: "Retry upload")
        }
    }

    private func statusText(for moment: UploadingMoment) -> String {
        switch moment.status {
        case .initializing:
            return NSLocalizedString("feed.uploading.initializing", value: "Iniciando...", comment: "Initializing upload status")
        case .uploading:
            return NSLocalizedString("feed.uploading.uploading", comment: "Uploading files status")
        case .processing:
            return NSLocalizedString("feed.uploading.processing", comment: "Processing upload status")
        case .completed, .moderated:
            return NSLocalizedString("feed.uploading.published", comment: "Moment published status")
        case .failed:
            return NSLocalizedString("feed.uploading.error", comment: "Upload error status")
        }
    }

    private func progressGradient(for status: UploadStatus) -> LinearGradient {
        switch status {
        case .failed:
            return LinearGradient(
                colors: [Color.red, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            // Dynamic color shift based on actual renderedProgress
            let progress = max(0.0, min(1.0, renderedProgress))
            
            let startColor = Color.interpolate(
                from: Color(hex: "6A11CB"), // Premium Purple
                to: Color(hex: "34C759"),    // Apple Green
                fraction: progress
            )
            let endColor = Color.interpolate(
                from: Color(hex: "007AFF"),   // Electric Blue
                to: Color(hex: "1EA84C"),    // Emerald Green
                fraction: progress
            )
            
            return LinearGradient(
                colors: [startColor, endColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color.black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.62)
    }

    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var iconMutedColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.45)
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.35)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12)
    }
}

// MARK: - 🎨 COLOR INTERPOLATION HELPER
fileprivate extension Color {
    static func interpolate(from color1: Color, to color2: Color, fraction: Double) -> Color {
        let f = CGFloat(max(0.0, min(1.0, fraction)))
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        #if canImport(UIKit)
        let uiColor1 = UIColor(color1)
        let uiColor2 = UIColor(color2)
        let success1 = uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let success2 = uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        guard success1 && success2 else { return color2 }
        #else
        return color2
        #endif
        
        let r = r1 + (r2 - r1) * f
        let g = g1 + (g2 - g1) * f
        let b = b1 + (b2 - b1) * f
        let a = a1 + (a2 - a1) * f
        
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

// MARK: - 🧪 LIQUID GLASS TRANSITION
struct LiquidGlassTransitionModifier: AnimatableModifier {
    var progress: Double // 0.0 to 1.0
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    func body(content: Content) -> some View {
        let stretchX: CGFloat
        let squishY: CGFloat
        
        if progress <= 0.0 {
            stretchX = 0.0
            squishY = 0.0
        } else if progress >= 1.0 {
            // Support spring overshoot naturally
            stretchX = progress
            squishY = progress
        } else {
            // Bouncy horizontal stretching & vertical squishing envelope in transition
            let envelope = sin(progress * .pi)
            stretchX = progress + (0.15 * envelope)
            squishY = progress - (0.05 * envelope)
        }
        
        return content
            .scaleEffect(x: stretchX, y: squishY, anchor: .trailing)
            .opacity(max(0.0, min(1.0, progress * 1.5))) // Snappy fade-in
            .blur(radius: (1.0 - progress) * 8.0) // Glassy blur dissolve
    }
}

extension AnyTransition {
    static var liquidGlassStretch: AnyTransition {
        .modifier(
            active: LiquidGlassTransitionModifier(progress: 0.0),
            identity: LiquidGlassTransitionModifier(progress: 1.0)
        )
    }
}
