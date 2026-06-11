import SwiftUI
import FirebaseAuth
import PhotosUI

// MARK: - EnhancedInputBar
struct EnhancedInputBar: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showSuggestedOptions: Bool
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
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
                                selectedItem = nil
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
                        // ✅ Botón + alineado al centro
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(NovaColors.textPrimary)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel(Text("nova.input.addPhoto.accessibility"))
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    await MainActor.run {
                                        viewModel.selectedImage = image
                                    }
                                }
                            }
                        }

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

// MARK: - Utilities y Extensions
struct NovaScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
