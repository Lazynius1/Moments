import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

extension EnhancedNotificationRow {
    // ✅ TRAILING CONTENT ADAPTATIVO
    var trailingContent: some View {
        Group {
            switch group.notifications.first?.type {
            case .like, .comment, .reaction, .photoTag: // ✅ AÑADIDO .photoTag
                if let path = momentImagePath, let url = URL(string: path), !momentImageLoadFailed {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(Color(hex: "007AFF"))
                                )
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    colorScheme == .dark ?
                                    Color.white.opacity(0.2) :
                                    Color.black.opacity(0.1),
                                    lineWidth: 1
                                ) // ✅ ADAPTATIVO
                        )
                        .onTapGesture {
                            onTapAction()
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(
                                    colorScheme == .dark ?
                                    .white.opacity(0.6) :
                                    .black.opacity(0.5)
                                ) // ✅ ADAPTATIVO
                                .font(.system(size: 16))
                        )
                }

            case .mention:
                if let first = group.notifications.first, isStoryMention(first) {
                    storyMentionThumbnail
                } else if let path = momentImagePath, let url = URL(string: path), !momentImageLoadFailed {
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(Color(hex: "007AFF"))
                                )
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "at")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.55))
                                .font(.system(size: 16, weight: .semibold))
                        )
                }

            case .storyReaction:
                NotificationStoryThumbnailView(
                    imagePath: storyImagePath,
                    reaction: group.notifications.first?.reaction,
                    colorScheme: colorScheme,
                    loadFailed: storyImageLoadFailed
                )

            case .storyChainContinued:
                if let path = storyImagePath, let url = URL(string: path), !storyImageLoadFailed {
                    ZStack(alignment: .bottomTrailing) {
                        KFImage(url)
                            .placeholder {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(Color(hex: "007AFF"))
                                    )
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )

                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                    .frame(width: 44, height: 44)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(
                                    colorScheme == .dark ?
                                    .white.opacity(0.72) :
                                    .black.opacity(0.62)
                                )
                                .font(.system(size: 17, weight: .semibold))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                }

            case .followRequest:
                HStack(spacing: 8) {
                    Button(NSLocalizedString("notifications.accept", comment: "Accept button")) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.acceptFollowRequest(group: group)
                        }
                    }
                    .buttonStyle(GlassmorphicButtonStyle(
                        color: Color(hex: "007AFF"),
                        colorScheme: colorScheme // ✅ PASADO colorScheme
                    ))
                    
                    Button(NSLocalizedString("notifications.reject", comment: "Reject button")) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.rejectFollowRequest(group: group)
                        }
                    }
                    .buttonStyle(GlassmorphicButtonStyle(
                        color: .red,
                        colorScheme: colorScheme // ✅ PASADO colorScheme
                    ))
                }

            case .newFollower, .mutualConnection:
                Button(action: {
                    toggleFollow()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: notificationFollowIcon)
                            .font(.system(size: 12, weight: .semibold))

                        Text(notificationFollowTitle)
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .liquidGlass(in: Capsule(), interactive: followButtonState.isActionable)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!followButtonState.isActionable)
                .opacity(notificationFollowIsPassive ? 0.78 : 1)

            case .echoSuggestion:
                // 🌊 Echo notification preview with Nova Spark styling
                Button(action: onTapAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                            .font(.system(size: 20))
                        
                        Text(NSLocalizedString("notifications.echo.viewAction", comment: "View Echo button"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [.orange.opacity(0.2), .yellow.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [.orange.opacity(0.6), .yellow.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())

            case .dataExportReady:
                Button(action: onTapAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(NSLocalizedString("notifications.export.download", comment: "Download export button"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "007AFF"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "007AFF").opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

            case .mediaModeration:
                Button(action: {
                    if let notification = group.notifications.first {
                        onModerationReviewTap?(notification)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(NSLocalizedString("notifications.mediaModeration.reviewAction", comment: "Review action for moderated content"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.84))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

            default:
                EmptyView()
            }
        }
    }

    var storyMentionThumbnail: some View {
        NotificationStoryThumbnailView(
            imagePath: storyImagePath,
            reaction: nil,
            colorScheme: colorScheme,
            loadFailed: storyImageLoadFailed
        )
    }
}
