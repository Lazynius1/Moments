import SwiftUI
import UIKit

// MARK: - Selection + frame tracking

struct ChatMessageMenuSelection: Equatable {
    let rowId: String
    let message: EnhancedMessage
    let anchorFrame: CGRect
    let anchorCornerRadius: CGFloat
    let isOutgoing: Bool
    let extractSource: ChatMessageExtractSource
    var clusterMessages: [EnhancedMessage]? = nil

    static func == (lhs: ChatMessageMenuSelection, rhs: ChatMessageMenuSelection) -> Bool {
        lhs.rowId == rhs.rowId
    }
}

struct ChatMessageLiftSnapshot {
    let frame: CGRect
    let cornerRadius: CGFloat
    let extractSource: ChatMessageExtractSource
}

/// Hueco en la celda + la vista viva de la burbuja, para elevar el original sin bitmap.
@MainActor
final class ChatMessageExtractSource {
    fileprivate weak var slotView: ChatExtractSlotView?
    fileprivate var allowsExtract = true

    func windowFrame(fallback: CGRect) -> CGRect {
        guard let slotView, let window = slotView.window, slotView.bounds.width > 0, slotView.bounds.height > 0 else {
            return fallback
        }
        return slotView.convert(slotView.bounds, to: window)
    }

    func prepareForExtract() {
        allowsExtract = true
    }

    fileprivate func take(into overlay: UIView) {
        guard allowsExtract else { return }
        slotView?.take(into: overlay)
    }

    func putBack() {
        allowsExtract = false
        slotView?.putBack()
    }
}

private final class ChatExtractSlotView: UIView {
    var hostedView: UIView?
    private var isExtracted = false
    private var restoredUserInteraction = true

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isExtracted {
            hostedView?.frame = bounds
        }
    }

    func take(into overlay: UIView) {
        guard let hostedView, hostedView.superview !== overlay else { return }
        isExtracted = true
        restoredUserInteraction = hostedView.isUserInteractionEnabled
        hostedView.isUserInteractionEnabled = false
        // Keep the in-list size. Stretching to the overlay reflows text
        // ("hola" → "hol a") because the bubble uses width-driven wrapping.
        let size = hostedView.bounds.size
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = []
        overlay.addSubview(hostedView)
        hostedView.frame = CGRect(origin: .zero, size: size)
    }

    func putBack() {
        guard let hostedView, isExtracted else { return }
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(hostedView)
        hostedView.frame = bounds
        hostedView.isUserInteractionEnabled = restoredUserInteraction
        isExtracted = false
    }
}

private struct ChatExtractableContent<Content: View>: UIViewRepresentable {
    let source: ChatMessageExtractSource
    let content: Content

    init(source: ChatMessageExtractSource, @ViewBuilder content: () -> Content) {
        self.source = source
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeUIView(context: Context) -> ChatExtractSlotView {
        let slot = ChatExtractSlotView()
        slot.backgroundColor = .clear
        slot.isUserInteractionEnabled = true
        let hosted = context.coordinator.hostingController.view!
        hosted.backgroundColor = .clear
        hosted.insetsLayoutMarginsFromSafeArea = false
        hosted.translatesAutoresizingMaskIntoConstraints = true
        hosted.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        slot.hostedView = hosted
        slot.addSubview(hosted)
        hosted.frame = slot.bounds
        source.slotView = slot
        return slot
    }

    func updateUIView(_ slot: ChatExtractSlotView, context: Context) {
        context.coordinator.hostingController.rootView = content
        source.slotView = slot
        if slot.hostedView == nil {
            slot.hostedView = context.coordinator.hostingController.view
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChatExtractSlotView, context: Context) -> CGSize? {
        let screenCap = UIApplication.shared.activeWindowSize.width
            * ChatTextBubbleMetrics.maxWidthScreenFraction
        let target = CGSize(
            width: min(proposal.width ?? screenCap, screenCap),
            height: proposal.height ?? .greatestFiniteMagnitude
        )
        let fitted = context.coordinator.hostingController.sizeThatFits(in: target)
        return CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
    }

    final class Coordinator {
        let hostingController: UIHostingController<Content>

        init(content: Content) {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            host.sizingOptions = [.intrinsicContentSize]
            hostingController = host
        }
    }
}

private struct ChatExtractedLiftView: UIViewRepresentable {
    let source: ChatMessageExtractSource

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source)
    }

    func makeUIView(context: Context) -> ChatExtractOverlayHostView {
        let view = ChatExtractOverlayHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        view.source = source
        return view
    }

    func updateUIView(_ uiView: ChatExtractOverlayHostView, context: Context) {
        context.coordinator.source = source
        uiView.source = source
        if uiView.bounds.width > 0, uiView.bounds.height > 0 {
            source.take(into: uiView)
        }
    }

    static func dismantleUIView(_ uiView: ChatExtractOverlayHostView, coordinator: Coordinator) {
        coordinator.source.putBack()
    }

    final class Coordinator {
        var source: ChatMessageExtractSource
        init(source: ChatMessageExtractSource) {
            self.source = source
        }
    }
}

private final class ChatExtractOverlayHostView: UIView {
    var source: ChatMessageExtractSource?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let source else { return }
        source.take(into: self)
    }
}

enum ChatBubbleAnchorMetrics {
    /// Escala al abrir menú o durante highlight (reacción, jump, reply).
    static let menuSelectionScale: CGFloat = 1.07
    static let highlightScale: CGFloat = 1.03
    static let highlightDuration: TimeInterval = 1.5
    /// Duración del flash al saltar a un mensaje citado (tap en la cita).
    static let replyJumpHighlightDuration: TimeInterval = 0.7
    static let pressScale: CGFloat = 0.97

    static func cornerRadius(for message: EnhancedMessage) -> CGFloat {
        switch message.type {
        case .text:
            return 20
        case .audio:
            return 18
        case .image, .video, .viewOnceImage, .viewOnceVideo, .location, .ephemeral, .sharedMoment, .sharedStory, .sharedProfile:
            return 16
        case .gif, .sticker:
            return 12
        case .file:
            return 14
        default:
            return 16
        }
    }

    static let clusterCornerRadius: CGFloat = 16
}

/// Opacidad del resto del chat mientras el menú está abierto (la burbuja seleccionada queda al 100 %).
enum ChatMenuDimming {
    static let inactiveOpacity: CGFloat = 0.42
}

extension View {
    func chatMenuDimmedUnlessSelected(isSelected: Bool, menuOpen: Bool) -> some View {
        opacity(menuOpen && !isSelected ? ChatMenuDimming.inactiveOpacity : 1)
    }

    func chatMenuDimmedWhenOpen(_ menuOpen: Bool) -> some View {
        opacity(menuOpen ? ChatMenuDimming.inactiveOpacity : 1)
    }
}

// MARK: - Row chrome (layout + outgoing color)

/// Publica color outgoing; sin medición de layout (evita cycling al hacer scroll).
struct ChatMessageRowChrome<Content: View>: View {
    let isOutgoing: Bool
    let colorScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    private var outgoingBubbleColor: Color {
        Color(hex: "3F6F8F")
    }

    var body: some View {
        content()
            .environment(\.chatOutgoingBubbleColor, outgoingBubbleColor)
    }
}

// MARK: - Bubble chrome (escala + long-press)

private struct ChatBubbleGlobalFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ChatMessageBubbleChrome<Content: View>: View {
    let isMenuSelected: Bool
    let isOutgoing: Bool
    let cornerRadius: CGFloat
    let colorScheme: ColorScheme
    var isFlashing: Bool = false
    var onTap: (() -> Void)? = nil
    let onLongPress: ((ChatMessageLiftSnapshot) -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var isPressing = false
    @State private var bubbleFrame: CGRect = .zero
    @State private var extractSource = ChatMessageExtractSource()

    private var selectionScale: CGFloat {
        if isFlashing { return ChatBubbleAnchorMetrics.highlightScale }
        if isPressing { return ChatBubbleAnchorMetrics.pressScale }
        return 1
    }

    private var highlightTintColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.12)
    }

    var body: some View {
        ChatExtractableContent(source: extractSource) {
            content()
                .environment(\.chatMessageBubbleCornerRadius, cornerRadius)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(highlightTintColor)
                        .opacity(isFlashing ? 1 : 0)
                        .allowsHitTesting(false)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isFlashing), value: isFlashing)
                }
                .modifier(ChatBubblePressClassifierModifier(
                    isEnabled: onLongPress != nil || onTap != nil,
                    isPressing: $isPressing,
                    onTap: onTap,
                    onLongPress: {
                        guard let onLongPress else { return }
                        isPressing = false
                        DispatchQueue.main.async {
                            extractSource.prepareForExtract()
                            onLongPress(
                                ChatMessageLiftSnapshot(
                                    frame: extractSource.windowFrame(fallback: bubbleFrame),
                                    cornerRadius: cornerRadius,
                                    extractSource: extractSource
                                )
                            )
                        }
                    }
                ))
        }
        .scaleEffect(
            selectionScale,
            anchor: isOutgoing ? .bottomTrailing : .bottomLeading
        )
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isMenuSelected), value: isMenuSelected)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isFlashing), value: isFlashing)
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .zIndex(isMenuSelected || isFlashing ? 1 : 0)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: ChatBubbleGlobalFramePreference.self,
                        value: geometry.frame(in: .global)
                    )
            }
        }
        .onPreferenceChange(ChatBubbleGlobalFramePreference.self) { newFrame in
            bubbleFrame = newFrame
        }
    }
}

private struct ChatBubblePressClassifierModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isPressing: Bool
    let onTap: (() -> Void)?
    let onLongPress: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.chatMessagePressClassifier(
                isPressing: $isPressing,
                onTap: onTap,
                onLongPress: onLongPress
            )
        } else {
            content
        }
    }
}

// MARK: - Overlay

private struct ChatMessageMenuLayout {
    let messageOffsetY: CGFloat
    let reactionsCenter: CGPoint
    let menuCenter: CGPoint
    let reactionsAreAbove: Bool
}

private struct ChatReactionEmojiFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct ChatSkinToneSelection {
    let baseEmoji: String
    let anchorKey: String
}

struct ChatMessageContextMenuOverlay: View {
    @Binding var selection: ChatMessageMenuSelection?

    let containerSize: CGSize
    /// Origen del `GeometryReader` del overlay en pantalla; `anchorFrame` viene en `.global`.
    let containerFrameInGlobal: CGRect
    let safeAreaInsets: EdgeInsets
    let colorScheme: ColorScheme
    let currentUserId: String
    let forwardingPreferences: [String: Bool]

    let onDeleteForEveryone: (EnhancedMessage) -> Void
    let onDeleteForMe: (EnhancedMessage) -> Void
    let onEdit: (EnhancedMessage) -> Void
    let onReply: (EnhancedMessage) -> Void
    let onCopy: (EnhancedMessage) -> Void
    let onForward: (EnhancedMessage) -> Void
    let onToggleStar: (EnhancedMessage) -> Void
    let onReaction: (EnhancedMessage, String) -> Void
    let onMoreReactions: (EnhancedMessage) -> Void
    var onOpenMessage: ((EnhancedMessage, [EnhancedMessage]?) -> Void)? = nil

    private let menuRowHeight: CGFloat = 36
    private let menuCornerRadius: CGFloat = ChatAttachmentSheetMetrics.cornerRadius
    private let stackGap: CGFloat = 10
    private let reactionsBarHeight: CGFloat = 54
    private let expandedReactionsHeight: CGFloat = 232
    private let horizontalInset: CGFloat = 16

    private let reactionsBarEstimatedWidth: CGFloat = 300
    private let menuEstimatedWidth: CGFloat = 240
    /// Lift extra cuando hay hueco (el mensaje no solo se escala, también se eleva).
    private let extraMessageLift: CGFloat = 18

    @StateObject private var emojiUsageTracker = EmojiUsageTracker()
    @State private var isPresented = false
    @State private var dismissGeneration = 0
    @State private var areReactionsExpanded = false
    @State private var skinToneSelection: ChatSkinToneSelection?
    @State private var reactionEmojiFrames: [String: CGRect] = [:]

    private var primaryTextColor: Color {
        MomentsChromeGlass.contentColor(for: colorScheme)
    }

    private var menuCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
    }

    /// Spring de entrada: viaje + escala con damping alto (~0.42s).
    private var presentationAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.42, dampingFraction: 0.84)
    }

    /// Put-back: easeInOut corto para devolver el mensaje a su sitio sin rebote.
    private var dismissalAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.26)
    }

    var body: some View {
        ZStack {
            if let selection {
                let rowCount = visibleMenuRowsCount(
                    for: selection.message,
                    isCurrentUser: selection.message.senderId == currentUserId
                )
                let layout = menuLayout(for: selection, rowCount: rowCount)
                let anchor = localAnchorFrame(selection.anchorFrame)
                let presentedOffsetY = isPresented ? layout.messageOffsetY : 0
                let restReactionsCenter = CGPoint(
                    x: layout.reactionsCenter.x,
                    y: layout.reactionsCenter.y - layout.messageOffsetY
                )
                let restMenuCenter = CGPoint(
                    x: layout.menuCenter.x,
                    y: layout.menuCenter.y - layout.messageOffsetY
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.32 : 0.18))
                    .opacity(isPresented ? 1 : 0)
                    .ignoresSafeArea()

                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }
                    .accessibilityHidden(true)

                liftedMessage(for: selection)
                    .offset(overlayOffset(for: CGPoint(x: anchor.midX, y: anchor.midY + presentedOffsetY)))
                    .zIndex(1)

                reactionsRail(for: selection, isAboveMessage: layout.reactionsAreAbove)
                    .fixedSize()
                    .offset(overlayOffset(for: isPresented ? layout.reactionsCenter : restReactionsCenter))
                    .scaleEffect(
                        isPresented ? 1 : 0.86,
                        anchor: layout.reactionsAreAbove ? .bottom : .top
                    )
                    .opacity(isPresented ? 1 : 0)
                    .zIndex(3)

                actionsMenu(for: selection.message, isCurrentUser: selection.message.senderId == currentUserId)
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(overlayOffset(for: isPresented ? layout.menuCenter : restMenuCenter))
                    .scaleEffect(
                        isPresented ? 1 : 0.92,
                        anchor: layout.menuCenter.y >= anchor.midY ? .top : .bottom
                    )
                    .opacity(isPresented && !areReactionsExpanded ? 1 : 0)
                    .allowsHitTesting(isPresented && !areReactionsExpanded)
                    .zIndex(2)
            }
        }
        .onChange(of: selection?.rowId) { _, rowId in
            guard rowId != nil else {
                isPresented = false
                return
            }
            dismissGeneration += 1
            isPresented = false
            areReactionsExpanded = false
            skinToneSelection = nil
            DispatchQueue.main.async {
                withAnimation(presentationAnimation) {
                    isPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private func liftedMessage(
        for selection: ChatMessageMenuSelection
    ) -> some View {
        let anchor = localAnchorFrame(selection.anchorFrame)
        ZStack {
            ChatExtractedLiftView(source: selection.extractSource)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    let message = selection.message
                    let cluster = selection.clusterMessages
                    if onOpenMessage != nil {
                        dismissMenu { onOpenMessage?(message, cluster) }
                    } else {
                        dismissMenu()
                    }
                }
        }
        .frame(width: anchor.width, height: anchor.height)
        .scaleEffect(
            isPresented ? ChatBubbleAnchorMetrics.menuSelectionScale : 1,
            anchor: selection.isOutgoing ? .bottomTrailing : .bottomLeading
        )
        .shadow(
            color: .black.opacity(isPresented ? 0.28 : 0),
            radius: isPresented ? 28 : 0,
            x: 0,
            y: isPresented ? 14 : 0
        )
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func reactionsRail(for selection: ChatMessageMenuSelection, isAboveMessage: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.chat), id: \.self) { emoji in
                    reactionButton(
                        emoji,
                        for: selection.message,
                        size: 28,
                        anchorKey: "quick:\(emoji)"
                    )
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                    .rotationEffect(.degrees(areReactionsExpanded ? 180 : 0))
                    .frame(width: 36, height: 36)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: false)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        HapticManager.shared.lightImpact()
                        skinToneSelection = nil
                        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.4, dampingFraction: 0.86)) {
                            areReactionsExpanded.toggle()
                        }
                    }
                    .accessibilityAddTraits(.isButton)
            }
            .frame(height: 46)
            .padding(.horizontal, 10)

            if areReactionsExpanded {
                Divider()
                    .opacity(0.4)
                    .padding(.horizontal, 12)

                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7),
                        spacing: 7
                    ) {
                        ForEach(inlineReactionEmojis, id: \.self) { emoji in
                            reactionButton(
                                emoji,
                                for: selection.message,
                                size: 27,
                                anchorKey: "grid:\(emoji)"
                            )
                                .frame(height: 36)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .frame(height: expandedReactionsHeight - 47)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: areReactionsExpanded ? min(containerSize.width - 24, 350) : nil)
        .momentsChromeGlass(
            in: RoundedRectangle(cornerRadius: 23, style: .continuous),
            interactive: false
        )
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
        .coordinateSpace(name: "chatReactionRail")
        .onPreferenceChange(ChatReactionEmojiFramePreference.self) { frames in
            reactionEmojiFrames = frames
        }
        .overlay(
            alignment: reactionConnectorAlignment(
                isOutgoing: selection.isOutgoing,
                isAboveMessage: isAboveMessage
            )
        ) {
            ChatReactionRailConnector(
                pointsDown: isAboveMessage,
                bendsTrailing: !selection.isOutgoing,
                colorScheme: colorScheme
            )
            .offset(
                x: selection.isOutgoing ? -23 : 23,
                y: isAboveMessage ? 20 : -20
            )
            .allowsHitTesting(false)
        }
        .overlay {
            skinToneOverlay(
                for: selection.message,
                isAboveMessage: isAboveMessage
            )
        }
    }

    private var inlineReactionEmojis: [String] {
        let recent = emojiUsageTracker.recentlyUsed(limit: 12)
        let pickerEmojis = EmojiPickerView.emojiCategories.flatMap { $0.emojis }
        var seen = Set<String>()
        return (recent + EmojiReactionDefaults.chat + pickerEmojis)
            .filter { seen.insert($0).inserted }
    }

    private func reactionButton(
        _ emoji: String,
        for message: EnhancedMessage,
        size: CGFloat,
        anchorKey: String
    ) -> some View {
        Text(emoji)
            .font(.system(size: size))
            .frame(minWidth: 30, minHeight: 34)
            .contentShape(Rectangle())
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatReactionEmojiFramePreference.self,
                        value: [anchorKey: geometry.frame(in: .named("chatReactionRail"))]
                    )
                }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.3, maximumDistance: 18)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            let base = emojiWithoutSkinTone(emoji)
                            if supportsSkinTone(base) {
                                HapticManager.shared.mediumImpact()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    areReactionsExpanded = true
                                    skinToneSelection = ChatSkinToneSelection(
                                        baseEmoji: base,
                                        anchorKey: anchorKey
                                    )
                                }
                            } else {
                                selectReaction(emoji, for: message)
                            }
                        case .second:
                            selectReaction(emoji, for: message)
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectReaction(emoji, for: message) }
    }

    private func selectReaction(_ emoji: String, for message: EnhancedMessage) {
        HapticManager.shared.mediumImpact()
        emojiUsageTracker.increment(emoji)
        skinToneSelection = nil
        dismissMenu { onReaction(message, emoji) }
    }

    @ViewBuilder
    private func skinToneOverlay(for message: EnhancedMessage, isAboveMessage: Bool) -> some View {
        GeometryReader { geometry in
            if let toneSelection = skinToneSelection,
               let anchor = reactionEmojiFrames[toneSelection.anchorKey] {
                let bubbleWidth: CGFloat = 264
                let bubbleHeight: CGFloat = 54
                let halfWidth = bubbleWidth / 2
                let centerX = min(
                    max(anchor.midX, halfWidth + 4),
                    max(halfWidth + 4, geometry.size.width - halfWidth - 4)
                )
                let belowY = anchor.maxY + 8 + bubbleHeight / 2
                let aboveY = anchor.minY - 8 - bubbleHeight / 2
                let preferredY = isAboveMessage ? belowY : aboveY
                let alternateY = isAboveMessage ? aboveY : belowY
                let fitsPreferred = preferredY - bubbleHeight / 2 >= 4
                    && preferredY + bubbleHeight / 2 <= geometry.size.height - 4
                let unclampedY = fitsPreferred ? preferredY : alternateY
                let centerY = min(
                    max(unclampedY, bubbleHeight / 2 + 4),
                    max(bubbleHeight / 2 + 4, geometry.size.height - bubbleHeight / 2 - 4)
                )

                HStack(spacing: 2) {
                    ForEach(skinToneVariants(for: toneSelection.baseEmoji), id: \.self) { variant in
                        Button {
                            selectReaction(variant, for: message)
                        } label: {
                            Text(variant)
                                .font(.system(size: 28))
                                .frame(width: 40, height: 42)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .momentsChromeGlass(
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous),
                    interactive: true
                )
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.18), radius: 18, y: 8)
                .position(x: centerX, y: centerY)
                .transition(.scale(scale: 0.72, anchor: isAboveMessage ? .top : .bottom).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .allowsHitTesting(skinToneSelection != nil)
    }

    private func skinToneVariants(for baseEmoji: String) -> [String] {
        ["", "🏻", "🏼", "🏽", "🏾", "🏿"].map { baseEmoji + $0 }
    }

    private func emojiWithoutSkinTone(_ emoji: String) -> String {
        String(emoji.unicodeScalars.filter { scalar in
            !(0x1F3FB...0x1F3FF).contains(Int(scalar.value))
        })
    }

    private func supportsSkinTone(_ emoji: String) -> Bool {
        guard let value = emoji.unicodeScalars.first.map({ Int($0.value) }) else { return false }
        switch value {
        case 0x1F442...0x1F44F,
             0x1F450,
             0x1F466...0x1F487,
             0x1F48F...0x1F490,
             0x1F645...0x1F64F,
             0x1F6A3,
             0x1F6B4...0x1F6B6,
             0x1F90C, 0x1F90F,
             0x1F918...0x1F91F,
             0x1F926,
             0x1F930...0x1F93E,
             0x1F977,
             0x1F9B5...0x1F9B6,
             0x1F9C1...0x1F9C2,
             0x1F9D1...0x1F9FF,
             0x270A...0x270D:
            return true
        default:
            return false
        }
    }

    private func reactionConnectorAlignment(isOutgoing: Bool, isAboveMessage: Bool) -> Alignment {
        switch (isOutgoing, isAboveMessage) {
        case (true, true): return .bottomTrailing
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .topLeading
        }
    }

    @ViewBuilder
    private func actionsMenu(for message: EnhancedMessage, isCurrentUser: Bool) -> some View {
        VStack(spacing: 0) {
            if !message.isDeleted {
                if showsMessageInfo(for: message, isCurrentUser: isCurrentUser) {
                    messageInfo(for: message)

                    Divider()
                        .opacity(0.55)
                        .padding(.horizontal, 8)
                }

                ChatContextMenuRow(title: "chat.action.reply", icon: "arrowshape.turn.up.left", primaryTextColor: primaryTextColor) {
                    dismissMenu { onReply(message) }
                }

                if ChatMessagePolicy.canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.forward", icon: "arrowshape.turn.up.right", primaryTextColor: primaryTextColor) {
                        dismissMenu { onForward(message) }
                    }
                }

                let isStarred = message.isStarred(by: currentUserId)
                if !ChatMessagePolicy.isVanishRestricted(message) {
                    ChatContextMenuRow(
                        title: isStarred ? "chat.action.unstar" : "chat.action.star",
                        icon: isStarred ? "star.slash" : "star",
                        primaryTextColor: primaryTextColor
                    ) {
                        dismissMenu { onToggleStar(message) }
                    }
                }


                if ChatMessagePolicy.canEdit(message, userId: currentUserId) {
                    ChatContextMenuRow(title: "chat.action.edit", icon: "pencil", primaryTextColor: primaryTextColor) {
                        dismissMenu { onEdit(message) }
                    }
                }

                if ChatMessagePolicy.canCopy(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.copy", icon: "doc.on.doc", primaryTextColor: primaryTextColor) {
                        dismissMenu { onCopy(message) }
                    }
                }


                ChatContextMenuRow(title: "chat.action.deleteForMe", icon: "trash", isDestructive: true, primaryTextColor: primaryTextColor) {
                    dismissMenu { onDeleteForMe(message) }
                }

                if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) {
                    ChatContextMenuRow(title: "chat.action.deleteForEveryone", icon: "trash.fill", isDestructive: true, primaryTextColor: primaryTextColor) {
                        dismissMenu { onDeleteForEveryone(message) }
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .momentsChromeGlass(in: menuCardShape, interactive: true)
        .clipShape(menuCardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    @ViewBuilder
    private func messageInfo(for message: EnhancedMessage) -> some View {
        let receiptTime = readReceiptTime(for: message)
        HStack(spacing: 10) {
            if let receiptTime {
                MessageStatusIcon(status: .read)

                Text("\(MessageStatus.read.displayName) \(receiptTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(primaryTextColor)
            }

            Spacer(minLength: 10)

            if message.editedAt != nil {
                Text("chat.edited")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(primaryTextColor.opacity(0.52))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
    }

    private func readReceiptTime(for message: EnhancedMessage) -> Date? {
        message.readAtBy?
            .filter { $0.key != message.senderId }
            .map(\.value)
            .max()
    }

    private func showsMessageInfo(for message: EnhancedMessage, isCurrentUser: Bool) -> Bool {
        guard isCurrentUser else { return false }
        return readReceiptTime(for: message) != nil
    }

    private func overlayOffset(for point: CGPoint) -> CGSize {
        CGSize(
            width: point.x - containerSize.width / 2,
            height: point.y - containerSize.height / 2
        )
    }

    private func localAnchorFrame(_ globalFrame: CGRect) -> CGRect {
        CGRect(
            x: globalFrame.minX - containerFrameInGlobal.minX,
            y: globalFrame.minY - containerFrameInGlobal.minY,
            width: globalFrame.width,
            height: globalFrame.height
        )
    }

    private func scaledAnchorFrame(for globalAnchorFrame: CGRect) -> CGRect {
        let anchorFrame = localAnchorFrame(globalAnchorFrame)
        let scale = ChatBubbleAnchorMetrics.menuSelectionScale
        let widthDiff = anchorFrame.width * (scale - 1)
        let heightDiff = anchorFrame.height * (scale - 1)
        return CGRect(
            x: anchorFrame.minX - widthDiff / 2,
            y: anchorFrame.minY - heightDiff / 2,
            width: anchorFrame.width * scale,
            height: anchorFrame.height * scale
        )
    }

    private var layoutTopMargin: CGFloat {
        safeAreaInsets.top + 12
    }

    private var layoutBottomMargin: CGFloat {
        safeAreaInsets.bottom + 12
    }

    private func menuLayout(for selection: ChatMessageMenuSelection, rowCount: Int) -> ChatMessageMenuLayout {
        let scaled = scaledAnchorFrame(for: selection.anchorFrame)
        let includesMessageInfo = showsMessageInfo(
            for: selection.message,
            isCurrentUser: selection.message.senderId == currentUserId
        )
        let menuHeight = menuPanelHeight(rowCount: rowCount, includesMessageInfo: includesMessageInfo)
        let reactionPanelHeight = areReactionsExpanded ? expandedReactionsHeight : reactionsBarHeight
        let reactionPanelWidth = areReactionsExpanded
            ? min(containerSize.width - 24, 350)
            : reactionsBarEstimatedWidth
        let centerX = clampedCenterX(scaled.midX, itemWidth: max(reactionPanelWidth, menuEstimatedWidth))

        // Reubica el mensaje elevado para que reacciones + mensaje + acciones
        // formen un bloque visible. El rail queda arriba y las acciones debajo.
        let minimumMessageTop = layoutTopMargin + reactionPanelHeight + stackGap
        let maximumMessageTop = containerSize.height
            - layoutBottomMargin
            - menuHeight
            - stackGap
            - scaled.height
        let targetMessageTop: CGFloat
        if maximumMessageTop >= minimumMessageTop {
            let preferredTop = scaled.minY - extraMessageLift
            targetMessageTop = min(max(preferredTop, minimumMessageTop), maximumMessageTop)
        } else {
            // Menú excepcionalmente alto: prioriza que su inicio quede accesible;
            // el propio panel conserva su clamp dentro del viewport.
            targetMessageTop = minimumMessageTop
        }
        let messageOffsetY = targetMessageTop - scaled.minY
        let shiftedMessage = scaled.offsetBy(dx: 0, dy: messageOffsetY)
        let reactionsCenterY = shiftedMessage.minY - stackGap - reactionPanelHeight / 2
        let menuCenterY = shiftedMessage.maxY + stackGap + menuHeight / 2

        return ChatMessageMenuLayout(
            messageOffsetY: messageOffsetY,
            reactionsCenter: CGPoint(x: centerX, y: reactionsCenterY),
            menuCenter: CGPoint(x: clampedCenterX(scaled.midX, itemWidth: menuEstimatedWidth), y: menuCenterY),
            reactionsAreAbove: true
        )
    }

    private func clampedCenterX(_ centerX: CGFloat, itemWidth: CGFloat) -> CGFloat {
        let half = itemWidth / 2
        let minCenterX = horizontalInset + half
        let maxCenterX = containerSize.width - horizontalInset - half
        guard maxCenterX >= minCenterX else { return containerSize.width / 2 }
        return min(max(centerX, minCenterX), maxCenterX)
    }

    private func menuPanelHeight(rowCount: Int, includesMessageInfo: Bool) -> CGFloat {
        let infoHeight: CGFloat = includesMessageInfo ? 37 : 0
        return CGFloat(rowCount) * menuRowHeight + 16 + infoHeight
    }

    private func visibleMenuRowsCount(for message: EnhancedMessage, isCurrentUser: Bool) -> Int {
        guard !message.isDeleted else { return 0 }
        var count = 2 // Reply, DeleteForMe
        if !ChatMessagePolicy.isVanishRestricted(message) { count += 1 } // Star
        if ChatMessagePolicy.canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) { count += 1 }
        if ChatMessagePolicy.canEdit(message, userId: currentUserId) { count += 1 }
        if ChatMessagePolicy.canCopy(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) { count += 1 }
        if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) { count += 1 }
        return count
    }

    private func isWithinDeleteLimit(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) < 7200
    }

    private func dismissMenu(then action: (() -> Void)? = nil) {
        dismissGeneration += 1
        let generation = dismissGeneration
        withAnimation(dismissalAnimation) {
            isPresented = false
        }

        let delay = UIAccessibility.isReduceMotionEnabled ? 0 : 0.26
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == dismissGeneration else { return }
            selection?.extractSource.putBack()
            selection = nil
            action?()
        }
    }
}

private struct ChatReactionRailConnector: View {
    let pointsDown: Bool
    let bendsTrailing: Bool
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 16, height: 16)
                .position(x: 12, y: pointsDown ? 8 : 20)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 8, height: 8)
                .position(
                    x: bendsTrailing ? 21 : 3,
                    y: pointsDown ? 22 : 6
                )
        }
        .frame(width: 24, height: 28)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 15)
        .accessibilityHidden(true)
    }
}

// MARK: - Menu row

private struct ChatContextMenuRow: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let primaryTextColor: Color
    let action: () -> Void

    var body: some View {
        MomentRowButton(feedback: .menu, action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? .red : primaryTextColor)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
    }
}

struct GlassActionButton: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let adaptiveColors: AdaptiveColors
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var actionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16)))
                Spacer()
            }
            .foregroundStyle(isDestructive ? Color.red : MomentsChromeGlass.contentColor(for: colorScheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .momentsChromeGlass(in: actionShape, interactive: true)
            .clipShape(actionShape)
        }
        .buttonStyle(.plain)
    }
}
