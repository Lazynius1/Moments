import SwiftUI

// MARK: - Selection + frame tracking

struct ChatMessageMenuSelection: Equatable {
    let rowId: String
    let message: EnhancedMessage
    let anchorFrame: CGRect
    let anchorCornerRadius: CGFloat
    let isOutgoing: Bool
    var clusterMessages: [EnhancedMessage]? = nil

    static func == (lhs: ChatMessageMenuSelection, rhs: ChatMessageMenuSelection) -> Bool {
        lhs.rowId == rhs.rowId
    }
}

enum ChatBubbleAnchorMetrics {
    /// Escala al abrir menú o durante highlight (reacción, jump, reply).
    static let menuSelectionScale: CGFloat = 1.03
    static let highlightScale: CGFloat = menuSelectionScale
    static let highlightDuration: TimeInterval = 1.5
    static let pressScale: CGFloat = 0.97

    static func cornerRadius(for message: EnhancedMessage) -> CGFloat {
        switch message.type {
        case .text:
            return 20
        case .audio:
            return 18
        case .image, .video, .viewOnceImage, .viewOnceVideo, .location, .ephemeral, .sharedMoment, .sharedStory:
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
    let onLongPress: ((CGRect, CGFloat) -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var isPressing = false
    @State private var bubbleFrame: CGRect = .zero

    private var selectionScale: CGFloat {
        if isMenuSelected || isFlashing { return ChatBubbleAnchorMetrics.highlightScale }
        if isPressing { return ChatBubbleAnchorMetrics.pressScale }
        return 1
    }

    private var highlightTintColor: Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(0.12)
    }

    var body: some View {
        content()
            .environment(\.chatMessageBubbleCornerRadius, cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(highlightTintColor)
                    .opacity(isFlashing ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isFlashing), value: isFlashing)
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
            .modifier(ChatBubbleLongPressModifier(
                isEnabled: onLongPress != nil,
                isPressing: $isPressing,
                onLongPress: {
                    guard let onLongPress else { return }
                    // bubbleFrame (GeometryReader en .global) no resuelve de forma fiable dentro de
                    // una celda UIHostingConfiguration y suele quedar en .zero — se pasa igualmente:
                    // el caller resuelve el frame real vía UIKit (chatListController.frameInWindow)
                    // y usa este valor solo como último fallback si esa consulta fallara.
                    onLongPress(bubbleFrame, cornerRadius)
                }
            ))
    }
}

private struct ChatBubbleLongPressModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isPressing: Bool
    let onLongPress: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.chatMessageLongPress(isPressing: $isPressing, onLongPress: onLongPress)
        } else {
            content
        }
    }
}

// MARK: - Overlay

private struct ChatMessageMenuLayout {
    let reactionsCenter: CGPoint
    let menuCenter: CGPoint
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

    private let menuRowHeight: CGFloat = 36
    private let menuCornerRadius: CGFloat = ChatAttachmentSheetMetrics.cornerRadius
    private let stackGap: CGFloat = 10
    private let reactionsBarHeight: CGFloat = 54
    private let horizontalInset: CGFloat = 16

    private let reactionsBarEstimatedWidth: CGFloat = 300
    private let menuEstimatedWidth: CGFloat = 240

    @StateObject private var emojiUsageTracker = EmojiUsageTracker()

    private var primaryTextColor: Color {
        MomentsChromeGlass.contentColor(for: colorScheme)
    }

    private var menuCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let selection {
                let rowCount = visibleMenuRowsCount(
                    for: selection.message,
                    isCurrentUser: selection.message.senderId == currentUserId
                )
                let layout = menuLayout(for: selection, rowCount: rowCount)

                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }

                reactionsBar(for: selection.message)
                    .fixedSize()
                    .position(layout.reactionsCenter)
                    .transition(.opacity)

                actionsMenu(for: selection.message, isCurrentUser: selection.message.senderId == currentUserId)
                    .fixedSize(horizontal: true, vertical: true)
                    .position(layout.menuCenter)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selection?.rowId)
    }

    @ViewBuilder
    private func reactionsBar(for message: EnhancedMessage) -> some View {
        HStack(spacing: 12) {
            ForEach(emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.chat), id: \.self) { emoji in
                Button {
                    HapticManager.shared.mediumImpact()
                    dismissMenu()
                    onReaction(message, emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
            }

            Button {
                HapticManager.shared.lightImpact()
                let targetMessage = message
                dismissMenu()
                onMoreReactions(targetMessage)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(primaryTextColor)
                    .frame(width: 36, height: 36)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .momentsChromeGlass(in: Capsule(), interactive: true)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    @ViewBuilder
    private func actionsMenu(for message: EnhancedMessage, isCurrentUser: Bool) -> some View {
        VStack(spacing: 0) {
            if !message.isDeleted {
                ChatContextMenuRow(title: "chat.action.reply", icon: "arrowshape.turn.up.left", primaryTextColor: primaryTextColor) {
                    dismissMenu()
                    onReply(message)
                }

                if ChatMessagePolicy.canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.forward", icon: "arrowshape.turn.up.right", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onForward(message)
                    }
                }

                let isStarred = message.isStarred(by: currentUserId)
                if !ChatMessagePolicy.isVanishRestricted(message) {
                    ChatContextMenuRow(
                        title: isStarred ? "chat.action.unstar" : "chat.action.star",
                        icon: isStarred ? "star.slash" : "star",
                        primaryTextColor: primaryTextColor
                    ) {
                        dismissMenu()
                        onToggleStar(message)
                    }
                }


                if ChatMessagePolicy.canEdit(message, userId: currentUserId) {
                    ChatContextMenuRow(title: "chat.action.edit", icon: "pencil", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onEdit(message)
                    }
                }

                if ChatMessagePolicy.canCopy(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.copy", icon: "doc.on.doc", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onCopy(message)
                    }
                }


                ChatContextMenuRow(title: "chat.action.deleteForMe", icon: "trash", isDestructive: true, primaryTextColor: primaryTextColor) {
                    dismissMenu()
                    onDeleteForMe(message)
                }

                if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) {
                    ChatContextMenuRow(title: "chat.action.deleteForEveryone", icon: "trash.fill", isDestructive: true, primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onDeleteForEveryone(message)
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
        let menuHeight = menuPanelHeight(rowCount: rowCount)
        let centerX = clampedCenterX(scaled.midX, itemWidth: max(reactionsBarEstimatedWidth, menuEstimatedWidth))

        let spaceAbove = scaled.minY - layoutTopMargin
        let spaceBelow = containerSize.height - layoutBottomMargin - scaled.maxY

        let reactionsAbove = spaceAbove >= reactionsBarHeight + stackGap
        let reactionsBelow = !reactionsAbove && spaceBelow >= reactionsBarHeight + stackGap

        let reactionsCenterY: CGFloat
        if reactionsAbove {
            reactionsCenterY = max(
                layoutTopMargin + reactionsBarHeight / 2,
                scaled.minY - stackGap - reactionsBarHeight / 2
            )
        } else if reactionsBelow {
            reactionsCenterY = min(
                containerSize.height - layoutBottomMargin - reactionsBarHeight / 2,
                scaled.maxY + stackGap + reactionsBarHeight / 2
            )
        } else {
            reactionsCenterY = min(
                containerSize.height - layoutBottomMargin - reactionsBarHeight / 2,
                scaled.maxY + stackGap + reactionsBarHeight / 2
            )
        }

        let menuBelowPreferred = spaceBelow >= menuHeight + stackGap + (reactionsBelow ? reactionsBarHeight + stackGap : 0)
        let menuAbovePreferred = spaceAbove >= menuHeight + stackGap + (reactionsAbove ? reactionsBarHeight + stackGap : 0)
        let menuBelow: Bool
        if menuBelowPreferred { menuBelow = true }
        else if menuAbovePreferred { menuBelow = false }
        else { menuBelow = spaceBelow >= spaceAbove }

        let menuCenterY: CGFloat
        if menuBelow {
            var anchorMaxY = scaled.maxY
            if reactionsBelow {
                anchorMaxY += stackGap + reactionsBarHeight
            }
            menuCenterY = min(
                containerSize.height - layoutBottomMargin - menuHeight / 2,
                anchorMaxY + stackGap + menuHeight / 2
            )
        } else {
            var anchorMinY = scaled.minY
            if reactionsAbove {
                anchorMinY -= stackGap + reactionsBarHeight
            }
            menuCenterY = max(
                layoutTopMargin + menuHeight / 2,
                anchorMinY - stackGap - menuHeight / 2
            )
        }

        return ChatMessageMenuLayout(
            reactionsCenter: CGPoint(x: centerX, y: reactionsCenterY),
            menuCenter: CGPoint(x: clampedCenterX(scaled.midX, itemWidth: menuEstimatedWidth), y: menuCenterY)
        )
    }

    private func clampedCenterX(_ centerX: CGFloat, itemWidth: CGFloat) -> CGFloat {
        let half = itemWidth / 2
        let minCenterX = horizontalInset + half
        let maxCenterX = containerSize.width - horizontalInset - half
        guard maxCenterX >= minCenterX else { return containerSize.width / 2 }
        return min(max(centerX, minCenterX), maxCenterX)
    }

    private func menuPanelHeight(rowCount: Int) -> CGFloat {
        CGFloat(rowCount) * menuRowHeight + 16
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

    private func dismissMenu() {
        selection = nil
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
        MomentRowButton(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 16))
            }
            .foregroundColor(isDestructive ? .red : primaryTextColor)
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
            .foregroundColor(isDestructive ? Color.red : MomentsChromeGlass.contentColor(for: colorScheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .momentsChromeGlass(in: actionShape, interactive: true)
            .clipShape(actionShape)
        }
        .buttonStyle(.plain)
    }
}
