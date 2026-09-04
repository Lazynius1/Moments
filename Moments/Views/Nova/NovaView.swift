import SwiftUI
import UIKit

// MARK: - Vista Principal
struct NovaView: View {
    var body: some View {
        ChatRecoveryGateView(onCancel: nil) {
            NovaSecureContent()
        }
        .momentsFloatingTabBarHidden()
    }
}

private struct NovaSecureContent: View {
    @StateObject private var viewModel = NovaAgent()
    @StateObject private var keyboardScrollCoordinator = ChatKeyboardScrollCoordinator()
    @State private var showConversationHistory = false
    @State private var isShowingMemory = false
    @State private var memorySheetDetent: PresentationDetent = .medium
    @State private var activeAttachmentSheet: NovaAttachmentSheetKind?
    @State private var plusButtonAnchorFrame: CGRect = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var isShowingWelcome: Bool {
        viewModel.userData != nil
            && !viewModel.isLoading
            && viewModel.conversationHistory.isEmpty
            && viewModel.showSuggestedOptions
    }

    var body: some View {
        GeometryReader { geometry in
            novaRootContent(in: geometry)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.fetchUserData()
        }
        .onDisappear {
            Task { await viewModel.finalizeOnExit() }
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: showConversationHistory), value: showConversationHistory)
    }

    @ViewBuilder
    private func novaRootContent(in geometry: GeometryProxy) -> some View {
        let safeAreaTop = geometry.safeAreaInsets.top
        let safeAreaBottom = geometry.safeAreaInsets.bottom

        ZStack {
            NovaBackground()
                .ignoresSafeArea()

            novaConversationLayer(
                safeAreaTop: safeAreaTop,
                safeAreaBottom: safeAreaBottom
            )

            novaFloatingOverlays()
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.sheet, value: activeAttachmentSheet), value: activeAttachmentSheet)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: viewModel.pendingAction?.id)
        .onTapGesture {
            if viewModel.pendingAction == nil {
                hideKeyboard()
            }
        }
        .onChange(of: activeAttachmentSheet) { _, newValue in
            guard newValue != nil else { return }
            hideKeyboard()
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

    @ViewBuilder
    private func novaConversationLayer(
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        let topOverlayHeight: CGFloat = 92
        let bottomOverlayHeight: CGFloat = 108
        let topFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
        let bottomFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
        let tabBarFadeOffset: CGFloat = 92

        ZStack {
            if isShowingWelcome {
                ModernWelcomeSection(
                    viewModel: viewModel,
                    showSuggestedOptions: $viewModel.showSuggestedOptions,
                    onOpenMemory: { isShowingMemory = true }
                )
                .transition(MotionPolicy.Transition.enterPop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                novaConversationScrollView(
                    topOverlayHeight: topOverlayHeight,
                    bottomOverlayHeight: bottomOverlayHeight,
                    safeAreaBottom: safeAreaBottom
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Igual que `mainChatStack`: primero extendemos el host hasta el borde
        // físico y después anclamos fades y compositor sobre ese espacio.
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .top) {
            novaTopFadeGradient(base: topFadeBase, safeAreaTop: safeAreaTop)
        }
        .overlay(alignment: .top) {
            NovaHeader(
                viewModel: viewModel,
                showConversationHistory: $showConversationHistory,
                showSuggestedOptions: $viewModel.showSuggestedOptions,
                isShowingMemory: $isShowingMemory
            )
            .padding(.top, 2)
        }
        .overlay(alignment: .bottom) {
            novaBottomFadeGradient(
                base: bottomFadeBase,
                safeAreaBottom: safeAreaBottom,
                tabBarFadeOffset: tabBarFadeOffset
            )
        }
        .overlay(alignment: .bottom) {
            novaInputBarOverlay()
        }
    }

    @ViewBuilder
    private func novaConversationScrollView(
        topOverlayHeight: CGFloat,
        bottomOverlayHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        ScrollView {
            ScrollViewReader { proxy in
                novaMessageList(
                    proxy: proxy,
                    topOverlayHeight: topOverlayHeight,
                    bottomOverlayHeight: bottomOverlayHeight,
                    safeAreaBottom: safeAreaBottom
                )
            }
        }
        .scrollClipDisabled(false)
    }

    private var lastAssistantMessageId: UUID? {
        viewModel.conversationHistory.last(where: { !$0.isUser && !$0.isSystem })?.id
    }

    private var lastUserMessageId: UUID? {
        viewModel.conversationHistory.last(where: \.isUser)?.id
    }

    @ViewBuilder
    private func novaMessageList(
        proxy: ScrollViewProxy,
        topOverlayHeight: CGFloat,
        bottomOverlayHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        let scrollToBottom = {
            if let lastMessage = viewModel.conversationHistory.last {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }

        LazyVStack(spacing: 16, pinnedViews: []) {
            ForEach(viewModel.conversationHistory) { message in
                EnhancedChatBubble(
                    message: message,
                    username: viewModel.userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name"),
                    onRegenerate: (viewModel.canRetouchLastExchange && message.id == lastAssistantMessageId)
                        ? { viewModel.regenerateLastResponse() } : nil,
                    onEdit: (viewModel.canRetouchLastExchange && message.id == lastUserMessageId)
                        ? { viewModel.beginEditingLastUserMessage() } : nil
                )
                .id(message.id)
            }

            if viewModel.isLoading && viewModel.pendingAction == nil {
                ModernLoadingAnimation(statusLabel: viewModel.activeToolDisplayName)
                    .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topOverlayHeight)
        .padding(
            .bottom,
            bottomOverlayHeight + (keyboardScrollCoordinator.isVisible ? 0 : safeAreaBottom)
        )
        
        .onChange(of: viewModel.conversationHistory.count) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToBottom()
            }
        }
        .onChange(of: keyboardScrollCoordinator.isVisible) { _, visible in
            if visible && !viewModel.conversationHistory.isEmpty {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + keyboardScrollCoordinator.animationDuration + 0.05
                ) {
                    scrollToBottom()
                }
            }
        }
        .onAppear {
            if !viewModel.conversationHistory.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToBottom()
                }
            }
        }
    }

    @ViewBuilder
    private func novaTopFadeGradient(base: Color, safeAreaTop: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: base.opacity(colorScheme == .dark ? 1.0 : 0.98), location: 0.0),
                .init(color: base.opacity(colorScheme == .dark ? 0.96 : 0.9), location: 0.28),
                .init(color: base.opacity(colorScheme == .dark ? 0.58 : 0.42), location: 0.64),
                .init(color: base.opacity(colorScheme == .dark ? 0.14 : 0.08), location: 0.88),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: safeAreaTop + 38)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func novaBottomFadeGradient(
        base: Color,
        safeAreaBottom: CGFloat,
        tabBarFadeOffset: CGFloat
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: Color.clear, location: 0.0),
                .init(color: base.opacity(colorScheme == .dark ? 0.14 : 0.08), location: 0.12),
                .init(color: base.opacity(colorScheme == .dark ? 0.58 : 0.42), location: 0.36),
                .init(color: base.opacity(colorScheme == .dark ? 0.96 : 0.9), location: 0.72),
                .init(color: base.opacity(colorScheme == .dark ? 1.0 : 0.98), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: safeAreaBottom + 46)
        .ignoresSafeArea(edges: .bottom)
        .offset(y: tabBarFadeOffset)
        .opacity(keyboardScrollCoordinator.isVisible ? 0 : 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func novaInputBarOverlay() -> some View {
        VStack(spacing: 4) {
            Text("nova.ai.disclaimer")
                .font(.system(size: legacyPoppinsSize(10)))
                .foregroundStyle(NovaColors.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)

            EnhancedInputBar(
                viewModel: viewModel,
                showSuggestedOptions: $viewModel.showSuggestedOptions,
                activeAttachmentSheet: $activeAttachmentSheet,
                isKeyboardVisible: keyboardScrollCoordinator.isVisible,
                onFocusChange: { focused in
                    if focused && !viewModel.conversationHistory.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {}
                    }
                }
            )
        }
        .onPreferenceChange(NovaPlusButtonAnchorKey.self) { frame in
            plusButtonAnchorFrame = frame
        }
        .padding(
            .bottom,
            NovaInputBarLayout.bottomPadding(
                keyboardVisible: keyboardScrollCoordinator.isVisible
            )
        )
    }

    @ViewBuilder
    private func novaFloatingOverlays() -> some View {
        if showConversationHistory {
            ConversationHistoryOverlay(
                viewModel: viewModel,
                showConversationHistory: $showConversationHistory,
                showSuggestedOptions: $viewModel.showSuggestedOptions
            )
            .transition(.move(edge: .bottom))
            .zIndex(2)
        }

        if viewModel.showCelebration {
            ConfettiView()
                .zIndex(3)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation {
                            viewModel.showCelebration = false
                        }
                    }
                }
        }

        if let action = viewModel.pendingAction {
            NovaActionConfirmationOverlay(
                action: action,
                onConfirm: { viewModel.confirmPendingAction() },
                onCancel: { viewModel.cancelPendingAction() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .zIndex(50)
        }

        if activeAttachmentSheet == .menu {
            NovaAttachmentMenuPopover(
                isPresented: $activeAttachmentSheet,
                anchorFrame: plusButtonAnchorFrame
            )
            .transition(.opacity)
            .zIndex(44)
        }

        NovaAttachmentSheetOverlay(
            activeSheet: $activeAttachmentSheet,
            onCaptured: { image in
                viewModel.selectedImage = image
                activeAttachmentSheet = nil
            },
            onAdd: { image in
                viewModel.selectedImage = image
                activeAttachmentSheet = nil
            }
        )
    }
}

struct NovaView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NovaView()
        }
        .preferredColorScheme(.dark)
    }
}
