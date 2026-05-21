import SwiftUI
import UIKit

// MARK: - Vista Principal
struct GeminiView: View {
    @StateObject private var viewModel = GeminiViewModel()
    @State private var scrollOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var showConversationHistory = false
    @State private var isKeyboardVisible = false
    @State private var showLanguageSheet = false
    @State private var isShowingMemory = false
    @State private var memorySheetDetent: PresentationDetent = .medium
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            let showsFollowUpSuggestions =
                viewModel.showSuggestedOptions &&
                !viewModel.conversationHistory.isEmpty &&
                !viewModel.followUpSuggestions.isEmpty
            let topOverlayHeight: CGFloat = 132
            let bottomOverlayHeight: CGFloat = showsFollowUpSuggestions ? 128 : 88
            let topFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
            let bottomFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
            let tabBarFadeOffset: CGFloat = 92

            ZStack {
                // Fondo moderno con gradiente
                ModernGeminiBackground()
                    .ignoresSafeArea()

                ZStack {
                    if viewModel.userData != nil && !viewModel.isLoading && viewModel.conversationHistory.isEmpty && viewModel.showSuggestedOptions {
                        ModernWelcomeSection(
                            viewModel: viewModel,
                            showSuggestedOptions: $viewModel.showSuggestedOptions
                        )
                        .transition(.opacity.combined(with: .scale))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            ScrollViewReader { proxy in
                                // ✅ FUNCIÓN HELPER PARA SCROLL SUAVE
                                let scrollToBottom = {
                                    if let lastMessage = viewModel.conversationHistory.last {
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            proxy.scrollTo("\(lastMessage.id)_\(lastMessage.isHistorical ? "historical" : "new")", anchor: .bottom)
                                        }
                                    }
                                }
                                LazyVStack(spacing: 16, pinnedViews: []) {
                                    ForEach(viewModel.conversationHistory) { message in
                                        EnhancedChatBubble(
                                            message: message,
                                            username: viewModel.userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
                                        )
                                        .id("\(message.id)_\(message.isHistorical ? "historical" : "new")")
                                    }

                                    if viewModel.isLoading {
                                        ModernLoadingAnimation()
                                            .padding(.vertical, 20)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, topOverlayHeight)
                                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + bottomOverlayHeight : bottomOverlayHeight + safeAreaBottom)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(key: GeminiScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                                    }
                                )
                                // ✅ CAMBIO 1: Scroll cuando CAMBIAN los mensajes - MEJORADO
                                .onChange(of: viewModel.conversationHistory) { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        scrollToBottom()
                                    }
                                }
                                // ✅ CAMBIO 2: Scroll cuando aparece el teclado - MEJORADO
                                .onChange(of: keyboardHeight) { height in
                                    if height > 0 {
                                        // ✅ DELAY MÁS LARGO PARA SINCRONIZAR CON EL TECLADO
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            scrollToBottom()
                                        }
                                    }
                                }
                                // ✅ NUEVO: Scroll cuando el teclado está visible y hay foco
                                .onChange(of: isKeyboardVisible) { visible in
                                    if visible && !viewModel.conversationHistory.isEmpty {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                            scrollToBottom()
                                        }
                                    }
                                }
                                // ✅ CAMBIO 3: Scroll inicial cuando se cargan mensajes históricos - MEJORADO
                                .onAppear {
                                    if !viewModel.conversationHistory.isEmpty {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            scrollToBottom()
                                        }
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(GeminiScrollOffsetPreferenceKey.self) { value in
                            scrollOffset = value
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    LinearGradient(
                        stops: [
                            .init(color: topFadeBase.opacity(colorScheme == .dark ? 1.0 : 0.98), location: 0.0),
                            .init(color: topFadeBase.opacity(colorScheme == .dark ? 0.96 : 0.9), location: 0.28),
                            .init(color: topFadeBase.opacity(colorScheme == .dark ? 0.58 : 0.42), location: 0.64),
                            .init(color: topFadeBase.opacity(colorScheme == .dark ? 0.14 : 0.08), location: 0.88),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: safeAreaTop + 38)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        EnhancedGeminiHeader(
                            viewModel: viewModel,
                            showConversationHistory: $showConversationHistory,
                            showSuggestedOptions: $viewModel.showSuggestedOptions,
                            isShowingMemory: $isShowingMemory
                        )

                        NovaEncryptionBadge()
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 2)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: bottomFadeBase.opacity(colorScheme == .dark ? 0.14 : 0.08), location: 0.12),
                            .init(color: bottomFadeBase.opacity(colorScheme == .dark ? 0.58 : 0.42), location: 0.36),
                            .init(color: bottomFadeBase.opacity(colorScheme == .dark ? 0.96 : 0.9), location: 0.72),
                            .init(color: bottomFadeBase.opacity(colorScheme == .dark ? 1.0 : 0.98), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: safeAreaBottom + 46)
                    .ignoresSafeArea(edges: .bottom)
                    .offset(y: tabBarFadeOffset)
                    .opacity(keyboardHeight > 0 ? 0 : 1)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    EnhancedInputBar(
                        viewModel: viewModel,
                        showSuggestedOptions: $viewModel.showSuggestedOptions,
                        onFocusChange: { focused in
                            // ✅ SCROLL CUANDO EL TEXTOFIELD OBTIENE FOCUS
                            if focused && !viewModel.conversationHistory.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    if let lastMessage = viewModel.conversationHistory.last {
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            // El scroll se maneja en el onChange del keyboardHeight
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - safeAreaBottom + 8 : 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardHeight)
                }

                // Overlay de historial de conversaciones
                if showConversationHistory {
                    ConversationHistoryOverlay(
                        viewModel: viewModel,
                        showConversationHistory: $showConversationHistory,
                        showSuggestedOptions: $viewModel.showSuggestedOptions
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
                }

                // 🎉 CONFETI OVERLAY
                if viewModel.showCelebration {
                    ConfettiView()
                        .zIndex(3)
                        .transition(.opacity)
                        .onAppear {
                            // Auto-ocultar después de 4 segundos
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation {
                                    viewModel.showCelebration = false
                                }
                            }
                        }
                }
            }
            .onTapGesture {
                hideKeyboard()
                // ✅ No cambiar showSuggestedOptions aquí. La barra de input la gestiona ahora.
                // showSuggestedOptions = false
            }
            // ⭐ LISTENERS DE TECLADO MEJORADOS
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    // ✅ Ajustar keyboardHeight directamente, la animación se maneja en el .offset
                    keyboardHeight = keyboardFrame.height
                    isKeyboardVisible = true

                    // ✅ SCROLL AUTOMÁTICO CUANDO APARECE EL TECLADO
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMessage = viewModel.conversationHistory.last {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                // Usar ScrollViewReader para hacer scroll
                                // Esto se maneja en el onChange del keyboardHeight
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                // ✅ Ajustar keyboardHeight directamente
                keyboardHeight = 0
                isKeyboardVisible = false
            }
            .sheet(isPresented: $isShowingMemory) {
                NovaMemoryManagementView()
                    .presentationDetents([.medium, .large], selection: $memorySheetDetent)
                    .presentationDragIndicator(.visible)
                    .onDisappear {
                        viewModel.reloadMemoryFromStore()
                    }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.fetchUserData()
            if NovaLanguageService.getPreferredLanguage() == nil {
                showLanguageSheet = true
            }
        }
        // ✅ Mantener solo las animaciones de overlay aquí
        .animation(.easeInOut(duration: 0.3), value: showConversationHistory)
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSelectionSheet { selected in
                NovaLanguageService.setPreferredLanguage(selected)
                showLanguageSheet = false
            }
            .presentationDetents([.fraction(0.35)])
        }
    }
}

// MARK: - Preview (sin cambios)
struct GeminiView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            GeminiView()
        }
        .preferredColorScheme(.dark)
    }
}
