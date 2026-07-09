import SwiftUI
import UIKit

// MARK: - Vista Principal
struct NovaView: View {
    @ObservedObject private var accessCoordinator = ChatAccessCoordinator.shared

    var body: some View {
        Group {
            if accessCoordinator.accessState == .available {
                NovaSecureContent()
            } else {
                ChatRecoveryGateView(onCancel: nil) {
                    NovaSecureContent()
                }
            }
        }
        .task {
            _ = await accessCoordinator.ensureAccess()
        }
    }
}

private struct NovaSecureContent: View {
    @StateObject private var viewModel = NovaAgent()
    @State private var scrollOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var showConversationHistory = false
    @State private var isKeyboardVisible = false
    @State private var isShowingMemory = false
    @State private var memorySheetDetent: PresentationDetent = .medium
    @State private var activeAttachmentSheet: NovaAttachmentSheetKind?
    @State private var plusButtonAnchorFrame: CGRect = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            novaRootContent(in: geometry)
        }
        .navigationBarHidden(true)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            isKeyboardVisible = false
        }
        .onChange(of: activeAttachmentSheet) { _, newValue in
            guard newValue != nil else { return }
            hideKeyboard()
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

    @ViewBuilder
    private func novaConversationLayer(
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        let topOverlayHeight: CGFloat = 132
        let bottomOverlayHeight: CGFloat = 88
        let topFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
        let bottomFadeBase = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
        let tabBarFadeOffset: CGFloat = 92

        ZStack {
            if viewModel.userData != nil && !viewModel.isLoading && viewModel.conversationHistory.isEmpty && viewModel.showSuggestedOptions {
                ModernWelcomeSection(
                    viewModel: viewModel,
                    showSuggestedOptions: $viewModel.showSuggestedOptions
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
        .overlay(alignment: .top) {
            novaTopFadeGradient(base: topFadeBase, safeAreaTop: safeAreaTop)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                NovaHeader(
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
            novaBottomFadeGradient(
                base: bottomFadeBase,
                safeAreaBottom: safeAreaBottom,
                tabBarFadeOffset: tabBarFadeOffset
            )
        }
        .overlay(alignment: .bottom) {
            novaInputBarOverlay(safeAreaBottom: safeAreaBottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardHeight)
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
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(NovaScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
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
                    proxy.scrollTo("\(lastMessage.id)_\(lastMessage.isHistorical ? "historical" : "new")", anchor: .bottom)
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
                .id("\(message.id)_\(message.isHistorical ? "historical" : "new")")
            }

            if viewModel.isLoading && viewModel.pendingAction == nil {
                ModernLoadingAnimation(statusLabel: viewModel.activeToolDisplayName)
                    .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topOverlayHeight)
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + bottomOverlayHeight : bottomOverlayHeight + safeAreaBottom)
        .background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: NovaScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
            }
        }
        .onChange(of: viewModel.conversationHistory) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToBottom()
            }
        }
        .onChange(of: keyboardHeight) { _, height in
            if height > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToBottom()
                }
            }
        }
        .onChange(of: isKeyboardVisible) { _, visible in
            if visible && !viewModel.conversationHistory.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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
        .opacity(keyboardHeight > 0 ? 0 : 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func novaInputBarOverlay(safeAreaBottom: CGFloat) -> some View {
        EnhancedInputBar(
            viewModel: viewModel,
            showSuggestedOptions: $viewModel.showSuggestedOptions,
            activeAttachmentSheet: $activeAttachmentSheet,
            onFocusChange: { focused in
                if focused && !viewModel.conversationHistory.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {}
                }
            }
        )
        .onPreferenceChange(NovaPlusButtonAnchorKey.self) { frame in
            plusButtonAnchorFrame = frame
        }
        .padding(.bottom, NovaInputBarLayout.bottomPadding(
            keyboardHeight: keyboardHeight,
            safeAreaBottom: safeAreaBottom
        ))
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
        NavigationView {
            NovaView()
        }
        .preferredColorScheme(.dark)
    }
}
