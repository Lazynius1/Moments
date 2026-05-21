import SwiftUI
import UIKit

// MARK: - Premium Unified Message Options Menu
struct GlassmorphicMessageOptionsMenu: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onDeleteForEveryone: () -> Void
    let onDeleteForMe: () -> Void
    let onEdit: () -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onReaction: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var animateIn = false

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    let reactionEmojis = ["❤️", "😂", "😮", "😢", "😡", "👍"]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(animateIn ? 1 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    handleDismiss()
                }

            VStack(spacing: 20) {
                HStack(spacing: 15) {
                    ForEach(reactionEmojis, id: \.self) { emoji in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onReaction(emoji)
                        }) {
                            Text(emoji)
                                .font(.system(size: 30))
                                .scaleEffect(animateIn ? 1.0 : 0.5)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(adaptiveColors.messageBubbleBackground)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                )
                .overlay(
                    Capsule()
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                )
                .scaleEffect(animateIn ? 1.0 : 0.8)
                .opacity(animateIn ? 1 : 0)

                VStack(spacing: 1) {
                    if !message.isDeleted {
                        MenuRow(title: "chat.action.reply", icon: "arrowshape.turn.up.left", adaptiveColors: adaptiveColors) {
                            onReply()
                        }

                        Divider().background(adaptiveColors.messageBubbleStroke)

                        if isCurrentUser && message.type == .text {
                            MenuRow(title: "chat.action.edit", icon: "pencil", adaptiveColors: adaptiveColors) {
                                onEdit()
                            }
                            Divider().background(adaptiveColors.messageBubbleStroke)
                        }

                        if message.type == .text {
                            MenuRow(title: "chat.action.copy", icon: "doc.on.doc", adaptiveColors: adaptiveColors) {
                                onCopy()
                            }
                            Divider().background(adaptiveColors.messageBubbleStroke)
                        }

                        MenuRow(title: "chat.action.deleteForMe", icon: "trash", isDestructive: true, adaptiveColors: adaptiveColors) {
                            onDeleteForMe()
                        }

                        if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) {
                            Divider().background(adaptiveColors.messageBubbleStroke)
                            MenuRow(title: "chat.action.deleteForEveryone", icon: "trash.fill", isDestructive: true, adaptiveColors: adaptiveColors) {
                                onDeleteForEveryone()
                            }
                        }
                    }
                }
                .frame(width: 250)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(adaptiveColors.messageBubbleBackground)
                        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                )
                .offset(y: animateIn ? 0 : 20)
                .opacity(animateIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animateIn = true
            }
        }
    }

    private func handleDismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func isWithinDeleteLimit(_ timestamp: Date) -> Bool {
        return Date().timeIntervalSince(timestamp) < 7200
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let adaptiveColors: AdaptiveColors
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack {
                Text(title)
                    .font(.custom("Poppins-Regular", size: 16))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18))
            }
            .foregroundColor(isDestructive ? .red : adaptiveColors.messageTextColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassActionButton: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let adaptiveColors: AdaptiveColors
    let action: () -> Void

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
            .foregroundColor(isDestructive ? Color.red : adaptiveColors.messageTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(adaptiveColors.messageBubbleBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
