import SwiftUI
import FirebaseAuth

// MARK: - Selection

struct ConversationMenuSelection: Equatable {
    let conversation: Conversation
    let rowFrame: CGRect

    static func == (lhs: ConversationMenuSelection, rhs: ConversationMenuSelection) -> Bool {
        lhs.conversation.id == rhs.conversation.id
    }
}

struct ConversationListInteraction {
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onPressingChanged: (Bool) -> Void
}

// MARK: - Row frame tracking

struct ConversationRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Overlay

struct ConversationContextMenuOverlay: View {
    @Binding var selection: ConversationMenuSelection?

    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let colorScheme: ColorScheme

    let onMarkUnread: (Conversation) -> Void
    let onPin: (Conversation) -> Void
    let onMute: (Conversation) -> Void
    let onArchive: (Conversation) -> Void
    let onUnarchive: (Conversation) -> Void
    let onDelete: (Conversation) -> Void

    private let menuRowHeight: CGFloat = 38
    private let menuCornerRadius: CGFloat = 16
    private let rowCornerRadius: CGFloat = 14
    private let horizontalInset: CGFloat = 16
    private let stackGap: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let selection {
                dimLayer(cutout: selection.rowFrame)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }
                    .accessibilityHidden(true)
                    .transition(.opacity)

                actionsMenu(for: selection.conversation)
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(
                        x: menuLeadingX(for: selection.rowFrame),
                        y: menuTopY(for: selection.rowFrame)
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(
            MotionPolicy.animation(MotionPolicy.Spring.sheet, value: selection?.conversation.id),
            value: selection?.conversation.id
        )
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
    private func actionsMenu(for conversation: Conversation) -> some View {
        VStack(spacing: 0) {
            if conversation.unreadCount == 0 {
                ConversationContextMenuRow(
                    icon: "envelope.badge",
                    title: NSLocalizedString("messaging.menu.markUnread", comment: "Mark conversation unread"),
                    action: {
                        dismissMenu()
                        onMarkUnread(conversation)
                    }
                )
            }

            ConversationContextMenuRow(
                icon: conversation.isPinned == true ? "pin.slash" : "pin",
                title: NSLocalizedString(
                    conversation.isPinned == true ? "messaging.swipe.unpin" : "messaging.swipe.pin",
                    comment: "Pin conversation"
                ),
                action: {
                    dismissMenu()
                    onPin(conversation)
                }
            )

            ConversationContextMenuRow(
                icon: conversation.isMuted == true ? "bell" : "bell.slash",
                title: NSLocalizedString(
                    conversation.isMuted == true ? "messaging.swipe.unmute" : "messaging.swipe.mute",
                    comment: "Mute conversation"
                ),
                action: {
                    dismissMenu()
                    onMute(conversation)
                }
            )

            if conversation.isArchived(for: Auth.auth().currentUser?.uid) {
                ConversationContextMenuRow(
                    icon: "archivebox.fill",
                    title: NSLocalizedString("messaging.menu.unarchive", comment: "Unarchive conversation"),
                    action: {
                        dismissMenu()
                        onUnarchive(conversation)
                    }
                )
            } else {
                ConversationContextMenuRow(
                    icon: "archivebox",
                    title: NSLocalizedString("messaging.menu.archive", comment: "Archive conversation"),
                    action: {
                        dismissMenu()
                        onArchive(conversation)
                    }
                )
            }

            ConversationContextMenuRow(
                icon: "trash",
                title: NSLocalizedString("notifications.delete", comment: "Delete"),
                isDestructive: true,
                action: {
                    dismissMenu()
                    onDelete(conversation)
                }
            )
        }
        .frame(minWidth: 230)
        .fixedSize(horizontal: true, vertical: true)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous))
    }

    private var menuDivider: some View {
        Divider()
            .opacity(colorScheme == .dark ? 0.22 : 0.14)
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

    private var visibleMenuRowsCount: CGFloat {
        guard let conversation = selection?.conversation else { return 4 }
        return conversation.unreadCount == 0 ? 5 : 4
    }

    private var menuPanelHeight: CGFloat {
        menuRowHeight * visibleMenuRowsCount
    }

    private func menuLeadingX(for rowFrame: CGRect) -> CGFloat {
        let scaledFrame = scaledRowFrame(for: rowFrame)
        return scaledFrame.minX + horizontalInset
    }

    private func menuTopY(for rowFrame: CGRect) -> CGFloat {
        let scaledFrame = scaledRowFrame(for: rowFrame)
        let placesBelow = shouldPlaceMenuBelow(rowFrame: rowFrame)

        if placesBelow {
            return scaledFrame.maxY + stackGap
        }

        let proposed = scaledFrame.minY - stackGap - menuPanelHeight
        let minY = safeAreaInsets.top + 8
        return max(minY, proposed)
    }

    private func shouldPlaceMenuBelow(rowFrame: CGRect) -> Bool {
        let scaledFrame = scaledRowFrame(for: rowFrame)
        let spaceBelow = containerSize.height - safeAreaInsets.bottom - 12 - scaledFrame.maxY
        let spaceAbove = scaledFrame.minY - safeAreaInsets.top - 12
        let required = menuPanelHeight + stackGap

        if spaceBelow >= required { return true }
        if spaceAbove >= required { return false }
        return spaceBelow >= spaceAbove
    }

    private func dismissMenu() {
        selection = nil
    }
}

// MARK: - Row highlight (in-place, no clone)

struct ConversationRowMenuHighlight: ViewModifier {
    let isSelected: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? Color(hex: "1C1C1E") : .white)
                }
            }
            .animation(nil, value: isSelected)
    }
}

// MARK: - Menu row

private struct ConversationContextMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    private var textColor: Color {
        if isDestructive { return .red }
        return colorScheme == .dark ? .white : .black
    }

    var body: some View {
        MomentRowButton(feedback: .menu, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(.system(size: legacyPoppinsSize(14.5), weight: .medium))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
    }
}
