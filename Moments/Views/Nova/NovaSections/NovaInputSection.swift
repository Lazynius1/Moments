import SwiftUI
import FirebaseAuth

enum NovaInputBarLayout {
    /// Misma separación inferior que el compositor de chat (`ChatComposerChromeMetrics.panelHomeGap`).
    /// El input ignora el safe area inferior, igual que chat.
    static let bottomPaddingWithoutKeyboard: CGFloat = ChatComposerChromeMetrics.panelHomeGap
    /// Aire visible entre sheet e input (como `ChatInputBarLayout.sheetAboveInputGap`).
    static let sheetAboveInputGap: CGFloat = 12

    static func bottomPadding(keyboardVisible: Bool) -> CGFloat {
        ChatComposerChromeMetrics.panelBottomGap(keyboardVisible: keyboardVisible)
    }

    /// Borde inferior del sheet, por encima del input (Nova no usa safeAreaInset del compositor).
    static func attachmentSheetBottomInset() -> CGFloat {
        bottomPaddingWithoutKeyboard
            + ChatComposerChromeMetrics.estimatedComposerChromeHeight
            + sheetAboveInputGap
    }
}

struct NovaPlusButtonAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct NovaAttachmentPlusButton: View {
    let isMenuOpen: Bool
    let usesStandaloneGlass: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .momentsChromeGlass(
                        in: Circle(),
                        interactive: true,
                        isEnabled: usesStandaloneGlass
                    )

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NovaColors.textPrimary)
                    .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("nova.input.attach.accessibility"))
        .animation(MotionPolicy.animation(MotionPolicy.Spring.sheet, value: isMenuOpen), value: isMenuOpen)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: NovaPlusButtonAnchorKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }
}

// MARK: - EnhancedInputBar
struct EnhancedInputBar: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showSuggestedOptions: Bool
    @Binding var activeAttachmentSheet: NovaAttachmentSheetKind?
    let isKeyboardVisible: Bool
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    var onFocusChange: ((Bool) -> Void)?

    private var isMenuOpen: Bool {
        activeAttachmentSheet == .menu
    }

    private var usesUnifiedComposerSurface: Bool {
        isKeyboardVisible || !viewModel.inputText.isEmpty
    }

    private var inputFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var unifiedComposerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    private func toggleAttachmentMenu() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            activeAttachmentSheet = isMenuOpen ? nil : .menu
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                if let selectedImage = viewModel.selectedImage {
                    HStack {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 4)

                            Button(action: {
                                viewModel.selectedImage = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                    .font(.system(size: 20))
                            }
                            .accessibilityLabel(Text("nova.input.removePhoto.accessibility"))
                            .offset(x: 10, y: -10)
                        }
                        .padding(.top, 8)
                        .padding(.leading, 20)

                        Spacer()
                    }
                    .transition(MotionPolicy.reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }

                HStack(alignment: .bottom, spacing: usesUnifiedComposerSurface ? 0 : 10) {
                    NovaAttachmentPlusButton(
                        isMenuOpen: isMenuOpen,
                        usesStandaloneGlass: !usesUnifiedComposerSurface,
                        action: toggleAttachmentMenu
                    )

                    TextField(
                        NSLocalizedString("nova.input.placeholder", comment: "Ask Nova something placeholder"),
                        text: $viewModel.inputText,
                        axis: .vertical
                    )
                    .lineLimit(1...6)
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundStyle(NovaColors.textPrimary)
                    // Misma cápsula que chat en reposo: tipografía 15 + pad 8 → min 44.
                    // Sin el padding interior extra del compositor unificado (Nova no lo usa).
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .focused($isTextFieldFocused)
                    .onChange(of: isTextFieldFocused) { _, focused in
                        onFocusChange?(focused)
                    }
                    .onSubmit {
                        if !viewModel.inputText.isEmpty {
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                        }
                    }
                    .background {
                        Color.clear
                            .momentsChromeGlass(
                                in: inputFieldShape,
                                interactive: true,
                                isEnabled: !usesUnifiedComposerSurface
                            )
                    }
                    .overlay {
                        inputFieldShape
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                lineWidth: 0.8
                            )
                            .opacity(usesUnifiedComposerSurface ? 0 : 1)
                            .allowsHitTesting(false)
                    }

                    if !viewModel.inputText.isEmpty {
                        Button(action: {
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(NovaColors.textPrimary)
                                .frame(width: 44, height: 44)
                                .background {
                                    Color.clear
                                        .momentsChromeGlass(
                                            in: Circle(),
                                            interactive: true,
                                            isEnabled: !usesUnifiedComposerSurface
                                        )
                                }
                        }
                        .accessibilityLabel(Text("nova.input.send.accessibility"))
                        .transition(MotionPolicy.reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                // Igual que chat: reserva desde reposo la geometría de la cápsula
                // fusionada para que el teclado no cambie también la altura del composer.
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .momentsChromeGlass(
                    in: unifiedComposerShape,
                    interactive: false,
                    isEnabled: usesUnifiedComposerSurface,
                    style: .native
                )
                .overlay {
                    unifiedComposerShape
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                        .opacity(usesUnifiedComposerSurface ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color.clear)
        .animation(MotionPolicy.animation(.easeInOut(duration: 0.25), value: viewModel.inputText.isEmpty), value: viewModel.inputText.isEmpty)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isMenuOpen)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: usesUnifiedComposerSurface), value: usesUnifiedComposerSurface)
    }
}

// MARK: - Sugerencias de bienvenida (estáticas, localizadas)
struct SmartSuggestionChips: View {
    enum SuggestionType {
        case welcome
    }

    @ObservedObject var viewModel: NovaAgent
    @Binding var showSuggestedOptions: Bool
    let type: SuggestionType

    var body: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.welcomeSuggestions) { suggestion in
                SmartSuggestionChip(
                    suggestion: SmartSuggestion(text: suggestion.title, icon: suggestion.icon, action: suggestion.prompt),
                    style: .hero
                ) {
                    viewModel.inputText = suggestion.prompt
                    viewModel.sendMessage()
                }
            }
        }
    }
}

struct SmartSuggestion: Codable {
    let text: String
    let icon: String
    var action: String? = nil
}

// MARK: - Shimmer Effect para Nova
extension View {
    func shimmer() -> some View {
        self.modifier(NovaShimmerModifier())
    }
}

struct NovaShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .onAppear {
                guard !MotionPolicy.reduceMotion else { return }
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
            .onDisappear {
                phase = 0
            }
    }
}

struct SmartSuggestionChip: View {
    let suggestion: SmartSuggestion
    var style: Style = .compact
    let action: () -> Void

    enum Style {
        case compact
        case hero
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: style == .hero ? 12 : 8) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: style == .hero ? 15 : 14, weight: .medium))
                    .foregroundStyle(NovaColors.textPrimary)
                    .frame(width: style == .hero ? 28 : 14)

                Text(suggestion.text)
                    .font(.system(size: legacyPoppinsSize(style == .hero ? 15 : 14), weight: style == .hero ? .semibold : .medium))
                    .foregroundStyle(NovaColors.textPrimary)

                if style == .hero {
                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, style == .hero ? 16 : 10)
            .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)
            .background {
                if style == .hero {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(NovaColors.materialBackground)
                } else {
                    Color.clear
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
            }
            .overlay {
                if style == .hero {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(NovaColors.borderColor, lineWidth: 1)
                }
            }
        }
    }
}
