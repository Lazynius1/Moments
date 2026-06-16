import SwiftUI
import UIKit
import FirebaseAuth

enum NovaInputBarLayout {
    static let bottomPaddingWithoutKeyboard: CGFloat = 8
    /// Aire visible entre sheet y tab bar.
    static let sheetAboveTabBarGap: CGFloat = 12
    /// Tab bar sobre home indicator (pill flotante iOS 26 incluye margen extra).
    static var tabBarClearance: CGFloat {
        if #available(iOS 26.0, *) {
            74
        } else {
            52
        }
    }

    static func bottomPadding(keyboardHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        keyboardHeight > 0
            ? keyboardHeight - safeAreaBottom + bottomPaddingWithoutKeyboard
            : bottomPaddingWithoutKeyboard
    }

    /// Borde inferior del sheet, por encima de la tab bar.
    static func attachmentSheetBottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + tabBarClearance + sheetAboveTabBarGap
    }
}

// MARK: - EnhancedInputBar
struct EnhancedInputBar: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showSuggestedOptions: Bool
    @Binding var activeAttachmentSheet: NovaAttachmentSheetKind?
    @Binding var attachmentMenuPresentationTrigger: Int
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    // ✅ CALLBACK PARA NOTIFICAR CUANDO EL TEXTOFIELD OBTIENE FOCUS
    var onFocusChange: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                // ⭐ VISTA PREVIA DE IMAGEN SELECCIONADA
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
                                    .foregroundColor(.white)
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

                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        NovaAttachmentMenuButton(
                            presentationTrigger: attachmentMenuPresentationTrigger,
                            tint: UIColor(NovaColors.textPrimary),
                            onCamera: {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                    activeAttachmentSheet = .camera
                                }
                            },
                            onPhotos: {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                    activeAttachmentSheet = .photos
                                }
                            }
                        )
                        .frame(width: 34, height: 34)
                        .accessibilityLabel(Text("nova.input.attach.accessibility"))

                        // ✅ TextField: crece hacia arriba, alineado al centro
                        TextField(NSLocalizedString("nova.input.placeholder", comment: "Ask Nova something placeholder"), text: $viewModel.inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(NovaColors.textPrimary)
                            .padding(.vertical, 10)
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
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(
                                        isTextFieldFocused ? NovaColors.textPrimary.opacity(0.14) : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                    }

                    // ✅ Botón enviar alineado al centro
                    if !viewModel.inputText.isEmpty {
                        Button(action: {
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                            isTextFieldFocused = false
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(NovaColors.textPrimary)
                                .frame(width: 44, height: 44)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: Circle(), interactive: true)
                                }
                        }
                        .accessibilityLabel(Text("nova.input.send.accessibility"))
                        .transition(MotionPolicy.reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .background(Color.clear)
        .animation(MotionPolicy.animation(.easeInOut(duration: 0.25), value: viewModel.inputText.isEmpty), value: viewModel.inputText.isEmpty)
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
                    .foregroundColor(NovaColors.textPrimary)
                    .frame(width: style == .hero ? 28 : 14)

                Text(suggestion.text)
                    .font(.custom(style == .hero ? "Poppins-SemiBold" : "Poppins-Medium", size: style == .hero ? 15 : 14))
                    .foregroundColor(NovaColors.textPrimary)

                if style == .hero {
                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(NovaColors.textSecondary)
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
                        .liquidGlass(in: Capsule(), interactive: true)
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

// MARK: - Native + menu (reapertura programática al volver desde cámara/fotos)

private struct NovaAttachmentMenuButton: UIViewRepresentable {
    let presentationTrigger: Int
    let tint: UIColor
    let onCamera: () -> Void
    let onPhotos: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCamera: onCamera, onPhotos: onPhotos)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        config.contentInsets = .zero
        button.configuration = config
        button.tintColor = tint
        button.showsMenuAsPrimaryAction = true
        button.menu = context.coordinator.makeMenu()
        button.accessibilityLabel = NSLocalizedString(
            "nova.input.attach.accessibility",
            comment: "Attach media to Nova"
        )
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.tintColor = tint
        button.menu = context.coordinator.makeMenu()
        context.coordinator.button = button
        context.coordinator.presentMenuIfNeeded(trigger: presentationTrigger)
    }

    final class Coordinator: NSObject {
        var button: UIButton?
        private var lastPresentationTrigger = 0
        private let onCamera: () -> Void
        private let onPhotos: () -> Void

        init(onCamera: @escaping () -> Void, onPhotos: @escaping () -> Void) {
            self.onCamera = onCamera
            self.onPhotos = onPhotos
        }

        func makeMenu() -> UIMenu {
            let camera = UIAction(
                title: NSLocalizedString("nova.attach.camera", comment: "Camera"),
                image: UIImage(systemName: "camera.fill")
            ) { [weak self] _ in
                self?.onCamera()
            }

            let photos = UIAction(
                title: NSLocalizedString("nova.attach.photos", comment: "Photos"),
                image: UIImage(systemName: "photo.on.rectangle.angled")
            ) { [weak self] _ in
                self?.onPhotos()
            }

            return UIMenu(children: [camera, photos])
        }

        func presentMenuIfNeeded(trigger: Int) {
            guard trigger > lastPresentationTrigger else { return }
            lastPresentationTrigger = trigger
            guard let button else { return }
            button.performPrimaryAction()
        }
    }
}

// MARK: - Utilities y Extensions
struct NovaScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
