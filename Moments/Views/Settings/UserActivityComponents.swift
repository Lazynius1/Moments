import SwiftUI
import Kingfisher
import AVFoundation

struct ActivityInteractionCategoryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: ActivityInteractionCategory
    let summary: ActivityCategorySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Group {
                    if category == .reactions {
                        AnimatedReactionIcon()
                    } else if category == .comments {
                        AnimatedCommentIcon()
                    } else if category == .echoes {
                        EchoesIconView(
                            size: EchoesIconMetrics.categoryRow,
                            tintColor: colorScheme == .dark ? .white : .black
                        )
                        .frame(width: 36, height: 36)
                    } else if category == .tags {
                        AttachmentIconView(
                            icon: .tagged,
                            preset: .activityCategoryRow,
                            tintColor: colorScheme == .dark ? .white : .black
                        )
                        .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .frame(width: 36, height: 36)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString(category.titleKey, comment: "Interaction category title"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        if let count = summary?.count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: legacyPoppinsSize(11), weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(category.accentColor)
                                )
                        }
                    }

                    Text(NSLocalizedString(category.subtitleKey, comment: "Interaction category subtitle"))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

struct StripThumbCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let thumb: ThumbInfo
    @State private var generatedThumbnail: UIImage?
    @State private var isGenerating = false

    private let size: CGFloat = 52

    var body: some View {
        ScreenshotProtectedView(isProtected: thumb.isProtected) {
            ZStack {
                content
                    .blur(radius: thumb.canView ? 0 : 12)

                if !thumb.canView {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if !thumb.url.isEmpty, let url = URL(string: thumb.url) {
            KFImage(url)
                .placeholder {
                    placeholder
                }
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else if let videoUrl = thumb.videoUrl {
            ZStack {
                if let img = generatedThumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    placeholder
                        .onAppear { generateThumbnail(from: videoUrl) }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 2)
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
            .frame(width: size, height: size)
    }

    private func generateThumbnail(from videoPath: String) {
        guard !isGenerating, generatedThumbnail == nil else { return }
        isGenerating = true
        Task {
            let image = await VideoThumbnailCache.shared.thumbnail(for: videoPath)
            await MainActor.run {
                generatedThumbnail = image ?? generatedThumbnail
                isGenerating = false
            }
        }
    }
}

struct AuthorFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedAuthorId: String?
    let availableAuthorIds: [String]
    let authorUsernameMap: [String: String]
    @State private var searchText: String = ""

    private var filteredAuthorIds: [String] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return availableAuthorIds }

        return availableAuthorIds.filter { authorId in
            if let username = authorUsernameMap[authorId], username.lowercased().contains(term) {
                return true
            }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredAuthorIds, id: \.self) { authorId in
                    Button {
                        selectedAuthorId = (selectedAuthorId == authorId) ? nil : authorId
                        dismiss()
                    } label: {
                        HStack {
                            StoryRingAvatarView(userId: authorId, size: 36, lineWidth: 2.3)

                            Text(authorUsernameMap[authorId] ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)

                            Spacer()
                            if selectedAuthorId == authorId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("userActivity.simple.filters.author.sheet.title", comment: "Author filter sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("userActivity.simple.filters.author.search", comment: "Search author filter")
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
