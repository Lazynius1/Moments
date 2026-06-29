import SwiftUI

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

/// Spinner fijo arriba del hilo al paginar historial (estilo Instagram).
struct ChatHistoryLoadingIndicator: View {
    let adaptiveColors: AdaptiveColors

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: adaptiveColors.primary))
                .scaleEffect(0.85)
            Text("chat.loadingOlderMessages")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(adaptiveColors.secondary)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
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
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.25))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                Text("chat.newMessages")
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

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(adaptiveColors.typingIndicatorColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmounts[index])
                    .opacity(animationAmounts[index])
                    .onAppear {
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
