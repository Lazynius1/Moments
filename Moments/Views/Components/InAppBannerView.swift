import SwiftUI
import UIKit
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct InAppBannerView: View {
    @ObservedObject var service = InAppNotificationService.shared
    @ObservedObject private var incognitoModeService = IncognitoModeService.shared
    @ObservedObject private var navigationService = NotificationNavigationService.shared
    @Environment(\.colorScheme) var colorScheme
    @GestureState private var dragOffset = CGSize.zero
    @State private var isQuickReplyExpanded = false
    @State private var suppressTapUntil: Date = .distantPast
    @State private var contentPreviewImage: String?
    @State private var contentPreviewFeedCrop: MediaItemFeedCrop?
    /// Morph Liquid Glass (SDK): mismo ID + `GlassEffectContainer` + animación de jerarquía/geometría.
    @Namespace private var bannerGlassNS

    /// Una sola pastilla Incognito: mensaje ↔ timer ↔ icono (con notif).
    private enum IncognitoChromePhase: Equatable {
        case message
        case timer
        case timerIcon
    }

    private var isBannerInteractive: Bool {
        service.showBanner || incognitoModeService.isActive
    }

    /// Toast de activar/pausar Incognito (mismo chrome que el timer).
    private var incognitoBridgeToast: InAppActionToast? {
        guard let toast = service.actionToast else { return nil }
        if toast.bridgesToIncognitoPill || toast.isIncognitoPaused { return toast }
        return nil
    }

    private var incognitoPhase: IncognitoChromePhase? {
        if incognitoBridgeToast != nil {
            return .message
        }
        guard incognitoModeService.isActive else { return nil }
        // Hold + notif/acción: icono unido al banner (no ocultar el timer ni separar pastillas).
        if service.showBanner {
            return .timerIcon
        }
        return .timer
    }

    private var showsStandardBanner: Bool {
        guard service.showBanner else { return false }
        // Si Incognito está en hold, el chrome vive en `incognitoHost` (unión liquid).
        if incognitoModeService.isActive || incognitoBridgeToast != nil { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let phase = incognitoPhase {
                    incognitoHost(phase: phase)
                        .inAppBannerInteractiveRegion()
                        .padding(.top, 8)
                } else if showsStandardBanner {
                    standardBannerContent
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(isBannerInteractive)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: service.showBanner), value: service.showBanner)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: incognitoPhase), value: incognitoPhase)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: incognitoModeService.isActive), value: incognitoModeService.isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isQuickReplyExpanded)
        .onPreferenceChange(InAppBannerInteractiveRegionKey.self) { frames in
            service.interactiveFrame = frames.reduce(CGRect.null) { $0.union($1) }
        }
        .onChange(of: service.showBanner) { _, isVisible in
            if !isVisible {
                isQuickReplyExpanded = false
            }
        }
        .onChange(of: isBannerInteractive) { _, interactive in
            if !interactive {
                service.interactiveFrame = .null
            }
        }
    }

    @ViewBuilder
    private var standardBannerContent: some View {
        if let toast = service.actionToast {
            actionToastBanner(toast)
        } else if let notification = service.currentNotification {
            if isQuickReplyExpanded, notification.type == .message {
                InAppMessageQuickReplyPanel(
                    notification: notification,
                    onDismiss: collapseQuickReply
                )
                .inAppBannerInteractiveRegion()
            } else {
                compactBanner(for: notification)
            }
        }
    }

    @ViewBuilder
    private func incognitoHost(phase: IncognitoChromePhase) -> some View {
        // Una sola familia de chrome: el timer conserva identidad y la notificación
        // aparece como un segundo lóbulo del mismo GlassEffectContainer.
        let unitedWithBanner = phase == .timerIcon
        let cluster = HStack(alignment: .center, spacing: 6) {
            InAppIncognitoChrome(
                service: incognitoModeService,
                // El panel pertenece al timer completo. Una notificación lo colapsa
                // antes de convertir el timer en el icono lateral.
                showsCompactOnly: phase == .message || phase == .timerIcon,
                glassNamespace: bannerGlassNS,
                compact: {
                    morphingIncognitoChrome(phase: phase)
                }
            )

            if unitedWithBanner {
                if let toast = service.actionToast, incognitoBridgeToast == nil {
                    actionToastBanner(toast, clustered: true)
                } else if let notification = service.currentNotification {
                    if isQuickReplyExpanded, notification.type == .message {
                        InAppMessageQuickReplyPanel(
                            notification: notification,
                            onDismiss: collapseQuickReply
                        )
                    } else {
                        compactBanner(for: notification, clustered: true)
                    }
                }
            }
        }

        if #available(iOS 26.0, *) {
            // El panel vertical necesita más alcance para formar el cuello con
            // el timer. El cluster horizontal de notificación ya queda bien a 18.
            GlassEffectContainer(spacing: unitedWithBanner ? 18 : 40) { cluster }
        } else {
            cluster
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 6)
        }
    }

    /// Superficie glass cuya geometría anima (mensaje↔timer↔icono-círculo).
    @ViewBuilder
    private func morphingIncognitoChrome(phase: IncognitoChromePhase) -> some View {
        switch phase {
        case .timerIcon:
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
                .modifier(
                    InAppBannerGlassMorphID(
                        id: "incognitoPill",
                        namespace: bannerGlassNS,
                        transition: .matchedGeometry
                    )
                )

        case .message, .timer:
            HStack(spacing: 10) {
                switch phase {
                case .message:
                    if let toast = incognitoBridgeToast {
                        VStack(alignment: .leading, spacing: 2) {
                            actionTitle(toast)
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if let subtitle = toast.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                        }
                        .layoutPriority(1)
                        Image(systemName: toast.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 16, height: 16)
                    }
                case .timer:
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18, height: 18)
                    Text(incognitoModeService.formattedTime)
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .monospacedDigit()
                case .timerIcon:
                    EmptyView()
                }
            }
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .padding(.horizontal, phase == .message ? 16 : 14)
            .padding(.vertical, phase == .message ? 10 : 9)
            .frame(minHeight: 40)
            .frame(width: phase == .timer ? 108 : nil)
            .modifier(InAppBannerHugWidth(maxWidth: 340))
            .contentShape(Capsule())
            .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
            .modifier(
                InAppBannerGlassMorphID(
                    id: "incognitoPill",
                    namespace: bannerGlassNS,
                    transition: .matchedGeometry
                )
            )
        }
    }

    /// Pastilla de cristal tintado. La acción va recortada sobre la foto.
    private func compactBanner(for notification: Notification, clustered: Bool = false) -> some View {
        let isSystem = isSystemBanner(notification)
        let copy = NotificationCopyResolver.resolve(notification)
        let lines = bannerTextLines(copy: copy, notification: notification)

        return HStack(spacing: 12) {
            maskedAvatar(for: notification, isSystem: isSystem)

            VStack(alignment: .leading, spacing: 2) {
                toastSentence(lines: lines, notification: notification)

                if isSystemModerationBanner(notification), lines.detail == nil {
                    Text(moderationBannerText(for: notification))
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if !isSystem, let previewPath = contentPreviewImage, let url = URL(string: previewPath) {
                KFImage(url)
                    .applyingFeedCrop(contentPreviewFeedCrop)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .modifier(InAppBannerHugWidth(maxWidth: clustered ? 280 : 340))
        .contentShape(Capsule())
        .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
        .modifier(
            InAppBannerGlassMorphID(
                id: clustered ? "holdBanner" : "inAppBanner",
                namespace: bannerGlassNS,
                transition: clustered ? .matchedGeometry : .materialize,
                enabled: true
            )
        )
        .inAppBannerInteractiveRegion()
        .overlay {
            Color.clear
                .contentShape(Capsule())
                .onTapGesture {
                    guard Date() >= suppressTapUntil else { return }
                    handleTap(on: notification)
                }
                .simultaneousGesture(messageLongPressGesture(for: notification))
        }
        .modifier(InAppBannerClusterLayout(clustered: clustered))
        .shadow(color: clustered ? .clear : .black.opacity(0.08), radius: 8, x: 0, y: 6)
        .offset(y: dragOffset.height)
        .simultaneousGesture(dismissDragGesture)
        .onAppear {
            HapticManager.shared.notification(.success)
            loadImages(for: notification)
        }
        .onChange(of: notification.id) { _, _ in
            contentPreviewImage = nil
            contentPreviewFeedCrop = nil
            loadImages(for: notification)
        }
    }

    private func actionToastBanner(_ toast: InAppActionToast, clustered: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                actionTitle(toast)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = toast.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            if toast.showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                let icon = (toast.bridgesToIncognitoPill || toast.isIncognitoPaused)
                    ? toast.systemImage
                    : "checkmark.circle.fill"
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16)
            }

            if toast.undo != nil {
                Button {
                    service.performUndoFromActionToast()
                } label: {
                    Text(NSLocalizedString("notifications.deleted.undo", value: "Deshacer", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(Color.red)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: clustered ? 56 : 48)
        .modifier(InAppBannerHugWidth(maxWidth: clustered ? 280 : 340))
        .contentShape(Capsule())
        .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
        .modifier(
            InAppBannerGlassMorphID(
                id: clustered ? "holdBanner" : "actionToast",
                namespace: bannerGlassNS,
                transition: clustered ? .matchedGeometry : .materialize,
                enabled: clustered
            )
        )
        .inAppBannerInteractiveRegion()
        .overlay {
            if toast.undo != nil {
                UndoCountdownRing(id: toast.id, duration: toast.duration)
            }
        }
        .shadow(color: clustered ? .clear : .black.opacity(0.08), radius: 8, x: 0, y: 6)
        .offset(y: dragOffset.height)
        .simultaneousGesture(dismissDragGesture)
    }

    private func actionTitle(_ toast: InAppActionToast) -> Text {
        let sentence = Text(toast.prefix).fontWeight(.semibold)
        guard let emphasis = toast.emphasis, !emphasis.isEmpty else {
            return sentence
        }
        return sentence + Text(emphasis).fontWeight(.bold) + Text(toast.suffix).fontWeight(.semibold)
    }

    @ViewBuilder
    private func toastSentence(lines: BannerTextLines, notification: Notification) -> some View {
        if let headline = lines.headline, let detail = lines.detail, headline == notification.senderUsername {
            if detail.count > 42 {
                Text(headline)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                (Text(headline).fontWeight(.semibold) + Text(" \(detail)").fontWeight(.medium))
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        } else if let headline = lines.headline, let detail = lines.detail {
            Text(headline)
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(detail)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if let detail = lines.detail {
            Text(detail)
                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        } else if let headline = lines.headline {
            Text(headline)
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    /// Foto del emisor con el tipo recortado abajo a la derecha.
    /// Reacción de momento/historia: el glifo real (vibe, fire…), no un SF Symbol.
    private func maskedAvatar(for notification: Notification, isSystem: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            bannerAvatar(for: notification, isSystem: isSystem)
                .drawingGroup(opaque: false)
                .reversedMask(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                }

            avatarCutoutGlyph(for: notification)
                .offset(x: 2, y: 2)
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func avatarCutoutGlyph(for notification: Notification) -> some View {
        if let reaction = momentReactionGlyph(for: notification) {
            Text(reaction)
                .font(.system(size: 13))
        } else if usesCustomCutout(notification) {
            customCutoutIcon(for: notification)
        } else {
            Image(systemName: badgeSymbol(for: notification))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }

    private func usesCustomCutout(_ notification: Notification) -> Bool {
        guard !isSystemTimeLimitBanner(notification), !isSystemModerationBanner(notification) else {
            return false
        }
        switch notification.type {
        case .photoTag, .mutualConnection, .chatBuzz, .echoSuggestion:
            return true
        default:
            return false
        }
    }

    /// Mutua, zumbido, Echo y etiqueta usan el asset propio, no el SF Symbol.
    @ViewBuilder
    private func customCutoutIcon(for notification: Notification) -> some View {
        switch notification.type {
        case .photoTag:
            AttachmentIconView(icon: .tagged, size: 15, tintColor: .secondary)
        case .mutualConnection:
            AttachmentIconView(icon: .mutuals, size: 15, tintColor: .secondary)
        case .chatBuzz:
            AttachmentIconView(icon: .buzz, size: 15, tintColor: .secondary)
        case .echoSuggestion:
            EchoesIconView(size: 15, tintColor: .secondary)
        default:
            EmptyView()
        }
    }

    private func momentReactionGlyph(for notification: Notification) -> String? {
        guard notification.type == .reaction || notification.type == .storyReaction else { return nil }
        guard let raw = notification.reaction?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let type = ReactionType(rawValue: raw) {
            return type.icon
        }
        return raw
    }

    private func badgeSymbol(for notification: Notification) -> String {
        if isSystemTimeLimitBanner(notification) { return "clock.fill" }
        if isSystemModerationBanner(notification) { return "exclamationmark.shield.fill" }
        return notification.type.systemIconName
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                if value.translation.height < 0 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if value.translation.height < -20 {
                    collapseQuickReply()
                    service.dismissManually()
                }
            }
    }

    private func messageLongPressGesture(for notification: Notification) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                guard notification.type == .message, notification.conversationId != nil else { return }
                suppressTapUntil = Date().addingTimeInterval(0.6)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isQuickReplyExpanded = true
                }
                HapticManager.shared.mediumImpact()
            }
    }

    private func collapseQuickReply() {
        isQuickReplyExpanded = false
    }

    private struct BannerTextLines {
        let headline: String?
        let detail: String?
    }

    private func bannerTextLines(copy: NotificationBannerCopy, notification: Notification) -> BannerTextLines {
        if ChatNotificationThread.isGroupConversationId(notification.conversationId ?? "") {
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }
        let name = notification.senderUsername

        if isSystemTimeLimitBanner(notification) {
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }

        if notification.type == .gentleReminder {
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }

        if notification.type == .mutualConnection {
            // Título (frase) + subtitle (CTA localizado en notification.mutualConnection.body).
            return BannerTextLines(headline: copy.title, detail: copy.body)
        }

        if notification.type == .echoSuggestion {
            let sentence = copy.body?.trimmingCharacters(in: .whitespacesAndNewlines)
            return BannerTextLines(headline: nil, detail: (sentence?.isEmpty == false) ? sentence : copy.title)
        }

        if let body = copy.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            if body.hasPrefix(name) {
                return BannerTextLines(headline: nil, detail: body)
            }
            return BannerTextLines(headline: name, detail: body)
        }

        if copy.title != name {
            return BannerTextLines(headline: name, detail: copy.title)
        }

        return BannerTextLines(headline: name, detail: nil)
    }

    @ViewBuilder
    private func bannerAvatar(for notification: Notification, isSystem: Bool) -> some View {
        if isSystem {
            systemBannerAvatar(for: notification)
        } else if ChatNotificationThread.isGroupConversationId(notification.conversationId ?? "") {
            GroupChatAvatar(name: notification.groupName ?? "", image: notification.groupImage ?? "", size: 34)
        } else {
            AsyncProfileImageView(userId: notification.senderId)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    private func isSystemTimeLimitBanner(_ notification: Notification) -> Bool {
        notification.senderId == "system_time_limit"
    }

    private func isSystemModerationBanner(_ notification: Notification) -> Bool {
        notification.type == .mediaModeration
    }

    private func isSystemBanner(_ notification: Notification) -> Bool {
        isSystemTimeLimitBanner(notification) || isSystemModerationBanner(notification)
    }

    @ViewBuilder
    private func systemBannerAvatar(for notification: Notification) -> some View {
        if isSystemModerationBanner(notification) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .frame(width: 34, height: 34)
                Image(colorScheme == .dark ? "SplashLogoLight" : "SplashLogoDark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            .overlay(
                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1), lineWidth: 1)
            )
        } else {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
        }
    }

    private func loadImages(for notification: Notification) {
        if isSystemBanner(notification) { return }

        if notification.type == .mention, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: storyAuthorId(for: notification))
        } else if notification.type == .like || notification.type == .comment || notification.type == .reaction || notification.type == .mention {
            if let momentId = notification.momentId {
                fetchMomentPreview(momentId: momentId)
            }
        } else if notification.type == .storyReaction, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: notification.storyAuthorId)
        } else if notification.type == .storyChainContinued, let storyId = notification.storyId {
            fetchStoryPreview(storyId: storyId, authorId: notification.senderId)
        }
    }

    private func fetchMomentPreview(momentId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        FirestoreService().fetchMoment(momentId: momentId, userId: userId) { result in
            DispatchQueue.main.async {
                if case .success(let moment) = result {
                    contentPreviewImage = moment.previewImageURLString
                    contentPreviewFeedCrop = moment.primaryVisibleMediaItem?.feedCrop
                }
            }
        }
    }

    private func fetchStoryPreview(storyId: String, authorId: String?) {
        contentPreviewFeedCrop = nil
        guard let userId = authorId else { return }
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .getDocument { snapshot, _ in
                DispatchQueue.main.async {
                    guard let mediaItem = snapshot?.data()?["mediaItem"] as? [String: Any] else { return }
                    if let thumbnailUrl = mediaItem["thumbnailUrl"] as? String, !thumbnailUrl.isEmpty {
                        contentPreviewImage = thumbnailUrl
                    } else if let url = mediaItem["url"] as? String {
                        contentPreviewImage = url
                    }
                }
            }
    }

    private func handleTap(on notification: Notification) {
        collapseQuickReply()
        service.dismissManually()

        // Navegar en el siguiente ciclo del run loop: el overlay deja de interceptar toques
        // en cuanto showBanner pasa a false (allowsHitTesting).
        DispatchQueue.main.async {
            self.routeBannerTap(notification)
        }
    }

    private func routeBannerTap(_ notification: Notification) {
        switch notification.type {
        case .message:
            if let conversationId = notification.conversationId {
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .messageReaction:
            if let conversationId = notification.conversationId {
                if let messageId = notification.messageId {
                    ChatNavigationIntentStore.enqueueHighlight(conversationId: conversationId, messageId: messageId)
                }
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .chatBuzz:
            if let conversationId = notification.conversationId {
                ChatNavigationIntentStore.enqueueBuzz(conversationId: conversationId, buzzEventId: notification.buzzEventId)
                navigationService.navigateToConversation(conversationId: conversationId)
            }
        case .dataExportReady:
            if let rawUrl = notification.downloadURL,
               let url = URL(string: rawUrl),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        default:
            navigationService.navigateToNotifications(filter: notificationsFilter(for: notification.type))
        }
    }

    private func notificationsFilter(for type: NotificationType) -> String? {
        switch type {
        case .followRequest, .requestAccepted:
            return "requests"
        case .reaction:
            return "reactions"
        case .comment:
            return "comments"
        case .storyReaction:
            return "stories"
        case .newFollower, .mutualConnection:
            return "follows"
        default:
            return nil
        }
    }

    private func storyAuthorId(for notification: Notification) -> String? {
        if notification.type == .storyReaction {
            return notification.storyAuthorId
                ?? notification.targetAuthorId
                ?? Auth.auth().currentUser?.uid
                ?? notification.senderId
        }
        return notification.storyAuthorId ?? notification.targetAuthorId ?? notification.senderId
    }

    private func moderationBannerText(for notification: Notification) -> String {
        if let message = notification.message, !message.isEmpty { return message }
        let moderationType = notification.reaction ?? "partial"
        let moderationScope = notification.moderationScope ?? "post"

        if moderationScope == "storySticker" {
            return NSLocalizedString("banner.verb.mediaModeration.storySticker.partial", value: "We hid a sticker from your story", comment: "")
        }
        if moderationScope == "postHiddenLayer" {
            return NSLocalizedString("banner.verb.mediaModeration.postHiddenLayer.partial", value: "We hid a hidden layer from your post", comment: "")
        }
        if moderationScope == "story" {
            return moderationType == "full"
                ? NSLocalizedString("banner.verb.mediaModeration.story.full", value: "Your story is now only visible to you", comment: "")
                : NSLocalizedString("banner.verb.mediaModeration.story.partial", value: "Some content was hidden from your story", comment: "")
        }
        return NSLocalizedString("banner.verb.mediaModeration.partial", value: "Some content was hidden from your post", comment: "")
    }
}

/// La pastilla mide el contenido y no pasa de `maxWidth`.
private struct InAppBannerHugWidth: ViewModifier {
    var maxWidth: CGFloat

    func body(content: Content) -> some View {
        InAppBannerHugLayout(maxWidth: maxWidth) {
            content
        }
    }
}

/// iOS 26+: identidad estable dentro del `GlassEffectContainer` compartido.
private struct InAppBannerGlassMorphID: ViewModifier {
    enum TransitionKind {
        case matchedGeometry
        case materialize
    }

    let id: String
    let namespace: Namespace.ID
    var transition: TransitionKind = .matchedGeometry
    var enabled: Bool = true

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), enabled {
            content
                .glassEffectID(id, in: namespace)
                .glassEffectTransition(sdkTransition)
        } else {
            content
        }
    }

    @available(iOS 26.0, *)
    private var sdkTransition: GlassEffectTransition {
        switch transition {
        case .matchedGeometry: return .matchedGeometry
        case .materialize: return .materialize
        }
    }
}

/// En cluster (hold+banner): hug al lado del icono. Solo: ancho completo centrado.
private struct InAppBannerClusterLayout: ViewModifier {
    var clustered: Bool

    func body(content: Content) -> some View {
        if clustered {
            content
        } else {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
        }
    }
}

private struct InAppBannerHugLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified)
        let offered = min(proposal.width ?? maxWidth, maxWidth)
        let width = min(ideal.width, offered)
        let height = subview.sizeThatFits(
            ProposedViewSize(width: width, height: proposal.height)
        ).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

private struct InAppBannerInteractiveRegionKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func inAppBannerInteractiveRegion() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InAppBannerInteractiveRegionKey.self,
                    value: [proxy.frame(in: .global)]
                )
            }
        }
    }
}

/// Ventana por encima de sheets y pantallas completas. Solo la pastilla recibe toques.
@MainActor
final class InAppBannerWindowPresenter {
    static let shared = InAppBannerWindowPresenter()
    private var window: InAppBannerPassWindow?

    func install(in scene: UIWindowScene) {
        guard window == nil else { return }
        let host = UIHostingController(rootView: InAppBannerView())
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        let window = InAppBannerPassWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }
}

private final class InAppBannerPassWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let (allows, interactiveFrame) = MainActor.assumeIsolated { () -> (Bool, CGRect) in
            let service = InAppNotificationService.shared
            return (
                service.showBanner || IncognitoModeService.shared.isActive,
                service.interactiveFrame
            )
        }
        guard allows else { return nil }

        // Solo el chrome que se ve intercepta. La antigua banda superior a todo
        // lo ancho bloqueaba controles vecinos como la campana del perfil.
        guard !interactiveFrame.isNull,
              interactiveFrame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }

        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === self { return nil }
        // La vista raíz de UIHostingController también hospeda los gestos SwiftUI.
        // Devolver nil aquí descartaba los taps del banner junto con el fondo.
        return hit
    }
}

struct InAppBannerWindowAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let scene = uiView.window?.windowScene else { return }
            InAppBannerWindowPresenter.shared.install(in: scene)
        }
    }
}

private struct UndoCountdownRing: View {
    let id: UUID
    let duration: TimeInterval
    @State private var progress: CGFloat = 1

    var body: some View {
        Capsule()
            .trim(from: 0, to: progress)
            .stroke(
                Color.red.opacity(0.85),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .allowsHitTesting(false)
            .onAppear { restart() }
            .onChange(of: id) { _, _ in restart() }
    }

    private func restart() {
        progress = 1
        withAnimation(.linear(duration: duration)) {
            progress = 0
        }
    }
}
