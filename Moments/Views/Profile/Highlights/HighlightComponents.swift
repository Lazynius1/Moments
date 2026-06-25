import SwiftUI
import Kingfisher

// MARK: - Story grid estilo Instagram (edge-to-edge, 9:16, fecha grande, duración vídeo)

struct HighlightStoryGrid: View {
    let stories: [Story]
    let selectedIds: Set<String>
    let isLoading: Bool
    let isEmpty: Bool
    var emptyMessageKey: String = "highlightedStories.noStoriesToSelect"
    let onToggle: (Story) -> Void
    let onStoryAppear: (Story) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    private let rowSpacing: CGFloat = 1

    var body: some View {
        Group {
            if isLoading && isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(NSLocalizedString("common.loading", comment: "Loading"))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else if isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(NSLocalizedString(emptyMessageKey, comment: "No stories to select"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .padding(.horizontal, 24)
            } else {
                LazyVGrid(columns: columns, spacing: rowSpacing) {
                    ForEach(stories) { story in
                        HighlightSelectableArchiveCard(
                            story: story,
                            isSelected: selectedIds.contains(story.id ?? ""),
                            onTap: { onToggle(story) }
                        )
                        .onAppear { onStoryAppear(story) }
                    }
                }
            }
        }
    }
}

struct HighlightArchiveStoryCardVisual: View {
    let story: Story

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                storyThumbnail
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                VStack {
                    HStack {
                        HighlightStoryDateBadge(date: story.timestamp)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)

                if story.mediaItem.type == .video {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            Text(Self.formatVideoDuration(story.duration))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        }
                    }
                    .padding(7)
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private var storyThumbnail: some View {
        let urlString = story.mediaItem.thumbnailUrl ?? story.mediaItem.url
        if let url = URL(string: urlString) {
            KFImage(url)
                .placeholder {
                    Rectangle().fill(Color.gray.opacity(0.22))
                }
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.22))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray.opacity(0.5))
                )
        }
    }

    static func formatVideoDuration(_ duration: Double) -> String {
        let total = max(Int(duration.rounded()), 0)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct HighlightStoryDateBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(dayText)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(monthText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.black.opacity(0.75))
                .textCase(.lowercase)
                .lineLimit(1)
        }
        .frame(minWidth: 34)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white)
        )
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}

struct HighlightSelectableArchiveCard: View {
    let story: Story
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                HighlightArchiveStoryCardVisual(story: story)
                    .overlay {
                        if isSelected {
                            Color.black.opacity(0.22)
                        }
                    }

                selectionBadge
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: isSelected)
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(ProfileColors.accent)
                    .frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Editor chrome

struct HighlightEditorBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.35 : 0.5)
                .ignoresSafeArea()
        }
    }
}

struct HighlightEditorHeader: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(Color.clear.momentsChromeGlass(in: Capsule()))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

struct HighlightViewerTitlePill: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    private var textColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.88)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
    }

    var body: some View {
        Text(title)
            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
            .foregroundColor(textColor)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear.momentsChromeGlass(in: Capsule()))
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }
}

struct HighlightEditorBottomBar: View {
    @Binding var title: String
    let coverURL: String?
    let isSaving: Bool
    let actionTitle: String
    let isActionEnabled: Bool
    let onCoverTap: () -> Void
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button(action: onCoverTap) {
                    ZStack {
                        if let coverURL, let url = URL(string: coverURL) {
                            KFImage(url)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                )
                        }

                        Circle()
                            .stroke(ProfileColors.accent.opacity(0.6), lineWidth: 2)
                            .frame(width: 52, height: 52)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("highlightedStories.titleLabel", comment: "Title"))
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(
                        NSLocalizedString("highlightedStories.titlePlaceholder", comment: "Title Placeholder"),
                        text: $title
                    )
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                }
            }

            Button(action: onAction) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                    Text(actionTitle)
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(isActionEnabled ? ProfileColors.accent : Color.gray.opacity(0.35))
                )
            }
            .disabled(!isActionEnabled || isSaving)
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

struct HighlightCoverPickerSheet: View {
    let stories: [Story]
    let selectedCoverId: String?
    let onSelect: (Story) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                if !stories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stories) { story in
                                Button {
                                    onSelect(story)
                                    dismiss()
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        HighlightArchiveStoryCardVisual(story: story)
                                            .frame(width: 56)

                                        if selectedCoverId == story.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(ProfileColors.accent, .white)
                                                .padding(4)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }

                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(stories) { story in
                        Button {
                            onSelect(story)
                            dismiss()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                HighlightArchiveStoryCardVisual(story: story)

                                if selectedCoverId == story.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(ProfileColors.accent, .white)
                                        .padding(8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("highlightedStories.selectCover", comment: "Select Cover"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

}
