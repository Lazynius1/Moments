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
    @Environment(\.dismiss) private var dismiss
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
                .onChange(of: photoPickerItem) { newItem in
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
            let rect = CGRect(x: 0, y: 0, width: 200, height: 200)

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
    private func constrainPositionToBounds(_ position: CGPoint) -> CGPoint {
        let padding: CGFloat = 60
        let bounds = UIScreen.main.bounds

        return CGPoint(
            x: max(padding, min(bounds.width - padding, position.x)),
            y: max(padding, min(bounds.height - padding, position.y))
        )
    }

    private func drawStickerCardBackground(
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

    private func drawStickerAccentPill(
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





    // MARK: - ✅ WEATHER STICKER
    private func createWeatherSticker() {
        // ✅ OBTENER CLIMA ACTUAL CON WEATHER KIT
        Task {
            do {
                let weather = try await getCurrentWeather()
                await MainActor.run {
                    createWeatherStickerWithData(weather)
                }
            } catch {
                // ✅ FALLBACK: Crear sticker con placeholder
                await MainActor.run {
                    createWeatherStickerWithPlaceholder()
                }
            }
        }
    }

    // ✅ FUNCIÓN PARA OBTENER CLIMA ACTUAL
    private func getCurrentWeather() async throws -> (temperature: Double, condition: String, symbol: String) {
        let locationManager = CLLocationManager()

        // ✅ VERIFICAR PERMISOS
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            throw WeatherError.noLocationPermission
        }

        // ✅ OBTENER UBICACIÓN ACTUAL
        guard let location = locationManager.location else {
            throw WeatherError.noLocation
        }

        // ✅ USAR WEATHERSERVICE EXISTENTE
        let weatherService = WeatherService.shared
        let currentWeather = try await weatherService.getWeather(for: location.coordinate)

        let temperature = currentWeather.temperature
        let condition = currentWeather.condition.displayName
        let symbol = getWeatherSymbol(for: condition)

        return (temperature: temperature, condition: condition, symbol: symbol)
    }

    // ✅ CONVERTIR CONDICIÓN A SÍMBOLO (MEJORADO CON HORA DEL DÍA)
    private func getWeatherSymbol(for condition: String) -> String {
        let lowercased = condition.lowercased()
        let hour = Calendar.current.component(.hour, from: Date())

        // ✅ DETECTAR SI ES NOCHE (entre 20:00 y 6:00)
        let isNight = hour >= 20 || hour < 6

        if lowercased.contains("clear") || lowercased.contains("sunny") {
            return isNight ? "🌙" : "☀️"
        } else if lowercased.contains("cloud") {
            return isNight ? "☁️" : "🌤️"
        } else if lowercased.contains("rain") || lowercased.contains("drizzle") {
            return "🌧️"
        } else if lowercased.contains("snow") || lowercased.contains("sleet") {
            return "❄️"
        } else if lowercased.contains("storm") || lowercased.contains("thunder") {
            return "⛈️"
        } else if lowercased.contains("fog") || lowercased.contains("haze") {
            return "🌫️"
        } else if lowercased.contains("wind") || lowercased.contains("breeze") {
            return "💨"
        } else if lowercased.contains("hot") {
            return "🔥"
        } else if lowercased.contains("cold") {
            return "🥶"
        } else {
            return isNight ? "🌙" : "🌤️"
        }
    }

    // ✅ CREAR STICKER CON DATOS REALES
    private func createWeatherStickerWithData(_ weather: (temperature: Double, condition: String, symbol: String)) {
        let temperature = Int(round(weather.temperature))
        let weatherText = "\(temperature)°C"



        // ✅ CREAR STICKER ANIMADO
        let sticker = StickerItem(
            image: createWeatherBackgroundImage(for: weather.symbol),
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .weather,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: weatherText,
                weatherSymbol: weather.symbol,
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )



        selectedStickers.append(sticker)

        dismiss()
    }

    // ✅ CREAR IMAGEN DE FONDO PARA ANIMACIÓN
    private func createWeatherBackgroundImage(for symbol: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 140, height: 50)

            // ✅ FONDO CON GRADIENTE SEGÚN CLIMA
            // ✅ FONDO CON GRADIENTE SEGÚN CLIMA
            let colors = getWeatherGradientColors(for: symbol)

            let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
            context.cgContext.saveGState()
            path.addClip()

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            } else {
                UIColor.systemBlue.setFill()
                context.fill(rect)
            }
            context.cgContext.restoreGState()

            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()

            // ✅ TEXTO CENTRADO (solo símbolo del clima)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]

            symbol.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
        }

        return image
    }

    // ✅ CREAR STICKER CON PLACEHOLDER
    private func createWeatherStickerWithPlaceholder() {
        let weatherText = "🌤️"



        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 140, height: 50)

            // ✅ FONDO AZUL POR DEFECTO
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor
            ] as CFArray

            let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
            context.cgContext.saveGState()
            path.addClip()

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            } else {
                UIColor.systemBlue.setFill()
                context.fill(rect)
            }
            context.cgContext.restoreGState()

            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()

            // ✅ TEXTO CENTRADO
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]

            weatherText.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
        }

        let sticker = StickerItem(
            image: image,
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .weather,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: weatherText,
                weatherSymbol: "🌤️",
                caption: nil,
                profileImagePath: nil, momentId: nil
            )
        )

        selectedStickers.append(sticker)
        dismiss()
    }

    // ✅ OBTENER COLORES DE GRADIENTE SEGÚN CLIMA
    private func getWeatherGradientColors(for symbol: String) -> CFArray {
        switch symbol {
        case "☀️": // Soleado
            return [
                UIColor.systemOrange.withAlphaComponent(0.9).cgColor,
                UIColor.systemYellow.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🌧️", "⛈️": // Lluvia/Tormenta
            return [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemIndigo.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "❄️", "🌨️": // Nieve
            return [
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "☁️", "⛅": // Nublado
            return [
                UIColor.systemGray.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🔥": // Calor
            return [
                UIColor.systemRed.withAlphaComponent(0.9).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.9).cgColor
            ] as CFArray
        case "🥶": // Frío
            return [
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor
            ] as CFArray
        default: // Por defecto
            return [
                UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                UIColor.systemCyan.withAlphaComponent(0.9).cgColor
            ] as CFArray
        }
    }

    // ✅ ENUM PARA ERRORES DE CLIMA
    enum WeatherError: Error {
        case noLocationPermission
        case noLocation
        case unsupportedVersion
    }

    // MARK: - ✅ TIME STICKER
    private func createTimeSticker() {
        let now = Date()

        // ✅ FORMATO: "14:30" (Hora) + "7 Ago" (Fecha)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.locale = Locale(identifier: "es_ES")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM"
        dateFormatter.locale = Locale(identifier: "es_ES")

        let timeString = timeFormatter.string(from: now)
        let dateString = dateFormatter.string(from: now)

        let width: CGFloat = 164
        let height: CGFloat = 56
        let cornerRadius: CGFloat = 22

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            drawStickerCardBackground(in: context, rect: rect, cornerRadius: cornerRadius)

            drawStickerAccentPill(
                in: context,
                rect: CGRect(x: 14, y: 14, width: 28, height: 28),
                fillColor: UIColor(red: 0.18, green: 0.66, blue: 0.98, alpha: 1),
                iconSystemName: "clock.fill"
            )

            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.92)
            ]

            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.black.withAlphaComponent(0.48)
            ]

            timeString.draw(in: CGRect(x: 52, y: 12, width: 92, height: 20), withAttributes: timeAttributes)
            dateString.draw(in: CGRect(x: 52, y: 31, width: 92, height: 14), withAttributes: dateAttributes)
        }

        let sticker = StickerItem(
            image: image,
            position: constrainPositionToBounds(CGPoint(
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
            )),
            type: .time,
            interactionData: StickerItem.StickerInteractionData(
                username: nil,
                userId: nil,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: timeString, // ✅ Guardamos la hora para el visor
                weatherSymbol: nil,
                caption: dateString, // ✅ Guardamos la fecha para el visor
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

struct StickerPillFlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 14

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = makeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + max(0, CGFloat(rows.count - 1) * rowSpacing)

        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY

        for (index, row) in rows.enumerated() {
            let rowWidth = row.items.reduce(CGFloat.zero) { result, item in
                result + item.size.width
            } + max(0, CGFloat(row.items.count - 1) * spacing)

            let centeredX = bounds.minX + max(0, (bounds.width - rowWidth) / 2)
            let rowShift: CGFloat
            switch index % 4 {
            case 0:
                rowShift = 0
            case 1:
                rowShift = 8
            case 2:
                rowShift = -6
            default:
                rowShift = 4
            }
            let currentRowY = currentY + (index.isMultiple(of: 2) ? 0 : 2)
            var currentX = min(
                max(bounds.minX, centeredX + rowShift),
                bounds.maxX - rowWidth
            )

            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: currentX, y: currentRowY + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                currentX += item.size.width + spacing
            }

            currentY += row.height + rowSpacing
        }
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard maxWidth > 0 else { return [] }

        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if proposedWidth > maxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [FlowItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(subview: subview, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }
}

private struct StickerEmojiSliderPillGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let normalized = (sin(t * 1.8) + 1) / 2
            let progress = 0.10 + (normalized * 0.80)

            GeometryReader { geometry in
                let size = geometry.size
                let trackHeight: CGFloat = 5
                let emojiSize: CGFloat = 19 + CGFloat(progress * 8)
                let horizontalInset: CGFloat = 3
                let trackWidth = max(size.width - emojiSize - (horizontalInset * 2), 12)
                let trackX = horizontalInset + (emojiSize / 2)
                let trackY = (size.height - trackHeight) / 2
                let emojiX = trackX + (trackWidth * progress) - (emojiSize / 2)
                let emojiY = (size.height - emojiSize) / 2

                ZStack(alignment: .topLeading) {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.10))
                        .frame(width: trackWidth, height: trackHeight)
                        .offset(x: trackX, y: trackY)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: emojiSliderMomentsGradientColors(),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(trackWidth * progress, trackHeight), height: trackHeight)
                        .offset(x: trackX, y: trackY)

                    Text("😍")
                        .font(.system(size: 15 + CGFloat(progress * 5)))
                        .frame(width: emojiSize, height: emojiSize)
                        .shadow(color: Color.black.opacity(0.14), radius: 3, y: 1)
                        .offset(x: emojiX, y: emojiY)
                }
            }
        }
    }
}



struct SmartLocationInputView: View {
    let onSelect: (String, CLLocationCoordinate2D?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var nearbyPlaces: [LocationResult] = []
    @State private var searchResults: [LocationResult] = []
    @State private var isLoadingNearby = true
    @State private var isSearching = false
    @State private var userLocation: CLLocation?
    @FocusState private var isTextFieldFocused: Bool

    @StateObject private var locationManager = LocationManager()

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    // Modelo para resultados de ubicación
    struct LocationResult: Identifiable, Hashable, Equatable {
        let id = UUID()
        let displayName: String // ✅ NOMBRE PARA MOSTRAR EN LA UI
        let fullName: String // ✅ NOMBRE COMPLETO PARA PRECISIÓN
        let address: String
        let distance: Double? // En metros
        let category: String
        let coordinate: CLLocationCoordinate2D

        var distanceString: String {
            guard let distance = distance else { return "" }
            if distance < 1000 {
                return "\(Int(distance))m"
            } else {
                return String(format: "%.1fkm", distance / 1000)
            }
        }

        var categoryIcon: String {
            switch category.lowercased() {
            case "restaurant", "food": return "fork.knife"
            case "shopping", "store": return "bag"
            case "entertainment": return "theatermasks"
            case "gas station": return "fuelpump"
            case "hospital": return "cross.case"
            case "school": return "graduationcap"
            case "park": return "tree"
            case "gym": return "dumbbell"
            case "hotel": return "bed.double"
            default: return "mappin"
            }
        }

        // MARK: - Conformance to Equatable
        static func == (lhs: LocationResult, rhs: LocationResult) -> Bool {
            return lhs.id == rhs.id &&
                   lhs.displayName == rhs.displayName &&
                   lhs.fullName == rhs.fullName &&
                   lhs.address == rhs.address &&
                   lhs.distance == rhs.distance &&
                   lhs.category == rhs.category &&
                   lhs.coordinate.latitude == rhs.coordinate.latitude &&
                   lhs.coordinate.longitude == rhs.coordinate.longitude
        }

        // MARK: - Conformance to Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(displayName)
            hasher.combine(fullName)
            hasher.combine(address)
            hasher.combine(distance)
            hasher.combine(category)
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("stickerview.location.searchTitle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(palette.primaryText)

                        Text("stickerview.location.searchSubtitle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(palette.secondaryText)
                    }

                    Spacer()

                    if locationManager.authorizationStatus == .authorizedWhenInUse ||
                        locationManager.authorizationStatus == .authorizedAlways {
                        Button(action: {
                            refreshLocationAndPlaces()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("stickerview.location.refresh")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(palette.buttonFill)
                                    .overlay(Capsule().stroke(palette.fieldStroke, lineWidth: 1))
                            )
                        }
                        .disabled(isLoadingNearby)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: isSearching ? "magnifyingglass" : (searchText.isEmpty ? "magnifyingglass" : "location.magnifyingglass"))
                        .font(.system(size: 16))
                        .foregroundColor(searchText.isEmpty ? palette.searchIcon : palette.searchIconActive)
                        .animation(.easeInOut(duration: 0.2), value: searchText)

                    TextField(NSLocalizedString("stickerview.location.searchPlaceholder", comment: "Location search placeholder"), text: $searchText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                            } else {
                                searchPlaces(query: newValue)
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                searchResults = []
                                isSearching = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(palette.clearIcon)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule())
            }
            .padding(.bottom, 20)

            // Lista de ubicaciones
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Ubicaciones cercanas
                        if isLoadingNearby {
                            SectionHeader(title: NSLocalizedString("stickerview.location.searchingNearby", comment: "Searching nearby places"), icon: "location", color: .blue)

                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if nearbyPlaces.isEmpty {
                            EmptyNearbyView()
                        } else {
                            SectionHeader(title: NSLocalizedString("stickerview.location.nearby", comment: "Nearby places"), icon: "location.fill", color: .red)

                            ForEach(nearbyPlaces, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    } else {
                        // Resultados de búsqueda
                        if isSearching {
                            SectionHeader(title: NSLocalizedString("stickerview.location.searching", comment: "Searching"), icon: "magnifyingglass", color: .blue)

                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonLocationRow()
                            }
                        } else if searchResults.isEmpty {
                            EmptySearchView(searchQuery: searchText)
                        } else {
                            SectionHeader(
                                title: searchResults.count == 1
                                    ? String(format: NSLocalizedString("stickerview.location.results.one", comment: "One location result"), searchResults.count)
                                    : String(format: NSLocalizedString("stickerview.location.results.other", comment: "Multiple location results"), searchResults.count),
                                icon: "mappin.and.ellipse",
                                color: .green
                            )

                            ForEach(searchResults, id: \.id) { place in
                                LocationRowView(location: place) {
                                    onSelect(place.displayName, place.coordinate)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: searchText)
                .animation(.easeInOut(duration: 0.3), value: searchResults)
                .animation(.easeInOut(duration: 0.3), value: nearbyPlaces)
                .padding(.horizontal, 4)
            }
        }
        .onAppear {
            isTextFieldFocused = true
            requestLocationAndSearch()
        }
        .onChange(of: locationManager.location) { newLocation in
            if let location = newLocation {
                userLocation = location
                searchNearbyPlaces()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                requestLocationAndSearch()
            }
        }
        .onDisappear {
            // Limpiar memoria al cerrar la vista
            cleanupMemory()
        }
    }

    // MARK: - Componentes de UI

    private struct LocationRowView: View {
        let location: SmartLocationInputView.LocationResult
        let onTap: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: location.categoryIcon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: 20, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(palette.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(location.address)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(palette.secondaryText)
                                .lineLimit(1)

                            if !location.distanceString.isEmpty {
                                Text("• \(location.distanceString)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(palette.tertiaryText)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.tertiaryText)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private struct SkeletonLocationRow: View {
        @State private var isAnimating = false
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            HStack(spacing: 14) {
                Circle()
                    .fill(palette.skeletonFill)
                    .frame(width: 44, height: 44)
                    .shimmer(isAnimating)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.skeletonFill)
                        .frame(width: 140, height: 14)
                        .shimmer(isAnimating)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.skeletonFill)
                        .frame(width: 100, height: 12)
                        .shimmer(isAnimating)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .onAppear {
                isAnimating = true
            }
        }
    }

    private struct EmptyNearbyView: View {
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "location.slash")
                    .font(.system(size: 40))
                    .foregroundColor(palette.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("stickerview.nearbyPlacesError")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.primaryText)

                    Text("stickerview.locationPermissionError")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(.horizontal, 4)
        }
    }

    private struct EmptySearchView: View {
        let searchQuery: String
        @Environment(\.colorScheme) private var colorScheme

        private var palette: StickerDetailPalette {
            StickerDetailPalette(colorScheme: colorScheme)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 40))
                    .foregroundColor(palette.secondaryText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("stickerview.noPlacesFound")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.primaryText)

                    Text(String(format: NSLocalizedString("stickerview.tryDifferentSearch", comment: "Try different search"), searchQuery))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 40)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Funciones de búsqueda

    private func requestLocationAndSearch() {
        locationManager.requestLocation()
    }

    private func refreshLocationAndPlaces() {
        // Recargar ubicación y lugares cercanos
        isLoadingNearby = true
        locationManager.requestLocation()

        // Si ya tenemos ubicación, recargar lugares cercanos inmediatamente
        if let currentLocation = locationManager.location {
            userLocation = currentLocation
            searchNearbyPlaces()
        }
    }

    private func searchNearbyPlaces() {
        guard let userLocation = userLocation else { return }

        isLoadingNearby = true

        // Búsqueda más específica para lugares útiles (como en LocationPickerView)
        let searchQueries = [
            NSLocalizedString("stickerview.location.query.restaurants", comment: "Nearby restaurants query"),
            NSLocalizedString("stickerview.location.query.cafes", comment: "Nearby cafes query"),
            NSLocalizedString("stickerview.location.query.shops", comment: "Nearby shops query"),
            NSLocalizedString("stickerview.location.query.parks", comment: "Nearby parks query"),
            NSLocalizedString("stickerview.location.query.museums", comment: "Nearby museums query"),
            NSLocalizedString("stickerview.location.query.hotels", comment: "Nearby hotels query"),
            NSLocalizedString("stickerview.location.query.pharmacies", comment: "Nearby pharmacies query"),
            NSLocalizedString("stickerview.location.query.banks", comment: "Nearby banks query"),
            NSLocalizedString("stickerview.location.query.metroStations", comment: "Nearby metro stations query"),
            NSLocalizedString("stickerview.location.query.libraries", comment: "Nearby libraries query")
        ]

        var allPlaces: [LocationResult] = []
        let group = DispatchGroup()

        // Limitar a 4 búsquedas simultáneas para reducir memoria
        for query in searchQueries.prefix(4) {
            group.enter()

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 1500, // Reducir radio a 1.5km
                longitudinalMeters: 1500
            )
            request.resultTypes = .pointOfInterest

            let search = MKLocalSearch(request: request)
            search.start { response, error in
                defer { group.leave() }

                if let response = response {
                    let places: [LocationResult] = response.mapItems.prefix(2).compactMap { item in // Máximo 2 por categoría
                        guard let name = item.name else { return nil }

                        let distance = userLocation.distance(from: CLLocation(
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude
                        ))

                        let fullAddress = formatAddress(item.placemark)
                        let fullName = "\(name), \(fullAddress)"

                        return LocationResult(
                            displayName: name,
                            fullName: fullName,
                            address: fullAddress,
                            distance: distance,
                            category: item.pointOfInterestCategory?.rawValue ?? "place",
                            coordinate: item.placemark.coordinate
                        )
                    }

                    DispatchQueue.main.async {
                        allPlaces.append(contentsOf: places)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            // Filtrar duplicados manualmente y ordenar por distancia
            var uniquePlaces: [LocationResult] = []
            var seenCoordinates: Set<String> = []

            for place in allPlaces {
                let coordinateKey = "\(place.coordinate.latitude),\(place.coordinate.longitude)"
                if !seenCoordinates.contains(coordinateKey) {
                    seenCoordinates.insert(coordinateKey)
                    uniquePlaces.append(place)
                }
            }

            let sortedPlaces = uniquePlaces.sorted { $0.distance ?? 0 < $1.distance ?? 0 }
            self.nearbyPlaces = Array(sortedPlaces.prefix(12)) // 12 lugares totales
            self.isLoadingNearby = false

            // Limpiar memoria
            allPlaces.removeAll()
        }
    }

    private func searchPlaces(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let userLocation = userLocation {
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 5000, // Reducir radio a 5km para ahorrar memoria
                longitudinalMeters: 5000
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isSearching = false

                guard let response = response else {
                    self.searchResults = []
                    return
                }

                // Ordenamiento inteligente por relevancia y distancia
                let sortedResults: [LocationResult] = response.mapItems.prefix(15).compactMap { item in
                    guard let name = item.name else { return nil }

                    let distance = self.userLocation?.distance(from: CLLocation(
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    ))

                    let fullAddress = formatAddress(item.placemark)
                    let fullName = "\(name), \(fullAddress)"

                    return LocationResult(
                        displayName: name,
                        fullName: fullName,
                        address: fullAddress,
                        distance: distance,
                        category: item.pointOfInterestCategory?.rawValue ?? "place",
                        coordinate: item.placemark.coordinate
                    )
                }.sorted { item1, item2 in
                    // Priorizar lugares con nombre
                    let hasName1 = !item1.displayName.isEmpty
                    let hasName2 = !item2.displayName.isEmpty

                    if hasName1 != hasName2 {
                        return hasName1
                    }

                    // Si ambos tienen nombre, priorizar por tipo (POI primero)
                    if hasName1 && hasName2 {
                        let isPOI1 = item1.category != "place"
                        let isPOI2 = item2.category != "place"
                        if isPOI1 != isPOI2 {
                            return isPOI1
                        }
                    }

                    // Finalmente, ordenar por distancia
                    return (item1.distance ?? Double.greatestFiniteMagnitude) < (item2.distance ?? Double.greatestFiniteMagnitude)
                }

                self.searchResults = sortedResults
            }
        }
    }

    private func cleanupMemory() {
        // Limpiar arrays para liberar memoria
        nearbyPlaces.removeAll()
        searchResults.removeAll()
        searchText = ""
        isSearching = false
        isLoadingNearby = false
    }

    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        // ✅ NÚMERO Y CALLE
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        // ✅ CÓDIGO POSTAL
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }

        // ✅ CIUDAD
        if let locality = placemark.locality {
            components.append(locality)
        }

        // ✅ PROVINCIA/ESTADO
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }

        // ✅ PAÍS
        if let country = placemark.country {
            components.append(country)
        }

        return components.joined(separator: ", ")
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

private struct StickerDetailPalette {
    let colorScheme: ColorScheme

    var primaryText: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.92)
    }

    var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color.black.opacity(0.50)
    }

    var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.40) : Color.black.opacity(0.34)
    }

    var searchIcon: Color {
        colorScheme == .dark ? .white.opacity(0.54) : Color.black.opacity(0.36)
    }

    var searchIconActive: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color.black.opacity(0.66)
    }

    var clearIcon: Color {
        colorScheme == .dark ? .white.opacity(0.56) : Color.black.opacity(0.34)
    }

    var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var fieldStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    var buttonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var divider: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var skeletonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}

// MARK: - Modern Mention Input with Real User Search
struct ModernMentionInputView: View {
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var recentUsers: [AppUser] = []
    @State private var suggestedUsers: [AppUser] = []
    @FocusState private var isTextFieldFocused: Bool

    private let firestoreService = FirestoreService()

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("stickerview.mention.searchTitle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(palette.primaryText)

                    Text("stickerview.mention.searchSubtitle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.secondaryText)
                }

                HStack(spacing: 12) {
                    Image(systemName: isSearching ? "magnifyingglass" : (searchText.isEmpty ? "magnifyingglass" : "person.circle.fill"))
                        .font(.system(size: 16))
                        .foregroundColor(searchText.isEmpty ? palette.searchIcon : palette.searchIconActive)
                        .animation(.easeInOut(duration: 0.2), value: searchText)

                    TextField(NSLocalizedString("stickerview.mention.searchPlaceholder", comment: "Mention search placeholder"), text: $searchText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { newValue in
                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                            } else {
                                searchUsers(query: newValue)
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchText = ""
                                searchResults = []
                                isSearching = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(palette.clearIcon)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule())
            }
            .padding(.bottom, 20)

            // Lista de usuarios
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Sección de recientes
                        if !recentUsers.isEmpty {
                            SectionHeader(title: NSLocalizedString("stickerview.mention.recent", comment: "Recent users"), icon: "clock.fill", color: .orange)

                            ForEach(recentUsers, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }

                            Divider()
                                .background(palette.divider)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 16)
                        }

                        // Sección de sugerencias
                        if !suggestedUsers.isEmpty {
                            SectionHeader(title: NSLocalizedString("stickerview.mention.suggestions", comment: "Suggested users"), icon: "sparkles", color: .purple)

                            ForEach(suggestedUsers, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        } else {
                            // Loading de sugerencias
                            SectionHeader(title: NSLocalizedString("stickerview.mention.suggestions", comment: "Suggested users"), icon: "sparkles", color: .purple)

                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonUserRow()
                            }
                        }
                    } else {
                        // Resultados de búsqueda
                        if isSearching {
                            SectionHeader(title: NSLocalizedString("stickerview.mention.searching", comment: "Searching users"), icon: "magnifyingglass", color: .blue)

                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonUserRow()
                            }
                        } else if searchResults.isEmpty {
                            StickerEmptySearchView(searchQuery: searchText)
                        } else {
                            SectionHeader(
                                title: searchResults.count == 1
                                    ? String(format: NSLocalizedString("stickerview.mention.results.one", comment: "One mention result"), searchResults.count)
                                    : String(format: NSLocalizedString("stickerview.mention.results.other", comment: "Multiple mention results"), searchResults.count),
                                icon: "person.2.fill",
                                color: .green
                            )

                            ForEach(searchResults, id: \.id) { user in
                                StickerUserRowView(user: user) {
                                    saveRecentUser(user)
                                    onSelect(user.username)
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: searchText)
                .animation(.easeInOut(duration: 0.3), value: searchResults)
                .padding(.horizontal, 4)
            }
        }
                        .onAppear {
            loadRecentUsers()
            loadSuggestedUsers()
            isTextFieldFocused = true
        }
    }

    // MARK: - Private Methods
    private func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        // Debounce la búsqueda
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.searchText == query { // Solo buscar si no ha cambiado
                self.performUserSearch(query: query)
            }
        }
    }

    private func performUserSearch(query: String) {
        firestoreService.searchUsers(query: query.lowercased(), limit: 15) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    // Filtrar al usuario actual y ordenar por relevancia
                    self.searchResults = users
                        .filter { $0.id != Auth.auth().currentUser?.uid }
                        .sorted { user1, user2 in
                            // Priorizar usuarios Plus y después por username
                            if user1.isPlusSubscriber && !user2.isPlusSubscriber {
                                return true
                            } else if !user1.isPlusSubscriber && user2.isPlusSubscriber {
                                return false
                            }
                            return user1.username < user2.username
                        }
                case .failure(let error):
                    self.searchResults = []
                }
                self.isSearching = false
            }
        }
    }

    private func loadRecentUsers() {
        // Cargar usuarios recientes desde UserDefaults o Core Data
        if let data = UserDefaults.standard.data(forKey: "recentMentionedUsers"),
           let userIds = try? JSONDecoder().decode([String].self, from: data) {

            // Cargar detalles de usuarios
            let group = DispatchGroup()
            var users: [AppUser] = []

            for userId in userIds.prefix(5) {
                group.enter()
                firestoreService.fetchUserProfile(userId: userId) { result in
                    if case .success(let user) = result {
                        users.append(user)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.recentUsers = users
            }
        }
    }

    private func loadSuggestedUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Cargar usuarios sugeridos (conexiones mutuas, etc.)
        firestoreService.fetchMutualConnections(userId: currentUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let connections):
                    self.suggestedUsers = Array(connections.prefix(6))
                case .failure(_):
                    self.suggestedUsers = []
                }
            }
        }
    }

    private func saveRecentUser(_ user: AppUser) {
        var recentIds = [String]()

        if let data = UserDefaults.standard.data(forKey: "recentMentionedUsers"),
           let existingIds = try? JSONDecoder().decode([String].self, from: data) {
            recentIds = existingIds.filter { $0 != user.id }
        }

        recentIds.insert(user.id, at: 0)
        recentIds = Array(recentIds.prefix(10)) // Mantener solo 10 recientes

        if let data = try? JSONEncoder().encode(recentIds) {
            UserDefaults.standard.set(data, forKey: "recentMentionedUsers")
        }
    }
}

// MARK: - Supporting Views
struct StickerUserRowView: View {
    let user: AppUser
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var imageLoadFailed = false

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar con mejor handling de errores
                Group {
                    if let imagePath = user.profileImagePath, !imagePath.isEmpty, !imageLoadFailed {
                        KFImage(URL(string: imagePath))
                            .onFailure { _ in
                                imageLoadFailed = true
                            }
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Text(String(user.username.prefix(1)).uppercased())
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(palette.divider, lineWidth: 0.5)
                )

                // Info del usuario
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(user.username)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(palette.primaryText)

                        // Badge de Plus subscriber si aplica
                        if user.isPlusSubscriber {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                        }
                    }

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(palette.secondaryText)
                            .lineLimit(1)
                    }

                    // Mostrar si es cuenta privada
                    if user.isPrivate {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(palette.tertiaryText)

                            Text("stickerview.privateAccount")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(palette.tertiaryText)
                        }
                    }
                }

                Spacer()

                // Flecha de selección
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.tertiaryText)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SkeletonUserRow: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(palette.skeletonFill)
                .frame(width: 50, height: 50)
                .shimmer(isAnimating)

            // Text skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.skeletonFill)
                    .frame(width: 120, height: 14)
                    .shimmer(isAnimating)

                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.skeletonFill)
                    .frame(width: 80, height: 12)
                    .shimmer(isAnimating)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .onAppear {
            isAnimating = true
        }
    }
}

struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let color: Color

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(palette.primaryText)

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.bottom, 4)
    }
}

struct StickerEmptySearchView: View {
    let searchQuery: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(palette.secondaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("stickerview.noUsersFound")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text(String(format: NSLocalizedString("stickerview.tryDifferentUsername", comment: "Try different username"), searchQuery.lowercased()))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(palette.secondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
        .padding(.horizontal, 4)
    }
}

// MARK: - Shimmer Effect Extension
extension View {
    func shimmer(_ isAnimating: Bool) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: isAnimating ? 200 : -200)
                .animation(
                    Animation.linear(duration: 1.2)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        )
        .clipped()
    }
}

// MARK: - No necesitas extensión - ya tienes las funciones en FirestoreService
// fetchMutualConnections, fetchUserProfile, searchUsers ya existen

struct ModernHashtagInputView: View {
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hashtag = ""
    @FocusState private var isTextFieldFocused: Bool

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.addHashtag")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.hashtag.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 15) {
                HStack {
                    Text("#")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.pink)
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.hashtag.placeholder", comment: "Hashtag placeholder"), text: $hashtag)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($isTextFieldFocused)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextFieldFocused ? Color.pink : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                // Botón de acción
                Button(action: {
                    onSelect(hashtag)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.addHashtag")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(hashtag.isEmpty ? Color.gray.opacity(0.3) : Color.pink)
                    )
                }
                .disabled(hashtag.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: hashtag.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

struct ModernLinkInputView: View {
    let onSelect: (String, String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var urlString = ""
    @State private var customTitle = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case url
        case title
    }

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    private var isFormValid: Bool {
        normalizedStickerURL(from: urlString) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.addLink")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.link.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "link")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.29, green: 0.72, blue: 0.98))
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.link.urlPlaceholder", comment: "Link URL placeholder"), text: $urlString)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .url)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == .url ? Color(red: 0.29, green: 0.72, blue: 0.98) : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                HStack {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 0.29, green: 0.72, blue: 0.98))
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.link.titlePlaceholder", comment: "Link title placeholder"), text: $customTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($focusedField, equals: .title)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == .title ? Color(red: 0.29, green: 0.72, blue: 0.98) : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                Button(action: {
                    onSelect(urlString, customTitle)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.addLink")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFormValid ? Color(red: 0.29, green: 0.72, blue: 0.98) : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!isFormValid)
                .animation(.easeInOut(duration: 0.2), value: isFormValid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusedField = .url
        }
    }
}

struct ModernCountdownInputView: View {
    let onSelect: (String, Double) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var targetDate = Date().addingTimeInterval(3600)
    @FocusState private var isTextFieldFocused: Bool

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetDate.timeIntervalSinceNow > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.createCountdown")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.countdown.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.61, green: 0.34, blue: 0.97))
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.countdown.titlePlaceholder", comment: "Countdown title placeholder"), text: $title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextFieldFocused ? Color(red: 0.61, green: 0.34, blue: 0.97) : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("stickerview.countdown.endsLabel")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(palette.secondaryText)
                        .kerning(1)

                    DatePicker(
                        "",
                        selection: $targetDate,
                        in: Date().addingTimeInterval(60)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Color(red: 0.61, green: 0.34, blue: 0.97))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(palette.fieldFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(palette.fieldStroke, lineWidth: 1.5)
                            )
                    )
                }

                Button(action: {
                    onSelect(title, targetDate.timeIntervalSince1970 * 1000)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.createCountdown")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFormValid ? Color(red: 0.61, green: 0.34, blue: 0.97) : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!isFormValid)
                .animation(.easeInOut(duration: 0.2), value: isFormValid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

struct ModernEmojiSliderInputView: View {
    let onSelect: (String, String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var prompt = ""
    @State private var selectedEmoji = "😍"
    @State private var isEmojiPickerExpanded = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case prompt
    }

    private let presetEmojis = ["😍", "🔥", "😂", "🥹", "🤩", "😮", "😢", "👏", "💯", "🤯"]

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    private var resolvedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedEmoji: String {
        selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "😍" : selectedEmoji
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.createEmojiSlider")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.emojiSlider.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.99, green: 0.56, blue: 0.21))
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.emojiSlider.promptPlaceholder", comment: "Emoji slider prompt placeholder"), text: $prompt)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($focusedField, equals: .prompt)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == .prompt ? Color(red: 0.99, green: 0.56, blue: 0.21) : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presetEmojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            HapticManager.shared.lightImpact()
                        } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(palette.fieldFill)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        selectedEmoji == emoji ? Color(red: 0.99, green: 0.56, blue: 0.21) : palette.fieldStroke,
                                                        lineWidth: selectedEmoji == emoji ? 2 : 1
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                isEmojiPickerExpanded.toggle()
                            }
                            HapticManager.shared.lightImpact()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(palette.primaryText)
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(palette.fieldFill)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    (isEmojiPickerExpanded || !presetEmojis.contains(selectedEmoji))
                                                    ? Color(red: 0.99, green: 0.56, blue: 0.21)
                                                    : palette.fieldStroke,
                                                    lineWidth: (isEmojiPickerExpanded || !presetEmojis.contains(selectedEmoji)) ? 2 : 1
                                                )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }

                if isEmojiPickerExpanded {
                    StickerEmojiPalettePicker(selectedEmoji: $selectedEmoji) { emoji in
                        selectedEmoji = emoji
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isEmojiPickerExpanded = false
                        }
                        HapticManager.shared.lightImpact()
                    }
                }

                StickerEmojiSliderCardView(
                    prompt: resolvedPrompt,
                    emoji: resolvedEmoji,
                    value: 0.5
                )
                .frame(width: emojiSliderRenderingSize(prompt: resolvedPrompt).width, height: emojiSliderRenderingSize(prompt: resolvedPrompt).height)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

                Button(action: {
                    onSelect(resolvedPrompt, resolvedEmoji)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "face.smiling.inverse")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.createEmojiSlider")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.99, green: 0.56, blue: 0.21))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusedField = .prompt
        }
    }
}
struct ModernQuizInputView: View {
    let onSelect: (String, [String], Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @State private var options = ["", "", ""]
    @State private var correctIndex = 0
    @FocusState private var focusedField: Int?

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("quiz.title", comment: ""))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(isDarkMode ? .white : .black)

                Text(NSLocalizedString("quiz.subtitle", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDarkMode ? .white.opacity(0.6) : .black.opacity(0.5))
            }
            .padding(.bottom, 10)

            // Campo de Pregunta
            VStack(alignment: .leading, spacing: 10) {
                TextField(NSLocalizedString("quiz.question.placeholder", comment: ""), text: $question)
                    .font(.system(size: 18, weight: .bold))
                    .padding()
                    .background(Color.white.opacity(isDarkMode ? 0.1 : 0.05))
                    .cornerRadius(16)
                    .focused($focusedField, equals: -1)

                // Opciones dinámicas
                ForEach(0..<options.count, id: \.self) { index in
                    quizOptionField(index: index)
                }

                // ✅ BOTÓN PARA AÑADIR OPCIÓN EXTRA (Máximo 4) - Liquid Glass Style
                if options.count < 4 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            options.append("")
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(NSLocalizedString("quiz.addOption", comment: ""))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(isDarkMode ? .white : .black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            Color.clear.liquidGlass(in: Capsule(), interactive: true)
                        )
                    }
                    .padding(.top, 4)
                }
            }

            Button(action: {
                let filledOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !question.isEmpty && filledOptions.count >= 2 {
                    onSelect(question, filledOptions, min(correctIndex, filledOptions.count - 1))
                }
            }) {
                Text(NSLocalizedString("quiz.done", comment: ""))
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                    )
                    .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.top, 10)
            .disabled(question.isEmpty || options.filter({!$0.isEmpty}).count < 2)
            .opacity(question.isEmpty || options.filter({!$0.isEmpty}).count < 2 ? 0.5 : 1.0)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        // ✅ TAP FUERA PARA BAJAR TECLADO
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            focusedField = -1
        }
    }

    @ViewBuilder
    private func quizOptionField(index: Int) -> some View {
        HStack {
            TextField(NSLocalizedString("quiz.option.placeholder", comment: "") + " \(index + 1)", text: $options[index])
                .font(.system(size: 16, weight: .medium))
                .focused($focusedField, equals: index)

            Spacer()

            Button(action: {
                correctIndex = index
                HapticManager.shared.lightImpact()
            }) {
                Image(systemName: correctIndex == index ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(correctIndex == index ? .green : .gray.opacity(0.5))
            }
        }
        .padding()
        .background(Color.white.opacity(isDarkMode ? 0.08 : 0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(correctIndex == index ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}


struct ModernPollInputView: View {
    let onSelect: ([String]) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @State private var option1 = ""
    @State private var option2 = ""
    @FocusState private var focusedField: Field?

    private let maxPollQuestionLength = 44
    private let maxPollOptionLength = 28

    enum Field {
        case question, option1, option2
    }

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.createPoll")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.poll.subtitleCompact")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("stickerview.question")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(palette.secondaryText)
                        .kerning(1)

                    TextField(NSLocalizedString("stickerview.poll.placeholder", comment: "Poll question placeholder"), text: $question)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($focusedField, equals: .question)
                        .onChange(of: question) { newValue in
                            if newValue.count > maxPollQuestionLength {
                                question = String(newValue.prefix(maxPollQuestionLength))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(palette.fieldFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(focusedField == .question ? Color.indigo : palette.fieldStroke, lineWidth: 1.5)
                                )
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("stickerview.option1")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(palette.secondaryText)
                        .kerning(1)

                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .frame(width: 14, alignment: .leading)

                        TextField(NSLocalizedString("stickerview.poll.option1Placeholder", comment: "First option placeholder"), text: $option1)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(palette.primaryText)
                            .focused($focusedField, equals: .option1)
                            .onChange(of: option1) { newValue in
                                if newValue.count > maxPollOptionLength {
                                    option1 = String(newValue.prefix(maxPollOptionLength))
                                }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(palette.fieldFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(focusedField == .option1 ? Color.blue : palette.fieldStroke, lineWidth: 1.5)
                            )
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("stickerview.option2")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(palette.secondaryText)
                        .kerning(1)

                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                            .frame(width: 14, alignment: .leading)

                        TextField(NSLocalizedString("stickerview.poll.option2Placeholder", comment: "Second option placeholder"), text: $option2)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(palette.primaryText)
                            .focused($focusedField, equals: .option2)
                            .onChange(of: option2) { newValue in
                                if newValue.count > maxPollOptionLength {
                                    option2 = String(newValue.prefix(maxPollOptionLength))
                                }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(palette.fieldFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(focusedField == .option2 ? Color.pink : palette.fieldStroke, lineWidth: 1.5)
                            )
                    )
                }

                Button(action: {
                    onSelect([question, option1, option2])
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.createPoll")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFormValid ? Color.indigo : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!isFormValid)
                .animation(.easeInOut(duration: 0.2), value: isFormValid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusedField = .question
        }
    }

    private var isFormValid: Bool {
        !question.isEmpty && !option1.isEmpty && !option2.isEmpty
    }
}

struct ModernQuestionInputView: View {
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @FocusState private var isTextFieldFocused: Bool

    private let maxQuestionLength = 48

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.addQuestion")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.question.subtitleCompact")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.teal)
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.question.placeholder", comment: "Question sticker placeholder"), text: $question)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($isTextFieldFocused)
                        .onChange(of: question) { newValue in
                            if newValue.count > maxQuestionLength {
                                question = String(newValue.prefix(maxQuestionLength))
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isTextFieldFocused ? Color.purple : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                // Botón de acción
                Button(action: {
                    onSelect(question.isEmpty ? NSLocalizedString("stickerview.question.defaultPrompt", comment: "Default question prompt") : question)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.addQuestion")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.purple)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Modern Grid Views

struct ModernEmojiGridView: View {
    let onSelect: (String) -> Void

    let emojis = ["😀", "😍", "🥳", "😎", "🤩", "😂", "🥺", "😭",
                  "😡", "🤯", "🥶", "🤗", "🙄", "😴", "🤔", "💀",
                  "❤️", "💔", "💯", "🔥", "⭐", "✨", "🎉", "🎈",
                  "👍", "👎", "👏", "🙏", "💪", "✌️", "🤟", "👌"]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15),
            GridItem(.flexible(), spacing: 15)
        ], spacing: 20) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        onSelect(emoji)
                    }
                }) {
                    Text(emoji)
                        .font(.system(size: 35))
                        .frame(width: 55, height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: emoji)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Animated GIF View
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit  // ✅ Cambio clave: aspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.clear

        if let url = url {
            loadAnimatedGIF(url: url, into: imageView)
        }

        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // No necesitamos actualizar
    }

    private func loadAnimatedGIF(url: URL, into imageView: UIImageView) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }

            DispatchQueue.main.async {
                if let animatedImage = UIImage.animatedImageWithData(data) {
                    imageView.image = animatedImage
                } else if let staticImage = UIImage(data: data) {
                    imageView.image = staticImage
                }
            }
        }.resume()
    }
}

// MARK: - UIImage Extension para GIFs
extension UIImage {
    static func animatedImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            // Si solo hay una imagen, retornar imagen estática
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            let image = UIImage(cgImage: cgImage)
            images.append(image)

            // ✅ OBTENER DURACIÓN DEL FRAME
            var frameDuration: Double = 0.1 // Duración por defecto

            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {

                if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double {
                    frameDuration = delayTime
                } else if let delayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                    frameDuration = delayTime
                }

                // ✅ MÍNIMO 0.02 segundos para evitar animaciones demasiado rápidas
                frameDuration = max(frameDuration, 0.02)
            }

            totalDuration += frameDuration
        }

        // ✅ CREAR IMAGEN ANIMADA
        guard !images.isEmpty else { return nil }

        return UIImage.animatedImage(with: images, duration: totalDuration)
    }
}

struct ModernGiphyGridView: View {
    let gifs: [GiphyGif]
    let onSelect: (GiphyGif) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(gifs) { gif in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        onSelect(gif)
                    }
                }) {
                    // Usar AnimatedGIFView para mostrar GIFs animados
                    if let url = URL(string: gif.images.fixed_height.url) {
                        AnimatedGIFView(url: url)
                            .frame(height: 120)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    } else {
                        // Placeholder si no hay URL válida
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: gif.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Giphy Models (sin cambios)

struct GiphyResponse: Codable {
    let data: [GiphyGif]
}

struct GiphyGif: Codable, Identifiable {
    let id: String
    let images: GiphyImages

    var preferredStickerURL: URL? {
        URL(string: images.original?.url ?? images.fixed_height.url)
    }
}

struct GiphyImages: Codable {
    let fixed_height: GiphyImage
    let original: GiphyImage?
}

struct GiphyImage: Codable {
    let url: String
    let width: String
    let height: String
}

// MARK: - Extensions y Efectos Visuales (AGREGAR AL FINAL)

extension View {
    func glow(color: Color, radius: CGFloat) -> some View {
        self
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
    }

    func pressAnimation() -> some View {
        self.scaleEffect(1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: UUID())
    }
}

// MARK: - MeshGradient Fallback para iOS < 18
struct MeshGradient: View {
    let width: Int
    let height: Int
    let points: [[Float]]
    let colors: [Color]

    var body: some View {
        LinearGradient(
            colors: [colors.first ?? .black, colors.last ?? .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func pressAnimatioon() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    // Animation handled by button press
                }
            }
    }
}

// MARK: - Notificación de Menciones
extension StickerPickerView {
    // ✅ Función para enviar notificaciones de menciones al publicar historia
    static func sendMentionNotificationsForStory(storyId: String, stickers: [StickerItem]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // ✅ Filtrar solo stickers de menciones
        let mentionStickers = stickers.filter { $0.type == .mention }

        for sticker in mentionStickers {
            if let interactionData = sticker.interactionData,
               let userId = interactionData.userId,
               let username = interactionData.username {

                // ✅ Enviar notificación con storyId real
                Task { @MainActor in
                    NotificationService.shared.sendMentionNotification(
                        to: userId,
                        storyId: storyId
                    )
                }

            }
        }
    }

    // ✅ Función auxiliar para extraer userId de sticker de mención
    private func extractUserIdFromMentionSticker(_ sticker: StickerItem) -> String? {
        if let interactionData = sticker.interactionData {
            return interactionData.userId
        }
        return nil
    }

}

// MARK: - ✅ CLAVE ASOCIADA PARA DELEGATE
// MARK: - ✅ VISTA DE CÁMARA PARA SELFIE
struct SelfieCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    let onImageCaptured: (UIImage) -> Void

    var body: some View {
        NavigationView {
            VStack {
                Spacer()

                Text("stickerview.selfie")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("stickerview.tapForFrontCamera")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()

                Button(action: {
                    showingImagePicker = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                }
                .padding()

                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color.gray.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("stickerview.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera, cameraDevice: .front) { image in
                onImageCaptured(image)
                dismiss()
            }
        }
    }
}

// MARK: - ✅ IMAGE PICKER WRAPPER
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let cameraDevice: UIImagePickerController.CameraDevice?
    let onImagePicked: (UIImage) -> Void
    let onCancel: (() -> Void)?

    init(
        sourceType: UIImagePickerController.SourceType,
        cameraDevice: UIImagePickerController.CameraDevice? = nil,
        onImagePicked: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.sourceType = sourceType
        self.cameraDevice = cameraDevice
        self.onImagePicked = onImagePicked
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        if let cameraDevice = cameraDevice {
            picker.cameraDevice = cameraDevice
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel?()
            picker.dismiss(animated: true)
        }
    }
}

struct AudioStickerRecordingView: View {
    let onAdd: (Data, Double) -> Void

    @StateObject private var recorder = AudioRecordingManager.shared
    @State private var isRecording = false
    @State private var recordedData: Data?
    @State private var duration: Double = 0
    @State private var timer: Timer?
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var playbackProgress: Double = 0
    // Stable waveform levels generated once per recording
    @State private var waveformLevels: [Float] = (0..<30).map { _ in Float.random(in: 0.2...0.8) }

    var body: some View {
        VStack(spacing: 20) {
            // — Title —
            Text(NSLocalizedString("stickerview.audio.title", comment: "Add your voice"))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .padding(.top, 8)

            // — Waveform / Mic area (tappable when recorded) —
            ZStack {
                if isRecording {
                    LiveWaveformView(color: Color(red: 1.0, green: 0.4, blue: 0.3))
                        .frame(height: 44)
                } else if recordedData != nil {
                    VisualWaveformView(
                        levels: waveformLevels,
                        color: Color.white.opacity(0.2),
                        activeColor: Color(red: 1.0, green: 0.4, blue: 0.3),
                        progress: playbackProgress,
                        height: 35
                    )
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlayback() }
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                        .frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 20))
            )
            .padding(.vertical, 6)

            // — Duration + state label —
            VStack(spacing: 6) {
                Text(formatDuration(duration))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(isRecording ? .red : .primary)
                    .contentTransition(.numericText())

                Text(statusLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // — Controls row —
            HStack(spacing: 32) {
                // Discard (Icon only, Red)
                if recordedData != nil && !isRecording {
                    Button(action: discardRecording) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                                .liquidGlass(in: Circle(), interactive: true)

                            Image(systemName: "trash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }

                // Record / Stop (Liquid Glass circle + Red icon)
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 72, height: 72)
                            .liquidGlass(in: Circle(), interactive: true)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.red)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.red)
                        }
                    }
                }
                .scaleEffect(isRecording ? 1.08 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)

                // Play / Pause (Icon only)
                if recordedData != nil && !isRecording {
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                                .liquidGlass(in: Circle(), interactive: true)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.vertical, 8)

            // — Add to story button (Premium Liquid Glass Pill) —
            if let data = recordedData, !isRecording {
                Button(action: {
                    HapticManager.shared.mediumImpact()
                    onAdd(data, duration)
                }) {
                    Text(NSLocalizedString("stickerview.audio.add", comment: "Add to Story"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.clear)
                                .liquidGlass(in: Capsule(), interactive: true)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .onAppear {
            // Auto-play when sheet opens (if there's already a recording)
            if recordedData != nil {
                startPlayback()
            }
        }
        .onDisappear {
            stopEverything()
        }
    }

    private var statusLabel: String {
        if isRecording { return NSLocalizedString("stickerview.audio.recording", comment: "Recording...") }
        if recordedData != nil { return isPlaying ? "▶ \(NSLocalizedString("stickerview.audio.recorded", comment: "Ready to add"))" : NSLocalizedString("stickerview.audio.recorded", comment: "Ready to add") }
        return NSLocalizedString("stickerview.audio.tapToRecord", comment: "Tap to record")
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopPlayback()
        recordedData = nil
        duration = 0
        playbackProgress = 0
        waveformLevels = (0..<30).map { _ in Float.random(in: 0.2...0.8) }
        isRecording = true
        recorder.startRecording()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            duration += 0.1
            if duration >= 15 {
                stopRecording()
            }
        }
    }

    private func stopRecording() {
        isRecording = false
        timer?.invalidate()
        timer = nil

        recorder.stopRecording { data in
            self.recordedData = data
            // Auto-play the just-recorded clip
            if data != nil {
                self.startPlayback()
            }
        }
    }

    private func discardRecording() {
        stopPlayback()
        recordedData = nil
        duration = 0
        playbackProgress = 0
    }

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        guard let data = recordedData else { return }
        do {
            let session = AVAudioSession.sharedInstance()

            // La preview del sheet debe sonar aunque el dispositivo esté en silencio.
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
            isPlaying = true

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                if let player = audioPlayer {
                    withAnimation(.linear(duration: 0.05)) {
                        playbackProgress = player.currentTime / player.duration
                    }
                    if !player.isPlaying {
                        stopPlayback()
                    }
                }
            }
        } catch {
            print("Failed to play: \(error)")
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopEverything() {
        if isRecording { recorder.stopRecording { _ in } }
        stopPlayback()
        timer?.invalidate()
    }

    private func formatDuration(_ time: Double) -> String {
        let seconds = Int(time)
        let millis = Int((time - Double(seconds)) * 10)
        return String(format: "00:%02d.%d", seconds, millis)
    }
}
