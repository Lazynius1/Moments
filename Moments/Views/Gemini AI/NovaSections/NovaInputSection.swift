import SwiftUI
import FirebaseAuth
import PhotosUI

// MARK: - EnhancedInputBar
struct EnhancedInputBar: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
    @Environment(\.colorScheme) var colorScheme

    // ✅ CALLBACK PARA NOTIFICAR CUANDO EL TEXTOFIELD OBTIENE FOCUS
    var onFocusChange: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            if viewModel.showSuggestedOptions {
                if !viewModel.conversationHistory.isEmpty && !viewModel.followUpSuggestions.isEmpty {
                    SmartSuggestionChips(viewModel: viewModel, showSuggestedOptions: $viewModel.showSuggestedOptions, type: .followUp)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

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
                            .offset(x: 10, y: -10)
                        }
                        .padding(.top, 8)
                        .padding(.leading, 20)

                        Spacer()
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        // ✅ Botón para adjuntar imágenes
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(ModernGeminiColors.textPrimary)
                                .frame(width: 34, height: 34)
                        }
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

                        // ✅ TextField con cambios en el overlay para rendimiento
                        TextField(NSLocalizedString("nova.input.placeholder", comment: "Ask Nova something placeholder"), text: $viewModel.inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(ModernGeminiColors.textPrimary)
                            .padding(.vertical, 12)
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
                    .padding(.trailing, 16)
                    .background {
                        Color.clear
                            .liquidGlass(in: Capsule(), interactive: true)
                            .overlay {
                                Capsule()
                                    .stroke(
                                        isTextFieldFocused ? ModernGeminiColors.textPrimary.opacity(0.14) : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                    }

                    HStack(spacing: 8) {
                        // ✅ Ahora solo el botón de enviar, se muestra si hay texto.
                        if !viewModel.inputText.isEmpty { // Si hay texto, mostrar botón de enviar
                            Button(action: {
                                viewModel.sendMessage()
                                showSuggestedOptions = false
                                isTextFieldFocused = false
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(ModernGeminiColors.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                            }
                            .padding(.bottom, 2) // Pequeño ajuste para aliñar con el círculo
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .background(Color.clear)
        // ✅ Animar solo la aparición/desaparición del botón enviar
        .animation(.easeInOut(duration: 0.25), value: viewModel.inputText.isEmpty)
    }
}

// MARK: - Sugerencias Inteligentes Dinámicas
struct SmartSuggestionChips: View {
    enum SuggestionType {
        case welcome
        case followUp
    }

    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    let type: SuggestionType

    @State private var dynamicSuggestions: [DynamicSuggestion] = []
    @State private var isLoadingSuggestions = true

    var body: some View {
        Group {
            if type == .welcome {
                VStack(spacing: 12) {
                    if isLoadingSuggestions {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 18)
                                .fill(ModernGeminiColors.secondaryBackground)
                                .frame(height: 56)
                                .shimmer()
                        }
                    } else {
                        let suggestions = dynamicSuggestions.map { SmartSuggestion(text: $0.text, icon: $0.icon, action: $0.action) }

                        ForEach(suggestions.prefix(3), id: \.text) { suggestion in
                            SmartSuggestionChip(
                                suggestion: suggestion,
                                style: .hero
                            ) {
                                viewModel.inputText = suggestion.action ?? suggestion.text
                                viewModel.sendMessage()
                            }
                        }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    followUpSuggestionContent
                        .padding(.vertical, 2)
                }
                .scrollContentBackground(.hidden)
                .scrollClipDisabled()
                .background(Color.clear)
            }
        }
        .onAppear {
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userData) { _, _ in
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userMemory?.id ?? "") { _, _ in
            loadDynamicSuggestions()
        }
    }

    private func loadDynamicSuggestions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isLoadingSuggestions = true
        NovaSuggestionService.shared.generateDynamicSuggestions(
            userId: userId,
            userMemory: viewModel.userMemory,
            userData: viewModel.userData
        ) { suggestions in
            Task { @MainActor in
                self.dynamicSuggestions = suggestions
                self.isLoadingSuggestions = false
            }
        }
    }

    private var followUpSuggestionContent: some View {
        HStack(spacing: 10) {
            if viewModel.isLoadingFollowUps {
                ForEach(0..<3) { _ in
                    Capsule()
                        .fill(ModernGeminiColors.secondaryBackground)
                        .frame(width: 120, height: 40)
                        .shimmer()
                }
            } else {
                ForEach(viewModel.followUpSuggestions.prefix(3), id: \.text) { suggestion in
                    SmartSuggestionChip(
                        suggestion: suggestion
                    ) {
                        viewModel.inputText = suggestion.action ?? suggestion.text
                        viewModel.sendMessage()
                    }
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

// MARK: - Sugerencias Dinámicas para Welcome Section
struct DynamicWelcomeSuggestions: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    @State private var dynamicSuggestions: [DynamicSuggestion] = []
    @State private var isLoadingSuggestions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("nova.quickSuggestions")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(ModernGeminiColors.textPrimary)

                Spacer()

                Image(systemName: "lightbulb.fill")
                    .foregroundColor(ModernGeminiColors.accent)
                    .font(.system(size: 16))
            }

            if isLoadingSuggestions {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(ModernGeminiColors.secondaryBackground)
                            .frame(height: 100)
                            .shimmer()
                    }
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(dynamicSuggestions.prefix(4)) { suggestion in
                        ModernSuggestionCard(
                            title: suggestion.text,
                            icon: suggestion.icon,
                            gradient: getGradientForCategory(suggestion.category)
                        ) {
                            viewModel.inputText = suggestion.action
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userData) { _, _ in
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userMemory?.id ?? "") { _, _ in
            loadDynamicSuggestions()
        }
    }

    private func loadDynamicSuggestions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isLoadingSuggestions = true
        NovaSuggestionService.shared.generateDynamicSuggestions(
            userId: userId,
            userMemory: viewModel.userMemory,
            userData: viewModel.userData
        ) { suggestions in
            Task { @MainActor in
                self.dynamicSuggestions = suggestions
                self.isLoadingSuggestions = false
            }
        }
    }

    private func getGradientForCategory(_ category: DynamicSuggestion.SuggestionCategory) -> [Color] {
        switch category {
        case .activity:
            return [ModernGeminiColors.primary, ModernGeminiColors.secondary]
        case .celebration:
            return [Color(hex: "FFD700"), Color(hex: "FFA500")]
        case .personalized:
            return [ModernGeminiColors.accent, ModernGeminiColors.primary]
        case .temporal:
            return [ModernGeminiColors.secondary, ModernGeminiColors.accent]
        case .general:
            return [ModernGeminiColors.primary, ModernGeminiColors.accent]
        }
    }
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
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
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
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .frame(width: style == .hero ? 28 : 14)

                Text(suggestion.text)
                    .font(.custom(style == .hero ? "Poppins-SemiBold" : "Poppins-Medium", size: style == .hero ? 15 : 14))
                    .foregroundColor(ModernGeminiColors.textPrimary)

                if style == .hero {
                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, style == .hero ? 16 : 10)
            .frame(maxWidth: style == .hero ? .infinity : nil, alignment: .leading)
            .background {
                if style == .hero {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(ModernGeminiColors.materialBackground)
                } else {
                    Color.clear
                        .liquidGlass(in: Capsule(), interactive: true)
                }
            }
            .overlay {
                if style == .hero {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Utilities y Extensions
struct GeminiScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
