import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

struct UserRelationshipChip: View {
    let title: String
    let icon: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(title)
                .font(.custom("Poppins-Medium", size: 11))
                .lineLimit(1)
        }
        .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.68))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .liquidGlass(in: Capsule(), interactive: false)
    }
}

struct UserRelationshipManagementSheet: View {
    let username: String
    let profileImagePath: String?
    let userId: String
    let isBestFriend: Bool
    let isMuted: Bool
    let isMutual: Bool
    let customListCount: Int
    let customLists: [CustomAudienceList]
    let isUpdatingBestFriend: Bool
    let isUpdatingMute: Bool
    let isUpdatingLists: Bool
    let onToggleBestFriend: () -> Void
    let onToggleMute: () -> Void
    let onRemoveFromList: (CustomAudienceList) -> Void
    let onUnfollow: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLists = false
    @State private var listPendingRemoval: CustomAudienceList?

    private var relationshipSummaryItems: [String] {
        var items: [String] = []
        if isMutual { items.append(NSLocalizedString("userProfile.relationship.mutual", comment: "")) }
        if customListCount > 0 { items.append(NSLocalizedString("userProfile.relationship.inLists", comment: "")) }
        if isMuted { items.append(NSLocalizedString("userProfile.relationship.muted", comment: "")) }
        return items
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                relationshipAvatar

                VStack(spacing: 4) {
                    Text(String(format: NSLocalizedString("userProfile.relationship.sheet.title", comment: ""), username))
                        .font(.custom("Poppins-Bold", size: 22))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("userProfile.relationship.sheet.subtitle", comment: ""))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.56))
                        .multilineTextAlignment(.center)
                }

                if !relationshipSummaryItems.isEmpty {
                    Text(relationshipSummaryItems.joined(separator: " · "))
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.46))
                        .lineLimit(1)
                }
            }
            .padding(.top, 18)

            ZStack {
                if showingLists {
                    listsContent
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    mainContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showingLists)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
                relationshipActionRow(
                    title: isBestFriend
                        ? NSLocalizedString("userProfile.relationship.bestFriends", comment: "")
                        : NSLocalizedString("userProfile.relationship.bestFriends.add", comment: ""),
                    subtitle: isBestFriend
                        ? NSLocalizedString("userProfile.relationship.bestFriends.remove.subtitle", comment: "")
                        : NSLocalizedString("userProfile.relationship.bestFriends.add.subtitle", comment: ""),
                    icon: isBestFriend ? "star.fill" : "star",
                    iconColor: isBestFriend ? .green : nil,
                    isLoading: isUpdatingBestFriend,
                action: onToggleBestFriend
            )

            relationshipActionRow(
                title: isMuted
                    ? NSLocalizedString("userProfile.relationship.mute.disable", comment: "")
                    : NSLocalizedString("userProfile.relationship.mute.enable", comment: ""),
                subtitle: isMuted
                    ? NSLocalizedString("userProfile.relationship.mute.disabled.subtitle", comment: "")
                    : NSLocalizedString("userProfile.relationship.mute.enabled.subtitle", comment: ""),
                icon: isMuted ? "speaker.wave.2" : "speaker.slash",
                iconColor: nil,
                isLoading: isUpdatingMute,
                action: onToggleMute
            )

            Button(action: {
                showingLists = true
            }) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("userProfile.relationship.lists.title", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 15))
                        Text(customListCount > 0
                            ? String(format: NSLocalizedString("userProfile.relationship.lists.count", comment: ""), customListCount)
                            : NSLocalizedString("userProfile.relationship.lists.empty", comment: ""))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 17, weight: .semibold))

                        if customListCount > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.46) : .black.opacity(0.38))
                        }
                    }
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onUnfollow) {
                HStack(spacing: 14) {
                    Text(NSLocalizedString("userProfile.relationship.unfollow", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 15))

                    Spacer()

                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.red)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var listsContent: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button(action: {
                    showingLists = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 34, height: 34)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("userProfile.relationship.lists.title", comment: ""))
                        .font(.custom("Poppins-Bold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(NSLocalizedString("userProfile.relationship.lists.manage", comment: ""))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                }

                Spacer()
            }

            if customLists.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.44) : .black.opacity(0.38))

                    Text(NSLocalizedString("userProfile.relationship.lists.empty", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                VStack(spacing: 0) {
                    ForEach(customLists) { list in
                        Button(action: {
                            listPendingRemoval = list
                        }) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.custom("Poppins-SemiBold", size: 15))
                                    Text(String(format: NSLocalizedString("audience.people.count", comment: ""), list.members.count))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                                }

                                Spacer()

                                if isUpdatingLists {
                                    ProgressView()
                                        .scaleEffect(0.82)
                                } else {
                                    Image(systemName: list.icon ?? "list.bullet")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdatingLists)
                    }
                }
            }
        }
        .confirmationDialog(
            listRemovalTitle,
            isPresented: Binding(
                get: { listPendingRemoval != nil },
                set: { if !$0 { listPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.relationship.lists.remove.action", comment: ""), role: .destructive) {
                if let list = listPendingRemoval {
                    onRemoveFromList(list)
                    listPendingRemoval = nil
                }
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                listPendingRemoval = nil
            }
        } message: {
            Text(listRemovalMessage)
        }
    }

    private var listRemovalTitle: String {
        guard let listPendingRemoval else {
            return NSLocalizedString("userProfile.relationship.lists.remove.title.fallback", comment: "")
        }

        return String(
            format: NSLocalizedString("userProfile.relationship.lists.remove.title", comment: ""),
            username,
            listPendingRemoval.name
        )
    }

    private var listRemovalMessage: String {
        NSLocalizedString("userProfile.relationship.lists.remove.message", comment: "")
    }

    private var relationshipAvatar: some View {
        Group {
            if let profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.58))
            }
        }
        .frame(width: 62, height: 62)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        .clipShape(Circle())
    }

    private func relationshipActionRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color?,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.82)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(iconColor ?? (colorScheme == .dark ? .white : .black))
                        .frame(width: 24)
                }
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

}

// ✅ NUEVO: Modal elegante para solicitud de mensaje (mismo estilo que MessageRequestsView)
struct MessageRequestModalView: View {
    @Binding var messageText: String
    @Binding var errorMessage: String?
    @Binding var showingSuccessMessage: Bool
    let onSend: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Content
            contentView

            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("messageRequestModal.title", comment: "Modal title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(adaptiveColors.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Content View
    private var contentView: some View {
        VStack(spacing: 24) {
                            // Icono principal
                VStack(spacing: 16) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.blue)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("messageRequestModal.description", comment: "Modal description"))
                        .font(.body)
                        .foregroundColor(adaptiveColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            // Campo de texto
            VStack(spacing: 12) {
                TextField(NSLocalizedString("messageRequestModal.placeholder", comment: "Message placeholder"), text: $messageText, axis: .vertical)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(adaptiveColors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .focused($isTextFieldFocused)
                    .lineLimit(3...6)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                }
            }

            // Botones de acción
            VStack(spacing: 12) {
                Button(action: onSend) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .medium))

                        Text(NSLocalizedString("messageRequestModal.sendButton", comment: "Send button"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)

                Button(action: { dismiss() }) {
                    Text(NSLocalizedString("messageRequestModal.cancelButton", comment: "Cancel button"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(adaptiveColors.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(adaptiveColors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                colors: adaptiveColors.overlayStroke,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 20)
    }
}
