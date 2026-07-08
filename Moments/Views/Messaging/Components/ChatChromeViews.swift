import SwiftUI
import UIKit

// MARK: - Swipe back nativo

/// Reactiva `interactivePopGestureRecognizer` aunque el back button del sistema esté oculto.
private struct NavigationInteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var savedPopDelegate: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigationController,
                  let pop = navigationController.interactivePopGestureRecognizer else { return }

            savedPopDelegate = pop.delegate
            pop.isEnabled = true
            pop.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = savedPopDelegate
            savedPopDelegate = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
                return true
            }
            guard (navigationController?.viewControllers.count ?? 0) > 1 else { return false }

            // Bajar teclado al iniciar el swipe back.
            view.window?.endEditing(true)
            return true
        }
    }
}

// MARK: - Chat toolbar + scroll edge (API nativa iOS 26)

/// Círculo glass por botón (con `sharedBackgroundVisibility(.hidden)` en el toolbar).
struct ChatToolbarIconGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.momentsChromeGlass(in: Circle(), interactive: true)
    }
}

struct ChatToolbarScrollEdgeModifier: ViewModifier {
    var hardBottomEdge = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if hardBottomEdge {
                content
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollEdgeEffectStyle(.hard, for: .bottom)
            } else {
                content.scrollEdgeEffectStyle(.soft, for: .top)
            }
        } else {
            content
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.04),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
    }
}

extension View {
    func momentsScrollEdgeChrome(hardBottomEdge: Bool = false) -> some View {
        modifier(ChatToolbarScrollEdgeModifier(hardBottomEdge: hardBottomEdge))
    }

    /// Lista de conversaciones: solo difuminado superior. En el hilo, `hardBottomEdge: true` recorta el borde inferior en el composer.
    func chatScrollEdgeEffect(hardBottomEdge: Bool = false) -> some View {
        momentsScrollEdgeChrome(hardBottomEdge: hardBottomEdge)
    }

    func messagingListEdgeToEdge() -> some View {
        modifier(MessagingListSectionMarginsModifier())
    }

    @ViewBuilder
    func chatBottomBarInset<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }

    /// Swipe desde el borde izquierdo para volver a la lista (push/pop nativo).
    func chatInteractivePopEnabled() -> some View {
        background(NavigationInteractivePopEnabler())
    }

    /// Reporta la altura del composer (input + reply) para re-anclar scroll cuando crece.
    func chatComposerHeightReporting() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ChatComposerHeightKey.self, value: geo.size.height)
            }
        }
    }

    func onChatComposerHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onPreferenceChange(ChatComposerHeightKey.self, perform: action)
    }
}

private struct ChatComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MessagingListSectionMarginsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.listSectionMargins(.horizontal, 0)
        } else {
            content
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func chatHideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Cápsula glass flotante al paginar historial (misma familia que `ChatBuzzToast`).
struct ChatHistoryLoadingIndicator: View {
    let adaptiveColors: AdaptiveColors
    var textKey: LocalizedStringKey = "chat.loadingOlderMessages"
    var showsProgress: Bool = true
    var retryTextKey: LocalizedStringKey? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var shape: Capsule { Capsule(style: .continuous) }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .momentsChromeGlass(in: shape, interactive: false)
        .clipShape(shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(
                        tint: colorScheme == .dark ? .white : adaptiveColors.primary
                    ))
                    .scaleEffect(0.78)
            }
            Text(textKey)
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.82))
            if let retryTextKey {
                Text(retryTextKey)
                    .font(.system(size: legacyPoppinsSize(12), weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)
            }
        }
    }
}

/// Marca sutil al llegar al inicio del historial disponible.
struct ChatHistoryStartHeader: View {
    let adaptiveColors: AdaptiveColors

    var body: some View {
        Text("chat.historyStart")
            .font(.system(size: legacyPoppinsSize(12)))
            .foregroundStyle(adaptiveColors.secondary.opacity(0.85))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }
}

struct ChatConversationIntroRow: View {
    let context: PendingChatContext?
    let fallbackName: String
    let fallbackUserId: String
    let adaptiveColors: AdaptiveColors

    private var displayName: String {
        context?.otherUsername ?? fallbackName
    }

    private var userId: String {
        context?.otherUserId ?? fallbackUserId
    }

    private var username: String {
        context?.otherUsername ?? fallbackName
    }

    private var subtitleKey: LocalizedStringKey {
        if let context {
            switch context.status {
            case .normalConversation:
                return "chat.intro.normal"
            case .incomingRequestPending:
                return "chat.intro.request.incoming"
            case .outgoingRequestDraft:
                return "chat.intro.request.outgoing"
            case .outgoingRequestSent:
                return "chat.intro.request.sent"
            case .outgoingRequestBlocked:
                return "chat.intro.request.blocked"
            }
        }
        return "chat.intro.normal"
    }

    private var statsText: String? {
        guard let context else { return nil }
        let followers = context.otherFollowersCount ?? 0
        let moments = context.otherMomentsCount ?? 0
        guard followers > 0 || moments > 0 else { return nil }
        return String(
            format: NSLocalizedString("chat.intro.profileStats", comment: "Pending chat profile stats"),
            MomentsFormat.count(followers, style: .profileStat),
            MomentsFormat.count(moments, style: .profileStat)
        )
    }

    private var showsStatusSubtitle: Bool {
        context?.status != .outgoingRequestDraft
    }

    private var relationshipText: String? {
        guard let context else { return nil }
        if context.viewerFollowsOther == true, context.otherFollowsViewer == true {
            if let date = [context.viewerFollowedAt, context.otherFollowedViewerAt].compactMap({ $0 }).max() {
                return String(
                    format: NSLocalizedString("chat.intro.relationship.mutualSince", comment: "Mutual follow since year"),
                    username,
                    yearString(from: date)
                )
            }
            return String(
                format: NSLocalizedString("chat.intro.relationship.mutual", comment: "Users follow each other"),
                username
            )
        }
        if context.viewerFollowsOther == true {
            if let viewerFollowedAt = context.viewerFollowedAt {
                return String(
                    format: NSLocalizedString("chat.intro.relationship.viewerFollowsSince", comment: "Viewer follows user since year"),
                    username,
                    yearString(from: viewerFollowedAt)
                )
            }
            return String(
                format: NSLocalizedString("chat.intro.relationship.viewerFollows", comment: "Viewer follows user"),
                username
            )
        }
        if context.otherFollowsViewer == true {
            if let otherFollowedViewerAt = context.otherFollowedViewerAt {
                return String(
                    format: NSLocalizedString("chat.intro.relationship.otherFollowsViewerSince", comment: "Other follows viewer since year"),
                    username,
                    yearString(from: otherFollowedViewerAt)
                )
            }
            return String(
                format: NSLocalizedString("chat.intro.relationship.otherFollowsViewer", comment: "Other user follows viewer"),
                username
            )
        }
        return NSLocalizedString("chat.intro.relationship.notMutual", comment: "Users do not follow each other")
    }

    var body: some View {
        VStack(spacing: 12) {
            AsyncProfileImageView(userId: userId)
                .frame(width: 96, height: 96)
                .clipShape(Circle())

            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.system(size: legacyPoppinsSize(25), weight: .bold))
                        .foregroundStyle(adaptiveColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if context?.otherIsVerified == true {
                        VerifiedBadge(size: 20)
                    }
                }

                if let statsText {
                    Text(statsText)
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(adaptiveColors.secondary)
                        .lineLimit(1)
                }

                if showsStatusSubtitle {
                    Text(subtitleKey)
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(adaptiveColors.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                if let relationshipText {
                    Text(relationshipText)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(adaptiveColors.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 46)
        .padding(.bottom, 22)
    }

    private func yearString(from date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }
}

struct ChatRequestInviteNotice: View {
    let displayName: String
    let username: String
    let adaptiveColors: AdaptiveColors

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paperplane")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(adaptiveColors.secondary)
                .frame(width: 36, height: 36)
                .momentsChromeGlass(in: Circle(), interactive: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("chat.request.invite.title", comment: "Invite user to chat title"), displayName, username))
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("chat.request.invite.body")
                    .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                    .foregroundStyle(adaptiveColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

struct ChatRequestDisclaimerRow: View {
    let textKey: LocalizedStringKey
    let adaptiveColors: AdaptiveColors

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)

            Text(textKey)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(adaptiveColors.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16), interactive: false)
    }
}

struct PendingRequestMessageRow: View {
    let message: PendingChatTimelineMessage
    let adaptiveColors: AdaptiveColors

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 6) {
                switch message.messageType {
                case .image:
                    mediaLabel(systemName: "photo", textKey: "messageRequests.image")
                case .video:
                    mediaLabel(systemName: "play.rectangle", textKey: "messageRequests.video")
                default:
                    Text(message.text)
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundStyle(message.isOutgoing ? Color.white : adaptiveColors.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(message.isOutgoing ? AnyShapeStyle(Color.blue.opacity(0.92)) : AnyShapeStyle(adaptiveColors.cardBackground))
            )

            if !message.isOutgoing {
                Spacer(minLength: 48)
            }
        }
    }

    private func mediaLabel(systemName: String, textKey: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
            Text(textKey)
        }
        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
        .foregroundStyle(message.isOutgoing ? Color.white : adaptiveColors.primary)
    }
}

/// Encabezado de sección en listas de mensajes (misma fuente que el toolbar).
struct MessagingSectionHeader: View {
    let title: LocalizedStringKey
    let adaptiveColors: AdaptiveColors

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(adaptiveColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct ChatTintedGlassCircleButton: View {
    let systemName: String
    let tint: Color
    let foregroundColor: Color
    var size: CGFloat = 40
    var iconSize: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .modifier(ChatTintedGlassCircleModifier(tint: tint))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ChatTintedGlassCircleModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content.momentsChromeGlass(in: Circle(), interactive: true, tint: tint)
    }
}

// MARK: - Chat Background
struct ChatGlassmorphicBackground: View {
    let adaptiveColors: AdaptiveColors
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                adaptiveColors.chatBackground[0]
                    .ignoresSafeArea()
            } else {
                adaptiveColors.chatBackground[0]
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func glassmorphicChat() -> some View {
        modifier(GlassmorphicModifier())
    }

    func glassmorphicChatCircle() -> some View {
        modifier(GlassmorphicCircleModifier())
    }
}

struct GlassmorphicModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.3 : 0.6)

                    Rectangle()
                        .fill(
                            colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.white.opacity(0.7)
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.2) :
                        Color.black.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
    }
}

struct GlassmorphicCircleModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.3 : 0.6)

                    Circle()
                        .fill(
                            colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.white.opacity(0.7)
                        )
                }
            )
            .overlay(
                Circle()
                    .stroke(
                        colorScheme == .dark
                        ? Color.white.opacity(0.2)
                        : Color.black.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Supporting Views
struct GlassmorphicDateHeader: View {
    let date: Date
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        Text(formatDate(date))
            .font(.system(size: legacyPoppinsSize(12)))
            .foregroundColor(adaptiveColors.dateHeaderColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .glassmorphicChat()
            .clipShape(Capsule())
    }

    private func formatDate(_ date: Date) -> String {
        MomentsFormat.smartDate(from: date, context: .chatSeparator)
    }
}

struct GlassmorphicUnreadDivider: View {
    var unreadCount: Int = 0
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var dividerText: Text {
        if unreadCount > 1 {
            return Text(String(format: NSLocalizedString("chat.unreadCount.preview", comment: "Unread messages count"), unreadCount))
        }
        return Text("chat.newMessages")
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.25))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                dividerText
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
            }
            .foregroundColor(adaptiveColors.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(adaptiveColors.chatInputBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(adaptiveColors.messageBubbleStroke.opacity(0.7), lineWidth: 0.5)
            )

            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.25))
                .frame(height: 1)
        }
    }
}

struct GlassmorphicAvatar: View {
    let userId: String
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        AsyncProfileImageView(userId: userId)
            .shadow(color: adaptiveColors.primary.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct GlassmorphicTypingIndicator: View {
    @State private var animationAmounts = [0.0, 0.0, 0.0]
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(adaptiveColors.typingIndicatorColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(reduceMotion ? 0.85 : animationAmounts[index])
                    .opacity(reduceMotion ? 0.85 : animationAmounts[index])
                    .onAppear {
                        // Con reduceMotion los puntos quedan estáticos, sin pulso infinito.
                        guard !reduceMotion else { return }
                        withAnimation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2)
                        ) {
                            animationAmounts[index] = 1.0
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassmorphicChat()
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MessagingActionToast: View {
    let text: String
    let colorScheme: ColorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Text(text)
            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .momentsChromeGlass(in: shape, interactive: false)
            .clipShape(shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 18, x: 0, y: 10)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Scroll down FAB

struct ChatScrollDownButton: View {
    let pendingCount: Int
    let accentColor: Color
    let badgeTextColor: Color
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let action: () -> Void

    @State private var didAppear = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
                    .frame(width: 40, height: 40)
                    .momentsChromeGlass(in: Circle(), interactive: true)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 6, x: 0, y: 2)

                if pendingCount > 0 {
                    Text(pendingCount > 99 ? "99+" : "\(pendingCount)")
                        .font(.system(size: legacyPoppinsSize(10), weight: .semibold))
                        .foregroundStyle(badgeTextColor)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(accentColor)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(didAppear ? 1 : 0.2)
        .opacity(didAppear ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                didAppear = true
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                didAppear = true
            }
        }
        .onDisappear {
            didAppear = false
        }
        .accessibilityLabel(Text(LocalizedStringKey("chat.scrollToBottom.accessibility")))
    }
}

// MARK: - Búsqueda in-thread

struct ChatInThreadSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let adaptiveColors: AdaptiveColors
    var onClear: () -> Void
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(adaptiveColors.secondary.opacity(0.75))

            TextField(LocalizedStringKey("chat.search.placeholder"), text: $text)
                .font(.system(size: legacyPoppinsSize(15)))
                .foregroundStyle(adaptiveColors.primary)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused(focused)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(adaptiveColors.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
