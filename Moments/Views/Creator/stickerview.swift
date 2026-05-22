import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Kingfisher
import CoreLocation
import MapKit
import WeatherKit
import PhotosUI
import AVFoundation
import AVKit


// MARK: - Sticker Picker

struct StickerPickerView: View {
    @Binding var selectedStickers: [StickerItem]
    let isVideo: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var catalogSearchText = ""
    @State private var gifSearchText = ""
    @State private var selectedCategory: StickerCategory = .trending
    @State private var giphyResults: [GiphyGif] = []
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var isLoadingGiphy = false
    @State private var mode: PickerMode = .catalog
    private let functionsRegion = "europe-southwest1"
    private let giphyFunctionName = "proxyGiphyStickers"

    private enum PickerMode: Equatable {
        case catalog
        case detail(StickerCategory)
    }

    enum StickerCategory: String, CaseIterable, Identifiable {
        case trending
        case emoji
        case location
        case mention
        case link
        case hashtag
        case poll
        case question
        case emojiSlider
        case countdown
        case weather
        case time
        case selfie
        case quiz
        case frame
        case reveal
        case audio

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .trending: return NSLocalizedString("stickerview.category.gif", comment: "GIF category")
            case .emoji: return NSLocalizedString("stickerview.category.emoji", comment: "Emoji category")
            case .location: return NSLocalizedString("stickerview.category.location", comment: "Location category")
            case .mention: return NSLocalizedString("stickerview.category.mention", comment: "Mention category")
            case .link: return NSLocalizedString("stickerview.category.link", comment: "Link category")
            case .hashtag: return NSLocalizedString("stickerview.category.hashtag", comment: "Hashtag category")
            case .poll: return NSLocalizedString("stickerview.category.poll", comment: "Poll category")
            case .question: return NSLocalizedString("stickerview.category.question", comment: "Question category")
            case .emojiSlider: return NSLocalizedString("stickerview.category.emojiSlider", comment: "Emoji slider category")
            case .countdown: return NSLocalizedString("stickerview.category.countdown", comment: "Countdown category")
            case .weather: return NSLocalizedString("stickerview.category.weather", comment: "Weather category")
            case .time: return NSLocalizedString("stickerview.category.time", comment: "Time category")
            case .selfie: return NSLocalizedString("stickerview.category.selfie", comment: "Selfie category")
            case .quiz: return NSLocalizedString("stickerview.category.quiz", comment: "Quiz category")
            case .frame: return NSLocalizedString("stickerview.category.frame", comment: "Frame category")
            case .reveal: return NSLocalizedString("stickerview.category.reveal", comment: "Reveal category")
            case .audio: return NSLocalizedString("stickerview.category.audio", comment: "Audio category")
            }
        }

        var symbolName: String {
            switch self {
            case .trending: return "sparkles.rectangle.stack.fill"
            case .emoji: return "face.smiling.fill"
            case .location: return "mappin.and.ellipse"
            case .mention: return "at"
            case .link: return "link"
            case .hashtag: return "number"
            case .poll: return "chart.bar.xaxis"
            case .question: return "questionmark.bubble.fill"
            case .emojiSlider: return "face.smiling.inverse"
            case .countdown: return "timer"
            case .weather: return "cloud.sun.fill"
            case .time: return "clock.fill"
            case .selfie: return "person.crop.circle.badge.plus"
            case .quiz: return "list.bullet.clipboard.fill"
            case .frame: return "photo.artframe"
            case .reveal: return "eye.slash.fill"
            case .audio: return "mic.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .trending: return Color(red: 0.33, green: 0.84, blue: 0.44)
            case .emoji: return Color(red: 1.00, green: 0.72, blue: 0.18)
            case .location: return Color(red: 0.53, green: 0.32, blue: 0.98)
            case .mention: return Color(red: 0.98, green: 0.50, blue: 0.14)
            case .link: return Color(red: 0.29, green: 0.72, blue: 0.98)
            case .hashtag: return Color(red: 0.92, green: 0.23, blue: 0.88)
            case .poll: return Color(red: 0.91, green: 0.25, blue: 0.74)
            case .question: return Color(red: 0.85, green: 0.26, blue: 0.84)
            case .emojiSlider: return Color(red: 0.99, green: 0.56, blue: 0.21)
            case .countdown: return Color(red: 0.61, green: 0.34, blue: 0.97)
            case .weather: return Color(red: 0.20, green: 0.77, blue: 0.95)
            case .time: return Color(red: 1.00, green: 0.62, blue: 0.20)
            case .selfie: return Color(red: 1.00, green: 0.25, blue: 0.55)
            case .quiz: return .orange
            case .frame: return .blue
            case .reveal: return .purple
            case .audio: return Color(red: 1.0, green: 0.4, blue: 0.3) // Coral/Orange
            }
        }

    }

    private var catalogCategories: [StickerCategory] {
        [.location, .mention, .trending, .emoji, .link, .question, .poll, .quiz, .reveal, .audio, .frame, .emojiSlider, .hashtag, .countdown, .weather, .time, .selfie]
    }

    private var filteredCatalogCategories: [StickerCategory] {
        let query = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var baseCategories = catalogCategories

        // ✨ Reveal limit: only one allowed per story
        if selectedStickers.contains(where: { $0.type == .reveal }) {
            baseCategories.removeAll(where: { $0 == .reveal })
        }

        // ✨ Audio limit: only one allowed per story and NO video
        if isVideo || selectedStickers.contains(where: { $0.type == .audio }) {
            baseCategories.removeAll(where: { $0 == .audio })
        }

        guard !query.isEmpty else { return baseCategories }
        return baseCategories.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var shouldShowCatalogSearch: Bool {
        mode == .catalog
    }

    private var shouldShowGifSearch: Bool {
        if case .detail(.trending) = mode {
            return true
        }
        return false
    }

    private var detailTitle: String {
        if case .detail(let category) = mode {
            return category.displayName
        }
        return ""
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var pickerBackgroundColor: Color {
        isDarkMode
            ? Color(red: 11 / 255, green: 18 / 255, blue: 21 / 255)
            : Color(red: 250 / 255, green: 249 / 255, blue: 246 / 255)
    }

    private var primaryTextColor: Color {
        isDarkMode ? .white : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        isDarkMode ? .white.opacity(0.58) : Color.black.opacity(0.48)
    }

    private var searchIconColor: Color {
        isDarkMode ? .white.opacity(0.54) : Color.black.opacity(0.36)
    }

    private var searchClearColor: Color {
        isDarkMode ? .white.opacity(0.56) : Color.black.opacity(0.34)
    }

    private var handleColor: Color {
        isDarkMode ? Color.white.opacity(0.16) : Color.black.opacity(0.16)
    }

    private var chromeFillColor: Color {
        isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var chromeStrokeColor: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var pillFillTopColor: Color {
        isDarkMode
            ? .white
            : Color(red: 11 / 255, green: 18 / 255, blue: 21 / 255)
    }

    private var pillFillBottomColor: Color {
        isDarkMode
            ? Color(red: 0.97, green: 0.95, blue: 0.91)
            : Color(red: 20 / 255, green: 29 / 255, blue: 34 / 255)
    }

    private var pillTextColor: Color {
        isDarkMode ? Color.black.opacity(0.92) : .white
    }

    var body: some View {
        ZStack {
            StickerPickerBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(handleColor)
                    .frame(width: 42, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                if case .detail = mode {
                    StickerPickerHeader()
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                if shouldShowCatalogSearch {
                    CatalogSearchBar()
                } else if shouldShowGifSearch {
                    GifSearchBar()
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if mode == .catalog {
                            StickerCatalogMosaic()
                        } else {
                            stickerContent
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    if selectedCategory == .trending {
                        loadTrendingStickers()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarHidden(true)
        .onAppear {
            if giphyResults.isEmpty {
                loadTrendingStickers()
            }
        }
    }

    @ViewBuilder
    private func StickerPickerBackground() -> some View {
        Color.clear
    }

    @ViewBuilder
    private func StickerPickerHeader() -> some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.lightImpact()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    mode = .catalog
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(chromeFillColor)
                            .overlay(Circle().stroke(chromeStrokeColor, lineWidth: 1))
                    )
            }
            .pressAnimation()

            Spacer()

            Text(detailTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(primaryTextColor)

            Spacer()

            Button(action: {
                HapticManager.shared.lightImpact()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(chromeFillColor)
                            .overlay(Circle().stroke(chromeStrokeColor, lineWidth: 1))
                    )
            }
            .pressAnimation()
        }
    }

    @ViewBuilder
    private func CatalogSearchBar() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(searchIconColor)

            TextField(NSLocalizedString("stickerview.search.placeholder", comment: "Sticker catalog search placeholder"), text: $catalogSearchText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(primaryTextColor)
                .autocorrectionDisabled()
                .autocapitalization(.none)

            if !catalogSearchText.isEmpty {
                Button(action: {
                    HapticManager.shared.lightImpact()
                    withAnimation(.easeOut(duration: 0.2)) {
                        catalogSearchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(searchClearColor)
                }
                .pressAnimation()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func GifSearchBar() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(searchIconColor)

            TextField(NSLocalizedString("stickerview.searchGifs.placeholder", comment: "GIF search placeholder"), text: $gifSearchText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(primaryTextColor)
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .onSubmit {
                    HapticManager.shared.lightImpact()
                    if gifSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        loadTrendingStickers()
                    } else {
                        searchTrendingStickers()
                    }
                }

            if !gifSearchText.isEmpty {
                Button(action: {
                    HapticManager.shared.lightImpact()
                    withAnimation(.easeOut(duration: 0.2)) {
                        gifSearchText = ""
                        loadTrendingStickers()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(searchClearColor)
                }
                .pressAnimation()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func StickerCatalogMosaic() -> some View {
        if filteredCatalogCategories.isEmpty {
            StickerEmptyState(
                icon: "magnifyingglass",
                title: NSLocalizedString("stickerview.catalog.emptyTitle", comment: "No stickers found title"),
                subtitle: NSLocalizedString("stickerview.catalog.emptySubtitle", comment: "No stickers found subtitle")
            )
        } else {
            VStack(alignment: .leading, spacing: 22) {
                StickerPillFlowLayout(spacing: 10, rowSpacing: 10) {
                    ForEach(Array(filteredCatalogCategories.enumerated()), id: \.element.id) { index, category in
                        StickerCatalogPill(category: category) {
                            handleCatalogSelection(category)
                        }
                        .rotationEffect(catalogPillTilt(for: index))
                        .offset(y: catalogPillVerticalOffset(for: index))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 2)

                CatalogGifPreviewSection()
            }
        }
    }

    @ViewBuilder
    private func StickerCatalogPill(
        category: StickerCategory,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CatalogPillIcon(category: category)

                if category != .emojiSlider {
                    Text(category.displayName)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(pillTextColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, category == .emojiSlider ? 10 : 14)
            .frame(height: category == .emojiSlider ? 44 : 46)
            .frame(minWidth: category == .emojiSlider ? 148 : nil)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                pillFillTopColor,
                                pillFillBottomColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isDarkMode ? Color.white.opacity(0.80) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isDarkMode ? 0.10 : 0.06), radius: 8, y: 5)
            )
        }
        .buttonStyle(.plain)
        .pressAnimation()
    }

    @ViewBuilder
    private func CatalogPillIcon(category: StickerCategory) -> some View {
        if category == .emojiSlider {
            StickerEmojiSliderPillGlyph()
                .frame(width: 122, height: 28)
        } else {
            Image(systemName: category.symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(category.accentColor)
                .shadow(color: category.accentColor.opacity(0.22), radius: 1.5, x: 0, y: 0)
                .frame(width: 18, height: 18)
        }
    }

    @ViewBuilder
    private func CatalogGifPreviewSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("stickerview.catalog.gifs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(primaryTextColor)

                Spacer()

                Button(action: {
                    handleCatalogSelection(.trending)
                }) {
                    Text("stickerview.catalog.viewAll")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(primaryTextColor.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(chromeFillColor)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(chromeStrokeColor, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .pressAnimation()
            }

            if isLoadingGiphy && giphyResults.isEmpty {
                MomentsLoadingView()
            } else if !giphyResults.isEmpty {
                CatalogTrendingPreviewGrid(stickers: Array(giphyResults.prefix(12)))
            }
        }
    }

    private func catalogPillTilt(for index: Int) -> Angle {
        switch index % 6 {
        case 0: return .degrees(-2)
        case 1: return .degrees(1.4)
        case 2: return .degrees(-1)
        case 3: return .degrees(2)
        case 4: return .degrees(-1.6)
        default: return .degrees(0.8)
        }
    }

    private func catalogPillVerticalOffset(for index: Int) -> CGFloat {
        switch index % 5 {
        case 0: return 0
        case 1: return 2
        case 2: return -1
        case 3: return 1
        default: return -2
        }
    }

    @ViewBuilder
    private func QuickEmojiRow() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(trendingEmojis.prefix(12)), id: \.self) { emoji in
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        createEmojiSticker(emoji)
                    }) {
                        Text(emoji)
                            .font(.system(size: 23))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .pressAnimation()
                }
            }
        }
    }

    @ViewBuilder
    private var stickerContent: some View {
        switch selectedCategory {
        case .trending:
            if isLoadingGiphy {
                MomentsLoadingView()
            } else if giphyResults.isEmpty {
                StickerEmptyState(
                    icon: "sparkles.rectangle.stack",
                    title: NSLocalizedString("stickerview.trending.emptyTitle", comment: "No trending stickers title"),
                    subtitle: NSLocalizedString("stickerview.trending.emptySubtitle", comment: "No trending stickers subtitle")
                )
            } else {
                MomentsTrendingGrid(stickers: giphyResults)
            }

        case .emoji:
            VStack(alignment: .leading, spacing: 16) {
                QuickEmojiRow()
                MomentsEmojiGrid()
            }

        case .location:
            SmartLocationInputView { location, coordinate in
                createLocationSticker(location, coordinate: coordinate)
            }

        case .mention:
            ModernMentionInputView { username in
                createMentionSticker(username)
            }

        case .link:
            ModernLinkInputView { urlString, customTitle in
                createLinkSticker(urlString: urlString, customTitle: customTitle)
            }

        case .hashtag:
            ModernHashtagInputView { hashtag in
                createHashtagSticker(hashtag)
            }

        case .poll:
            ModernPollInputView { poll in
                createPollSticker(poll)
            }

        case .question:
            ModernQuestionInputView { question in
                createQuestionSticker(question)
            }

        case .emojiSlider:
            ModernEmojiSliderInputView { prompt, emoji in
                createEmojiSliderSticker(prompt: prompt, emoji: emoji)
            }

        case .countdown:
            ModernCountdownInputView { title, targetAtMs in
                createCountdownSticker(title: title, targetAtMs: targetAtMs)
            }

        case .quiz:
            ModernQuizInputView { question, options, correctIndex in
                createQuizSticker(question: question, options: options, correctIndex: correctIndex)
            }

        case .frame:
            VStack(spacing: 25) {
                Text(NSLocalizedString("polaroid.title", comment: ""))
                    .font(.system(size: 24, weight: .black, design: .rounded))

                Text(NSLocalizedString("polaroid.subtitle", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label(NSLocalizedString("polaroid.selectPhoto", comment: ""), systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .onChange(of: photoPickerItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            createFrameSticker(image: uiImage)
                        }
                    }
                }
            }
            .padding(30)

        case .reveal:
            VStack(spacing: 20) {
                Text(NSLocalizedString("reveal.title", comment: ""))
                    .font(.system(size: 24, weight: .black, design: .rounded))

                Text(NSLocalizedString("reveal.subtitle", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button(action: {
                    createRevealSticker()
                }) {
                    Text(NSLocalizedString("reveal.addLayer", comment: ""))
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .cornerRadius(16)
                }
            }
            .padding(30)

        case .weather, .time, .selfie:
            EmptyView()

        case .audio:
            AudioStickerRecordingView(onAdd: { data, duration in
                createAudioSticker(audioData: data, duration: duration)
            })
        }
    }

    @ViewBuilder
    private func MomentsTrendingGrid(stickers: [GiphyGif]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(stickers) { sticker in
                Button(action: {
                    HapticManager.shared.mediumImpact()
                    createGiphySticker(from: sticker)
                }) {
                    GeometryReader { proxy in
                        AnimatedGIFView(url: URL(string: sticker.images.fixed_height.url))
                            .frame(width: proxy.size.width, height: proxy.size.width)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .pressAnimation()
            }
        }
    }

    @ViewBuilder
    private func CatalogTrendingPreviewGrid(stickers: [GiphyGif]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(stickers) { sticker in
                Button(action: {
                    HapticManager.shared.mediumImpact()
                    createGiphySticker(from: sticker)
                }) {
                    GeometryReader { proxy in
                        AnimatedGIFView(url: URL(string: sticker.images.fixed_height.url))
                            .frame(width: proxy.size.width, height: proxy.size.width * 1.14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .aspectRatio(0.88, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .pressAnimation()
            }
        }
    }

    @ViewBuilder
    private func MomentsEmojiGrid() -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(trendingEmojis, id: \.self) { emoji in
                Button(action: {
                    HapticManager.shared.lightImpact()
                    createEmojiSticker(emoji)
                }) {
                    Text(emoji)
                        .font(.system(size: 30))
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .pressAnimation()
            }
        }
    }

    @ViewBuilder
    private func MomentsLoadingView() -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: selectedCategory.accentColor))
                .scaleEffect(1.2)

            VStack(spacing: 6) {
                Text("stickerview.loadingStickers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)

                Text("stickerview.loadingTime")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private func StickerEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(secondaryTextColor.opacity(0.9))

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primaryTextColor)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func handleCatalogSelection(_ category: StickerCategory) {
        switch category {
        case .weather, .time, .selfie:
            insertInstantCategory(category)
        default:
            HapticManager.shared.mediumImpact()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                selectedCategory = category
                mode = .detail(category)
            }

            if category == .trending {
                if gifSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    loadTrendingStickers()
                } else {
                    searchTrendingStickers()
                }
            }
        }
    }

    private func insertInstantCategory(_ category: StickerCategory) {
        HapticManager.shared.mediumImpact()

        switch category {
        case .weather:
            createWeatherSticker()
        case .time:
            createTimeSticker()
        case .selfie:
            createSelfieSticker()
        default:
            break
        }
    }


    private var trendingEmojis: [String] {
        ["😍", "🔥", "💯", "✨", "😂", "🥺", "💕", "🎉", "😎", "🤩", "💀", "🙄",
         "😭", "❤️", "🥳", "😘", "🤝", "👑", "💪", "🌟", "🦋", "🌈", "⚡", "💎"]
    }

    // MARK: - Giphy API Methods (proxy por Cloud Functions)

    private func giphyProxyURL() -> URL? {
        guard let projectID = FirebaseApp.app()?.options.projectID else { return nil }
        return URL(string: "https://\(functionsRegion)-\(projectID).cloudfunctions.net/\(giphyFunctionName)")
    }

    private func fetchGiphyStickers(mode: String, query: String? = nil) {
        guard let url = giphyProxyURL() else {
            isLoadingGiphy = false
            return
        }

        guard let user = Auth.auth().currentUser else {
            isLoadingGiphy = false
            return
        }

        user.getIDTokenForcingRefresh(false) { token, _ in
            guard let token = token else {
                DispatchQueue.main.async {
                    self.isLoadingGiphy = false
                }
                return
            }

            var body: [String: Any] = [
                "mode": mode,
                "limit": 24,
                "rating": "pg"
            ]
            if let query = query, !query.isEmpty {
                body["query"] = query
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                DispatchQueue.main.async {
                    self.isLoadingGiphy = false
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = jsonData
            request.timeoutInterval = 20.0

            URLSession.shared.dataTask(with: request) { data, _, error in
                guard let data = data, error == nil else {
                    DispatchQueue.main.async {
                        self.isLoadingGiphy = false
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(GiphyResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.giphyResults = response.data
                        self.isLoadingGiphy = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoadingGiphy = false
                    }
                }
            }.resume()
        }
    }

    private func loadTrendingStickers() {
        isLoadingGiphy = true
        fetchGiphyStickers(mode: "trending")
    }

    private func searchTrendingStickers() {
        let query = gifSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoadingGiphy = true
        fetchGiphyStickers(mode: "search", query: query)
    }

    // MARK: - Sticker Creation Methods (exactamente iguales)

    private func createEmojiSticker(_ emoji: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 150),
                .paragraphStyle: paragraphStyle
            ]

            let textRect = CGRect(x: 0, y: 25, width: 200, height: 200)
            emoji.draw(in: textRect, withAttributes: attributes)
        }

        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .emoji,
            interactionData: nil
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createGiphySticker(from sticker: GiphyGif) {
        guard let url = sticker.preferredStickerURL else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }

            // Crear imagen estática para fallback
            let staticImage: UIImage
            if let animatedImage = UIImage.animatedImageWithData(data) {
                staticImage = animatedImage
            } else if let image = UIImage(data: data) {
                staticImage = image
            } else {
                return
            }

            let initialStickerImage = self.downscaleImageIfNeeded(staticImage, maxDimension: 180)

            DispatchQueue.main.async {
                let screenCenter = CGPoint(
                    x: UIScreen.main.bounds.width / 2,
                    y: UIScreen.main.bounds.height / 2
                )

                let randomOffset = CGPoint(
                    x: CGFloat.random(in: -40...40),
                    y: CGFloat.random(in: -40...40)
                )

                let finalPosition = CGPoint(
                    x: screenCenter.x + randomOffset.x,
                    y: screenCenter.y + randomOffset.y
                )

                let constrainedPosition = self.constrainPositionToBounds(finalPosition)

                // ✅ CREAR STICKER CON GIF ANIMADO usando el inicializador correcto
                let stickerItem = StickerItem(
                    image: initialStickerImage, // Tamaño inicial controlado, sin perder aspect ratio
                    gifURL: url,           // URL para animación
                    position: constrainedPosition,
                    type: .sticker,
                    interactionData: nil
                )

                self.selectedStickers.append(stickerItem)
                self.dismiss()
            }
        }.resume()
    }

    // CAMBIO 5: Función auxiliar para constrainPositionToBounds
    func constrainPositionToBounds(_ position: CGPoint) -> CGPoint {
        let padding: CGFloat = 60
        let bounds = UIScreen.main.bounds

        return CGPoint(
            x: max(padding, min(bounds.width - padding, position.x)),
            y: max(padding, min(bounds.height - padding, position.y))
        )
    }

    func drawStickerCardBackground(
        in context: UIGraphicsImageRendererContext,
        rect: CGRect,
        cornerRadius: CGFloat,
        fillColor: UIColor = .white,
        strokeColor: UIColor = UIColor.black.withAlphaComponent(0.08),
        shadowColor: UIColor = UIColor.black.withAlphaComponent(0.12)
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

        context.cgContext.saveGState()
        context.cgContext.setShadow(offset: CGSize(width: 0, height: 8), blur: 20, color: shadowColor.cgColor)
        fillColor.setFill()
        path.fill()
        context.cgContext.restoreGState()

        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func drawStickerAccentPill(
        in context: UIGraphicsImageRendererContext,
        rect: CGRect,
        fillColor: UIColor,
        iconSystemName: String? = nil,
        iconTint: UIColor = .white
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        fillColor.setFill()
        path.fill()

        if let iconSystemName,
           let icon = UIImage(systemName: iconSystemName)?.withTintColor(iconTint, renderingMode: .alwaysOriginal) {
            let side = min(rect.width, rect.height) * 0.48
            let iconRect = CGRect(
                x: rect.midX - side / 2,
                y: rect.midY - side / 2,
                width: side,
                height: side
            )
            icon.draw(in: iconRect)
        }
    }

    private func drawUtilityStickerText(
        title: String,
        subtitle: String?,
        titleRect: CGRect,
        subtitleRect: CGRect? = nil,
        titleColor: UIColor = UIColor.black.withAlphaComponent(0.92),
        subtitleColor: UIColor = UIColor.black.withAlphaComponent(0.48),
        titleFont: UIFont = .systemFont(ofSize: 19, weight: .semibold),
        subtitleFont: UIFont = .systemFont(ofSize: 12, weight: .medium)
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
            .paragraphStyle: paragraphStyle
        ]
        (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)

        if let subtitle, let subtitleRect {
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: subtitleColor,
                .paragraphStyle: paragraphStyle
            ]
            (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttributes)
        }
    }

    private func createLocationSticker(_ location: String, coordinate: CLLocationCoordinate2D?) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 220, height: 56))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 220, height: 56)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 22)

            drawStickerAccentPill(
                in: context,
                rect: CGRect(x: 12, y: 12, width: 32, height: 32),
                fillColor: UIColor(red: 0.98, green: 0.42, blue: 0.26, alpha: 1),
                iconSystemName: "mappin.and.ellipse"
            )

            let displayText = location.count > 22 ? String(location.prefix(22)) + "..." : location
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.90)
            ]
            (displayText as NSString).draw(
                in: CGRect(x: 54, y: 18, width: 148, height: 20),
                withAttributes: titleAttributes
            )
        }

        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN (TAMAÑO FIJO)
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .location,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: location,
                locationCoordinate: coordinate,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }


    private func cleanupMemory() {
        // ✅ Limpiar recursos pesados
        giphyResults.removeAll()
        isLoadingGiphy = false
        catalogSearchText = ""
        gifSearchText = ""
    }

    // MARK: - ✅ SELFIE STICKER
    private func createSelfieSticker() {
        let liveSelfieSticker = StickerItem(
            image: makeLiveSelfiePlaceholderImage(size: 120),
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2,
                y: UIScreen.main.bounds.height / 2
            )),
            type: .selfie,
            interactionData: StickerItem.StickerInteractionData(
                caption: "selfie_live"
            )
        )

        selectedStickers.append(liveSelfieSticker)
        dismiss()
    }

    private func makeLiveSelfiePlaceholderImage(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: rect)
            UIColor.white.withAlphaComponent(0.92).setFill()
            circlePath.fill()
            UIColor.black.withAlphaComponent(0.08).setStroke()
            circlePath.lineWidth = 1.5
            circlePath.stroke()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: size * 0.38, weight: .bold)
            let icon = UIImage(systemName: "camera.fill", withConfiguration: symbolConfig)?
                .withTintColor(UIColor.black.withAlphaComponent(0.78), renderingMode: .alwaysOriginal)
            icon?.draw(in: CGRect(
                x: size * 0.31,
                y: size * 0.31,
                width: size * 0.38,
                height: size * 0.38
            ))
        }
    }

    // ✅ FUNCIÓN PARA CREAR STICKER DESDE IMAGEN
    func createSelfieStickerFromImage(_ originalImage: UIImage) {
        // ✅ OPTIMIZAR IMAGEN ANTES DE PROCESAR
        // Reducir tamaño masivo (ej. 12MP) a algo manejable para el renderer (800px)
        let selfieImage = downscaleImageIfNeeded(originalImage)

        let size: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let stickerImage = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: rect)

            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            UIColor.white.withAlphaComponent(0.98).setFill()
            circlePath.fill()
            context.cgContext.restoreGState()

            UIColor.black.withAlphaComponent(0.04).setStroke()
            circlePath.lineWidth = 0.5
            circlePath.stroke()

            // ✅ FOTO DEL SELFIE (CIRCULAR)
            let imageRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let imageCirclePath = UIBezierPath(ovalIn: imageRect)

            context.cgContext.saveGState()
            imageCirclePath.addClip()

            // Redimensionar y centrar la imagen
            let aspectRatio = selfieImage.size.width / selfieImage.size.height
            let drawRect: CGRect

            if aspectRatio > 1 {
                // Imagen más ancha que alta
                let drawHeight = imageRect.height
                let drawWidth = drawHeight * aspectRatio
                let drawX = imageRect.midX - drawWidth / 2
                drawRect = CGRect(x: drawX, y: imageRect.minY, width: drawWidth, height: drawHeight)
            } else {
                // Imagen más alta que ancha
                let drawWidth = imageRect.width
                let drawHeight = drawWidth / aspectRatio
                let drawY = imageRect.midY - drawHeight / 2
                drawRect = CGRect(x: imageRect.minX, y: drawY, width: drawWidth, height: drawHeight)
            }

            selfieImage.draw(in: drawRect)
            context.cgContext.restoreGState()
        }

        // ✅ CREAR STICKER CON LA IMAGEN GENERADA
        let sticker = StickerItem(
            image: stickerImage,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .selfie,
            interactionData: nil
        )

        selectedStickers.append(sticker)

        // ✅ LIMPIAR MEMORIA
        cleanupMemory()
        dismiss()
    }

    // ✅ HELPER: Downscale large images before processing
    private func downscaleImageIfNeeded(_ image: UIImage, maxDimension: CGFloat = 800) -> UIImage {
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image
        }

        let aspectRatio = image.size.width / image.size.height
        let newSize: CGSize
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func createMentionSticker(_ username: String) {
        // Primero buscar el usuario por username para obtener su ID y foto
        searchUserByUsername(username) { userResult in
            DispatchQueue.main.async {
                switch userResult {
                case .success(let user):
                    // Usuario encontrado - crear sticker con su foto
                    self.generateMentionStickerWithUser(user)
                case .failure(_):
                    // Usuario no encontrado - crear sticker con placeholder
                    self.generateMentionStickerWithPlaceholder(username)
                }
            }
        }
    }

    // MARK: - Buscar usuario por username
    private func searchUserByUsername(_ username: String, completion: @escaping (Result<AppUser, Error>) -> Void) {
        let firestoreService = FirestoreService()

        // Usar tu método existente de búsqueda
        firestoreService.searchUsers(query: username.lowercased(), limit: 1) { result in
            switch result {
            case .success(let users):
                if let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) {
                    completion(.success(user))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Generar sticker con foto real del usuario
    private func generateMentionStickerWithUser(_ user: AppUser) {
        // ✅ SOLO CREAR STICKER - la notificación se enviará al publicar
        if let profileImagePath = user.profileImagePath, !profileImagePath.isEmpty,
           let profileURL = URL(string: profileImagePath) {

            // Descargar la imagen de perfil
            URLSession.shared.dataTask(with: profileURL) { data, _, error in
                DispatchQueue.main.async {
                    if let data = data, let profileImage = UIImage(data: data) {
                        // Crear sticker con foto real
                        self.generateSticker(username: user.username, userId: user.id, profileImage: profileImage)
                    } else {
                        // Error al descargar - usar placeholder
                        self.generateSticker(username: user.username, userId: user.id, profileImage: nil)
                    }
                }
            }.resume()
        } else {
            // No hay foto de perfil - usar placeholder
            generateSticker(username: user.username, userId: user.id, profileImage: nil)
        }
    }

    // MARK: - Generar sticker con placeholder (cuando no se encuentra usuario)
    private func generateMentionStickerWithPlaceholder(_ username: String) {
        // ✅ No crear sticker si no se encuentra el usuario
    }

    // MARK: - Función principal para generar el sticker (ESTILO INSTAGRAM)
    private func generateSticker(username: String, userId: String, profileImage: UIImage?) {

        let text = "@\(username)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.black.withAlphaComponent(0.92)
        ]

        let textSize = text.size(withAttributes: textAttributes)
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 14
        let iconSize: CGFloat = 28
        let interItemSpacing: CGFloat = 10
        let width = textSize.width + horizontalPadding * 2 + iconSize + interItemSpacing
        let height = max(textSize.height + verticalPadding * 2, 56)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)

            drawStickerCardBackground(in: context, rect: rect, cornerRadius: height / 2)
            drawStickerAccentPill(
                in: context,
                rect: CGRect(x: 14, y: (height - iconSize) / 2, width: iconSize, height: iconSize),
                fillColor: UIColor(red: 0.98, green: 0.65, blue: 0.13, alpha: 1),
                iconSystemName: "at"
            )

            let textRect = CGRect(
                x: 14 + iconSize + interItemSpacing,
                y: (height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: textAttributes)
        }

        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .mention,
            interactionData: StickerItem.StickerInteractionData(
                username: username,
                userId: userId,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
                    )
            selectedStickers.append(sticker)
        dismiss()
    }

    private func createHashtagSticker(_ hashtag: String) {
        let displayText = hashtag.count > 18 ? String(hashtag.prefix(18)) + "..." : hashtag
        let finalText = displayText
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.black.withAlphaComponent(0.92)
        ]
        let textWidth = ceil((finalText as NSString).size(withAttributes: textAttributes).width)
        let width = max(136, min(240, textWidth + 72))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 52))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: 52)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 22)

            drawStickerAccentPill(
                in: context,
                rect: CGRect(x: 12, y: 12, width: 28, height: 28),
                fillColor: UIColor(red: 0.96, green: 0.40, blue: 0.58, alpha: 1),
                iconSystemName: nil
            )

            let hashAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            ("#" as NSString).draw(in: CGRect(x: 20, y: 17, width: 10, height: 16), withAttributes: hashAttributes)

            (finalText as NSString).draw(
                in: CGRect(x: 50, y: 17, width: width - 62, height: 18),
                withAttributes: textAttributes
            )
        }

        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .hashtag,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: hashtag,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createLinkSticker(urlString: String, customTitle: String) {
        guard let normalizedURL = normalizedStickerURL(from: urlString) else { return }

        let displayTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = displayTitle.isEmpty ? stickerHostLabel(from: normalizedURL.absoluteString) : displayTitle
        let hostLabel = stickerHostLabel(from: normalizedURL.absoluteString)
        let resolvedSize = CGSize(width: max(220, min(320, linkStickerRenderingSize(for: resolvedTitle).width + 44)), height: 78)
        let renderer = UIGraphicsImageRenderer(size: resolvedSize)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: resolvedSize)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 24)
            drawStickerAccentPill(
                in: context,
                rect: CGRect(x: 16, y: 19, width: 40, height: 40),
                fillColor: UIColor(red: 0.18, green: 0.66, blue: 0.98, alpha: 1),
                iconSystemName: "link"
            )

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92),
                .paragraphStyle: paragraphStyle
            ]

            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.black.withAlphaComponent(0.48),
                .paragraphStyle: paragraphStyle
            ]

            (resolvedTitle as NSString).draw(
                in: CGRect(x: 70, y: 18, width: resolvedSize.width - 86, height: 20),
                withAttributes: titleAttributes
            )
            (hostLabel as NSString).draw(
                in: CGRect(x: 70, y: 40, width: resolvedSize.width - 86, height: 16),
                withAttributes: subtitleAttributes
            )
        }

        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .link,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                linkURL: normalizedURL.absoluteString,
                linkTitle: resolvedTitle,
                countdownTitle: nil,
                countdownTargetAtMs: nil,
                caption: nil,
                profileImagePath: nil,
                momentId: nil
            )
        )

        selectedStickers.append(sticker)
        dismiss()
    }

    private func createPollSticker(_ poll: [String]) {
        guard poll.count >= 3 else { return }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 172))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 300, height: 172)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 26)

            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92)
            ]
            let questionText = poll[0].count > 44 ? String(poll[0].prefix(44)) + "..." : poll[0]
            questionText.draw(in: CGRect(x: 18, y: 20, width: 264, height: 42), withAttributes: questionAttributes)

            let optionFill = UIColor.black.withAlphaComponent(0.045)
            let optionStroke = UIColor.black.withAlphaComponent(0.08)
            let optionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: UIColor.black.withAlphaComponent(0.88)
            ]

            let option1Rect = CGRect(x: 18, y: 82, width: 264, height: 32)
            let option1Path = UIBezierPath(roundedRect: option1Rect, cornerRadius: 17)
            optionFill.setFill()
            option1Path.fill()
            optionStroke.setStroke()
            option1Path.lineWidth = 1
            option1Path.stroke()

            let option2Rect = CGRect(x: 18, y: 122, width: 264, height: 32)
            let option2Path = UIBezierPath(roundedRect: option2Rect, cornerRadius: 17)
            optionFill.setFill()
            option2Path.fill()
            optionStroke.setStroke()
            option2Path.lineWidth = 1
            option2Path.stroke()

            let option1Text = poll[1].count > 28 ? String(poll[1].prefix(28)) + "..." : poll[1]
            let option2Text = poll[2].count > 28 ? String(poll[2].prefix(28)) + "..." : poll[2]

            option1Text.draw(in: CGRect(x: 32, y: 89, width: 232, height: 18), withAttributes: optionAttributes)
            option2Text.draw(in: CGRect(x: 32, y: 129, width: 232, height: 18), withAttributes: optionAttributes)
        }

        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN (TAMAÑO FIJO )
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .poll,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: poll,
                questionText: nil,
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createQuizSticker(question: String, options: [String], correctIndex: Int) {
        HapticManager.shared.heavyImpact()

        // Renderizamos una versión estática para el editor
        let controller = UIHostingController(rootView: StickerQuizCardView(
            question: question,
            options: options,
            selectedIndex: nil,
            correctIndex: correctIndex,
            onSelect: { _ in }
        ))
        let targetSize = CGSize(width: 300, height: 200) // Tamaño estimado razonable
        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .quiz,
            interactionData: StickerItem.StickerInteractionData(
                quizQuestion: question,
                quizOptions: options,
                quizCorrectIndex: correctIndex
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createFrameSticker(image: UIImage) {
        HapticManager.shared.mediumImpact()

        // ✅ La imagen REAL del usuario se guarda directamente como content (Base64)
        // El visor la recupera vía sticker.image → InteractiveFrameSticker(image:)
        // La vista previa en el editor muestra el marco Polaroid vacío (progress: 0)
        let sticker = StickerItem(
            image: image,   // ← imagen real → se encode a Base64 via extractContent
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .frame,
            interactionData: StickerItem.StickerInteractionData(
                caption: nil,
                quizQuestion: nil,
                frameStyle: "classic"
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createRevealSticker() {
        // ✨ Reveal limit check
        if selectedStickers.contains(where: { $0.type == .reveal }) {
            HapticManager.shared.notification(.error)
            dismiss()
            return
        }

        HapticManager.shared.mediumImpact()

        let image = UIImage(systemName: "eye.slash.fill")?.withTintColor(.white) ?? UIImage()

        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: 100), // Arriba por defecto
            type: .reveal,
            interactionData: StickerItem.StickerInteractionData(
                revealType: "solid",
                revealPattern: "dots",
                revealPrimaryColor: "#000000",
                revealSecondaryColor: "#000000"
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createAudioSticker(audioData: Data, duration: Double) {
        HapticManager.shared.mediumImpact()

        // 1. Guardar el audio en un archivo temporal para que BackgroundStoryUploadService lo pueda subir
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "story_audio_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try audioData.write(to: fileURL)

            // 2. Crear la imagen "Liquid Glass" circular (72x72) para el editor
            let size = CGSize(width: 72, height: 72)
            let renderer = UIGraphicsImageRenderer(size: size)
            let stickerImage = renderer.image { context in
                let rect = CGRect(origin: .zero, size: size)

                // Fondo circular con glassmorphism premium
                let path = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))

                // Sombra suave para elevación
                context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.2).cgColor)

                // Relleno glass ultra-limpio
                UIColor.white.withAlphaComponent(0.25).setFill()
                path.fill()

                // Borde fino brillante (Liquid Glass style)
                let borderPath = UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
                context.cgContext.setLineWidth(1.5)
                UIColor.white.withAlphaComponent(0.6).setStroke()
                borderPath.stroke()

                // Icono de audio (onda) en el centro
                let iconConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
                if let icon = UIImage(systemName: "waveform", withConfiguration: iconConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let iconRect = CGRect(
                        x: (size.width - icon.size.width) / 2,
                        y: (size.height - icon.size.height) / 2,
                        width: icon.size.width,
                        height: icon.size.height
                    )
                    icon.draw(in: iconRect)
                }
            }

            // 3. Crear el StickerItem con los metadatos necesarios
            let sticker = StickerItem(
                id: "audio_\(UUID().uuidString)",
                image: stickerImage,
                position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
                scale: 1.0,
                rotation: .zero,
                gifURL: nil,
                videoURL: nil,
                isAnimated: false,
                type: .audio,
                interactionData: StickerItem.StickerInteractionData(
                    audioURL: fileURL.absoluteString,
                    audioDuration: duration
                )
            )

            selectedStickers.append(sticker)
            dismiss()

        } catch {
            print("❌ Error saving temporary audio: \(error)")
        }
    }


    private func createQuestionSticker(_ question: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 132))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 300, height: 132)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 26)

            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92)
            ]

            let truncatedQuestion = question.count > 48 ? String(question.prefix(48)) + "..." : question
            truncatedQuestion.draw(in: CGRect(x: 18, y: 20, width: 264, height: 42), withAttributes: questionAttributes)

            let responseRect = CGRect(x: 18, y: 88, width: 264, height: 28)
            let responsePath = UIBezierPath(roundedRect: responseRect, cornerRadius: 14)
            UIColor.black.withAlphaComponent(0.05).setFill()
            responsePath.fill()

            let responseAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(red: 0.24, green: 0.46, blue: 0.88, alpha: 0.95)
            ]
            NSLocalizedString("question.tapToAnswer", comment: "Tap to answer")
                .draw(in: CGRect(x: 30, y: 95, width: 240, height: 16), withAttributes: responseAttributes)
        }

        // ✅ CREAR STICKER CON DATOS DE INTERACCIÓN
        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .question,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: question,
                weatherSymbol: nil,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )
        selectedStickers.append(sticker)
        dismiss()
    }

    private func createCountdownSticker(title: String, targetAtMs: Double) {
        let targetDate = Date(timeIntervalSince1970: targetAtMs / 1000)
        let remainingSeconds = max(Int(targetDate.timeIntervalSinceNow), 0)
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60
        let remainingText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 96))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 240, height: 96)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: 22)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            paragraphStyle.alignment = .center

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92),
                .paragraphStyle: paragraphStyle
            ]
            let digitAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92)
            ]
            let colonAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor(red: 0.43, green: 0.16, blue: 0.44, alpha: 1),
                .paragraphStyle: paragraphStyle
            ]

            let titleText = (title as NSString).substring(to: min(title.count, 26))
            (titleText as NSString).draw(in: CGRect(x: 20, y: 14, width: 200, height: 18), withAttributes: titleAttributes)

            let boxSize = CGSize(width: 26, height: 32)
            let digitSpacing: CGFloat = 4
            let colonWidth: CGFloat = 10
            let sequence = remainingText.map(String.init)

            var totalWidth: CGFloat = 0
            for character in sequence {
                totalWidth += character == ":" ? colonWidth : boxSize.width
            }
            totalWidth += CGFloat(max(0, sequence.count - 1)) * digitSpacing

            var currentX = (rect.width - totalWidth) / 2
            let rowY: CGFloat = 44

            for character in sequence {
                if character == ":" {
                    (character as NSString).draw(
                        in: CGRect(x: currentX, y: rowY + 3, width: colonWidth, height: boxSize.height),
                        withAttributes: colonAttributes
                    )
                    currentX += colonWidth + digitSpacing
                } else {
                    let boxRect = CGRect(x: currentX, y: rowY, width: boxSize.width, height: boxSize.height)
                    let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                    UIColor(white: 0.96, alpha: 1).setFill()
                    boxPath.fill()
                    UIColor.black.withAlphaComponent(0.05).setStroke()
                    boxPath.lineWidth = 1
                    boxPath.stroke()

                    (character as NSString).draw(
                        in: CGRect(x: boxRect.minX, y: boxRect.minY + 3, width: boxRect.width, height: 24),
                        withAttributes: digitAttributes.merging([.paragraphStyle: paragraphStyle]) { _, new in new }
                    )
                    currentX += boxSize.width + digitSpacing
                }
            }
        }

        let sticker = StickerItem(
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            type: .countdown,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                linkURL: nil,
                linkTitle: nil,
                countdownTitle: title,
                countdownTargetAtMs: targetAtMs,
                caption: nil,
                profileImagePath: nil,
                momentId: nil
            )
        )

        selectedStickers.append(sticker)
        dismiss()
    }

    private func createEmojiSliderSticker(prompt: String, emoji: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrompt = trimmedPrompt
        let resolvedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "😍" : emoji
        let image = createEmojiSliderFallbackImage(prompt: resolvedPrompt, emoji: resolvedEmoji, value: 0.5)

        let sticker = StickerItem(
            id: UUID().uuidString,
            image: image,
            position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
            scale: 1.0,
            rotation: .zero,
            gifURL: nil,
            videoURL: nil,
            isAnimated: false,
            type: .emojiSlider,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                linkURL: nil,
                linkTitle: nil,
                countdownTitle: nil,
                countdownTargetAtMs: nil,
                sliderEmoji: resolvedEmoji,
                sliderPrompt: resolvedPrompt,
                caption: nil,
                profileImagePath: nil,
                momentId: nil
            )
        )

        selectedStickers.append(sticker)
        dismiss()
    }
}
