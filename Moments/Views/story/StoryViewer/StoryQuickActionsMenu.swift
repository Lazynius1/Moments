import SwiftUI

struct StoryQuickActionsMenu: View {
    let isOwnStory: Bool
    let canLeaveBestFriends: Bool
    let textColor: Color
    let dividerColor: Color
    let onViewActivity: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onUnfollow: () -> Void
    let onMute: () -> Void
    let onReport: () -> Void
    let onLeaveBestFriends: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isOwnStory {
                row(
                    title: NSLocalizedString("storyContextMenu.viewActivity", comment: "View activity button"),
                    action: onViewActivity
                )

                divider

                row(
                    title: NSLocalizedString("storyContextMenu.save", comment: "Save story button"),
                    action: onSave
                )

                divider

                row(
                    title: NSLocalizedString("storyContextMenu.delete", comment: "Delete story button"),
                    isDestructive: true,
                    action: onDelete
                )
            } else {
                row(
                    title: NSLocalizedString("storyContextMenu.unfollow", comment: "Unfollow user button"),
                    action: onUnfollow
                )

                divider

                row(
                    title: NSLocalizedString("storyContextMenu.mute", comment: "Mute user button"),
                    action: onMute
                )

                divider

                row(
                    title: NSLocalizedString("storyContextMenu.report", comment: "Report story button"),
                    isDestructive: true,
                    action: onReport
                )

                if canLeaveBestFriends {
                    divider

                    row(
                        title: NSLocalizedString("storyContextMenu.leaveBestFriends", comment: "Leave best friends"),
                        action: onLeaveBestFriends
                    )
                }
            }
        }
        .frame(minWidth: 200)
        .fixedSize(horizontal: true, vertical: false)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
        }
    }

    private var divider: some View {
        Divider()
            .background(dividerColor)
    }

    private func row(
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        StoryMenuActionRow(
            title: title,
            textColor: textColor,
            isDestructive: isDestructive,
            action: action
        )
    }
}

private struct StoryMenuActionRow: View {
    let title: String
    let textColor: Color
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDestructive ? .red : textColor)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsMenuRow)
    }
}
