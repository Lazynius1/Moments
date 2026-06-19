import SwiftUI

// MARK: - Selection + frame tracking

struct ChatMessageMenuSelection: Equatable {
    let rowId: String
    let message: EnhancedMessage
    let rowFrame: CGRect
    var clusterMessages: [EnhancedMessage]? = nil

    static func == (lhs: ChatMessageMenuSelection, rhs: ChatMessageMenuSelection) -> Bool {
        lhs.rowId == rhs.rowId
    }
}

struct ChatMessageRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Overlay (mismo patrón que ConversationContextMenuOverlay)

struct ChatMessageContextMenuOverlay: View {
    @Binding var selection: ChatMessageMenuSelection?

    let containerSize: CGSize
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

    private let menuRowHeight: CGFloat = 44
    private let menuCornerRadius: CGFloat = ChatAttachmentSheetMetrics.cornerRadius
    private let rowCornerRadius: CGFloat = 16
    private let stackGap: CGFloat = 10
    private let reactionsBarHeight: CGFloat = 54
    private let horizontalInset: CGFloat = 16

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
                dimLayer(cutout: selection.rowFrame)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }
                    .transition(.opacity)

                reactionsBar(for: selection.message)
                    .fixedSize()
                    .position(reactionsPosition(for: selection.rowFrame))
                    .transition(.opacity)

                actionsMenu(for: selection.message, isCurrentUser: selection.message.senderId == currentUserId)
                    .fixedSize(horizontal: true, vertical: true)
                    .position(menuPosition(for: selection.rowFrame, rowCount: visibleMenuRowsCount(for: selection.message, isCurrentUser: selection.message.senderId == currentUserId)))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selection?.rowId)
    }

    @ViewBuilder
    private func dimLayer(cutout: CGRect) -> some View {
        let scaledCutout = scaledRowFrame(for: cutout)
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.50 : 0.32))

            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .frame(width: scaledCutout.width, height: scaledCutout.height)
                .position(x: scaledCutout.midX, y: scaledCutout.midY)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    @ViewBuilder
    private func reactionsBar(for message: EnhancedMessage) -> some View {
        HStack(spacing: 14) {
            ForEach(emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.chat), id: \.self) { emoji in
                Button {
                    HapticManager.shared.mediumImpact()
                    dismissMenu()
                    onReaction(message, emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 30))
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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

                menuDivider

                if ChatMessagePolicy.canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.forward", icon: "arrowshape.turn.up.right", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onForward(message)
                    }
                    menuDivider
                }

                let isStarred = message.isStarred(by: currentUserId)
                ChatContextMenuRow(
                    title: isStarred ? "chat.action.unstar" : "chat.action.star",
                    icon: isStarred ? "star.slash" : "star",
                    primaryTextColor: primaryTextColor
                ) {
                    dismissMenu()
                    onToggleStar(message)
                }

                menuDivider

                if ChatMessagePolicy.canEdit(message, userId: currentUserId) {
                    ChatContextMenuRow(title: "chat.action.edit", icon: "pencil", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onEdit(message)
                    }
                    menuDivider
                }

                if ChatMessagePolicy.canCopy(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) {
                    ChatContextMenuRow(title: "chat.action.copy", icon: "doc.on.doc", primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onCopy(message)
                    }
                    menuDivider
                }

                ChatContextMenuRow(title: "chat.action.deleteForMe", icon: "trash", isDestructive: true, primaryTextColor: primaryTextColor) {
                    dismissMenu()
                    onDeleteForMe(message)
                }

                if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) {
                    menuDivider
                    ChatContextMenuRow(title: "chat.action.deleteForEveryone", icon: "trash.fill", isDestructive: true, primaryTextColor: primaryTextColor) {
                        dismissMenu()
                        onDeleteForEveryone(message)
                    }
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .momentsChromeGlass(in: menuCardShape, interactive: true)
        .clipShape(menuCardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    private var menuDivider: some View {
        Divider()
            .overlay(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07))
            .padding(.horizontal, 12)
    }

    private func scaledRowFrame(for rowFrame: CGRect) -> CGRect {
        let scale: CGFloat = 0.92
        let widthDiff = rowFrame.width * (1 - scale)
        let heightDiff = rowFrame.height * (1 - scale)
        return CGRect(
            x: rowFrame.minX + widthDiff / 2,
            y: rowFrame.minY + heightDiff / 2,
            width: rowFrame.width * scale,
            height: rowFrame.height * scale
        )
    }

    private func reactionsPosition(for rowFrame: CGRect) -> CGPoint {
        let scaled = scaledRowFrame(for: rowFrame)
        return CGPoint(
            x: scaled.midX,
            y: scaled.minY - stackGap - reactionsBarHeight / 2
        )
    }

    private func menuPosition(for rowFrame: CGRect, rowCount: Int) -> CGPoint {
        let scaled = scaledRowFrame(for: rowFrame)
        let menuHeight = menuPanelHeight(rowCount: rowCount)
        let placesBelow = shouldPlaceMenuBelow(rowFrame: rowFrame, menuHeight: menuHeight)

        if placesBelow {
            return CGPoint(
                x: clampedMenuCenterX(for: scaled, menuWidth: 240),
                y: scaled.maxY + stackGap + menuHeight / 2
            )
        }

        let proposedY = scaled.minY - stackGap - reactionsBarHeight - stackGap - menuHeight / 2
        let minY = safeAreaInsets.top + menuHeight / 2 + 8
        return CGPoint(
            x: clampedMenuCenterX(for: scaled, menuWidth: 240),
            y: max(minY, proposedY)
        )
    }

    private func clampedMenuCenterX(for scaledFrame: CGRect, menuWidth: CGFloat) -> CGFloat {
        let margin = horizontalInset
        let half = menuWidth / 2
        let minX = margin + half
        let maxX = containerSize.width - margin - half
        return min(max(scaledFrame.midX, minX), maxX)
    }

    private func menuPanelHeight(rowCount: Int) -> CGFloat {
        CGFloat(rowCount) * menuRowHeight + 20
    }

    private func shouldPlaceMenuBelow(rowFrame: CGRect, menuHeight: CGFloat) -> Bool {
        let scaled = scaledRowFrame(for: rowFrame)
        let spaceBelow = containerSize.height - safeAreaInsets.bottom - 12 - scaled.maxY
        let spaceAbove = scaled.minY - safeAreaInsets.top - 12 - reactionsBarHeight - stackGap
        let required = menuHeight + stackGap

        if spaceBelow >= required { return true }
        if spaceAbove >= required { return false }
        return spaceBelow >= spaceAbove
    }

    private func visibleMenuRowsCount(for message: EnhancedMessage, isCurrentUser: Bool) -> Int {
        guard !message.isDeleted else { return 0 }
        var count = 2 // reply + delete for me
        if ChatMessagePolicy.canForward(message, currentUserId: currentUserId, forwardingPreferences: forwardingPreferences) { count += 1 }
        count += 1 // star / unstar
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
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            HStack {
                Text(title)
                    .font(.custom("Poppins-Medium", size: 17))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18))
            }
            .foregroundColor(isDestructive ? .red : primaryTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.custom("Poppins-Regular", size: 16))
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
