import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Kingfisher
import CoreLocation
import MapKit
import WeatherKit

// MARK: - Sticker Picker

struct StickerPickerView: View {
    @Binding var selectedStickers: [StickerItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var catalogSearchText = ""
    @State private var gifSearchText = ""
    @State private var selectedCategory: StickerCategory = .trending
    @State private var giphyResults: [GiphyGif] = []
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
        case countdown
        case weather
        case time
        case selfie

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
            case .countdown: return NSLocalizedString("stickerview.category.countdown", comment: "Countdown category")
            case .weather: return NSLocalizedString("stickerview.category.weather", comment: "Weather category")
            case .time: return NSLocalizedString("stickerview.category.time", comment: "Time category")
            case .selfie: return NSLocalizedString("stickerview.category.selfie", comment: "Selfie category")
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
            case .countdown: return "timer"
            case .weather: return "cloud.sun.fill"
            case .time: return "clock.fill"
            case .selfie: return "person.crop.circle.badge.plus"
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
            case .countdown: return Color(red: 0.61, green: 0.34, blue: 0.97)
            case .weather: return Color(red: 0.20, green: 0.77, blue: 0.95)
            case .time: return Color(red: 1.00, green: 0.62, blue: 0.20)
            case .selfie: return Color(red: 1.00, green: 0.25, blue: 0.55)
            }
        }

    }

    private var catalogCategories: [StickerCategory] {
        [.location, .mention, .trending, .emoji, .link, .question, .poll, .hashtag, .countdown, .weather, .time, .selfie]
    }

    private var filteredCatalogCategories: [StickerCategory] {
        let query = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalogCategories }
        return catalogCategories.filter {
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
        Rectangle()
            .fill(pickerBackgroundColor)
            .overlay(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDarkMode ? 0.02 : 0.14),
                            Color.white.opacity(isDarkMode ? 0.0 : 0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Circle()
                        .fill(Color(red: 0.79, green: 0.45, blue: 0.21).opacity(0.12))
                        .frame(width: 300, height: 300)
                        .blur(radius: 92)
                        .offset(x: 120, y: 220)

                    Circle()
                        .fill(Color(red: 0.46, green: 0.29, blue: 0.74).opacity(0.14))
                        .frame(width: 260, height: 260)
                        .blur(radius: 92)
                        .offset(x: -90, y: 160)

                    Rectangle()
                        .fill(isDarkMode ? Color.black.opacity(0.16) : Color.clear)
                }
            )
            .overlay(
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                                isDarkMode ? Color.white.opacity(0.02) : Color.black.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }

    @ViewBuilder
    private func StickerPickerHeader() -> some View {
        HStack(spacing: 12) {
            Button(action: {
                hapticFeedback(.light)
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
                hapticFeedback(.light)
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
                    hapticFeedback(.light)
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
                    hapticFeedback(.light)
                    if gifSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        loadTrendingStickers()
                    } else {
                        searchTrendingStickers()
                    }
                }

            if !gifSearchText.isEmpty {
                Button(action: {
                    hapticFeedback(.light)
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
            HStack(spacing: 10) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(category.accentColor)
                    .shadow(color: category.accentColor.opacity(0.22), radius: 1.5, x: 0, y: 0)

                Text(category.displayName)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(pillTextColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
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
                        hapticFeedback(.light)
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

        case .countdown:
            ModernCountdownInputView { title, targetAtMs in
                createCountdownSticker(title: title, targetAtMs: targetAtMs)
            }

        case .weather, .time, .selfie:
            EmptyView()
        }
    }

    @ViewBuilder
    private func MomentsTrendingGrid(stickers: [GiphyGif]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(stickers) { sticker in
                Button(action: {
                    hapticFeedback(.medium)
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
                    hapticFeedback(.medium)
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
                    hapticFeedback(.light)
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
            hapticFeedback(.medium)
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
        hapticFeedback(.medium)

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

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impact = UIImpactFeedbackGenerator(style: style)
        impact.impactOccurred()
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

    private func createLocationSticker(_ location: String, coordinate: CLLocationCoordinate2D?) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 120)
            
            // ✅ FONDO CON GRADIENTE COMO INSTAGRAM
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            
            // Gradiente de fondo
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.85).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.85).cgColor,
                UIColor.systemPink.withAlphaComponent(0.85).cgColor
            ] as CFArray
            
            context.cgContext.saveGState()
            backgroundPath.addClip()
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            } else {
                UIColor.systemPurple.setFill()
                context.fill(rect)
            }
            context.cgContext.restoreGState()
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = 1.5
            backgroundPath.stroke()
            
            // 📍 Icono de ubicación simple
            let locationIcon = "📍"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            locationIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // 📝 TEXTO DE UBICACIÓN
            let displayText = location
            
            // Texto principal
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedText = displayText.count > 25 ? String(displayText.prefix(25)) + "..." : displayText
            truncatedText.draw(in: CGRect(x: 16, y: 45, width: 248, height: 50), withAttributes: textAttributes)
            
            // Texto "Ver ubicación"
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            NSLocalizedString("stickerview.location.viewLocation", comment: "View location subtitle")
                .draw(in: CGRect(x: 16, y: 95, width: 248, height: 20), withAttributes: subtitleAttributes)
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
        
        // ✅ DISEÑO LIQUID GLASS (MÁS LIMPIO Y MODERNO)
        // Aumentamos altura para dar aire
        let width: CGFloat = 160
        let height: CGFloat = 56
        let cornerRadius: CGFloat = 28 // Full rounded sides
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            
            // 1. FONDO TRANSLÚCIDO (Glass Effect)
            // Simulación de cristal con blanco semitransparente + sombra interna sutil
            context.cgContext.saveGState()
            path.addClip()
            
            // Fondo base suave
            UIColor.black.withAlphaComponent(0.4).setFill() // Oscuro para contraste sobre cualquier fondo
            path.fill()
            
            // Brillo superior (Top Gloss)
            let glossPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height / 2))
            UIColor.white.withAlphaComponent(0.1).setFill()
            glossPath.fill()
            
            context.cgContext.restoreGState()
            
            // 2. BORDE SUTIL (Rim Light)
            // Borde blanco muy fino y semitransparente para definir la forma
            context.cgContext.saveGState()
            path.lineWidth = 1
            UIColor.white.withAlphaComponent(0.3).setStroke()
            path.stroke()
            context.cgContext.restoreGState()
            
            // 3. TEXTO TIME (Grande y Bold)
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold), // SF Pro Bold
                .foregroundColor: UIColor.white,
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium), // SF Pro Medium
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }()
            ]
            
            // Dibujar Hora
            let timeSize = timeString.size(withAttributes: timeAttributes)
            let dateSize = dateString.size(withAttributes: dateAttributes)
            
            let totalContentHeight = timeSize.height + dateSize.height - 4 // -4 de spacing negativo
            let startY = (height - totalContentHeight) / 2
            
            timeString.draw(in: CGRect(x: 0, y: startY, width: width, height: timeSize.height), withAttributes: timeAttributes)
            
            // Dibujar Fecha
            dateString.draw(in: CGRect(x: 0, y: startY + timeSize.height - 4, width: width, height: dateSize.height), withAttributes: dateAttributes)
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
            UIColor.black.withAlphaComponent(0.28).setFill()
            circlePath.fill()
            UIColor.white.setStroke()
            circlePath.lineWidth = 2
            circlePath.stroke()

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: size * 0.38, weight: .bold)
            let icon = UIImage(systemName: "camera.fill", withConfiguration: symbolConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
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
        
        // ✅ CREAR STICKER CIRCULAR CON BORDE ELEGANTE
        let size: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let stickerImage = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            
            // ✅ FONDO CIRCULAR CON GRADIENTE
            let circlePath = UIBezierPath(ovalIn: rect)
            
            // Gradiente de fondo
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.8).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.8).cgColor,
                UIColor.systemPink.withAlphaComponent(0.8).cgColor
            ] as CFArray
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0]) {
                context.cgContext.saveGState()
                circlePath.addClip()
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
                context.cgContext.restoreGState()
            } else {
                // Fallback
                UIColor.systemPurple.withAlphaComponent(0.8).setFill()
                circlePath.fill()
            }
            
            // ✅ BORDE ELEGANTE
            UIColor.white.withAlphaComponent(0.6).setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()
            
            // ✅ FOTO DEL SELFIE (CIRCULAR)
            let imageRect = rect.insetBy(dx: 6, dy: 6)
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

        // ✅ ESTILO INSTAGRAM: Solo @username con fondo blanco
        let text = "@\(username)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        
        let textSize = text.size(withAttributes: textAttributes)
        let padding: CGFloat = 12
        let width = textSize.width + (padding * 2)
        let height = textSize.height + (padding * 2)
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            
            // ✅ FONDO BLANCO nativo
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
            UIColor.white.setFill()
            backgroundPath.fill()
            
            // ✅ BORDE SUTIL
            UIColor.black.withAlphaComponent(0.1).setStroke()
            backgroundPath.lineWidth = 0.5
            backgroundPath.stroke()
            
            // ✅ TEXTO CENTRADO
            let textRect = CGRect(
                x: padding,
                y: padding,
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
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 120)
            
            // ✅ FONDO CON GRADIENTE COMO INSTAGRAM
            let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            
            // Gradiente de fondo (colores hashtag)
            let colors = [
                UIColor.systemPink.withAlphaComponent(0.85).cgColor,
                UIColor.systemOrange.withAlphaComponent(0.85).cgColor,
                UIColor.systemYellow.withAlphaComponent(0.85).cgColor
            ] as CFArray
            
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0]) {
                context.cgContext.saveGState()
                backgroundPath.addClip()
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
                context.cgContext.restoreGState()
            } else {
                UIColor.systemOrange.withAlphaComponent(0.85).setFill()
                backgroundPath.fill()
            }
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = 1.5
            backgroundPath.stroke()
            
            // 🏷️ Icono de hashtag
            let hashtagIcon = "#"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            hashtagIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // 📝 TEXTO DE HASHTAG
            let displayText = hashtag
            
            // Texto principal
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedText = displayText.count > 25 ? String(displayText.prefix(25)) + "..." : displayText
            truncatedText.draw(in: CGRect(x: 16, y: 45, width: 248, height: 50), withAttributes: textAttributes)
            
            // Texto "Ver hashtag"
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            NSLocalizedString("stickerview.hashtag.viewHashtag", comment: "View hashtag subtitle")
                .draw(in: CGRect(x: 16, y: 95, width: 248, height: 20), withAttributes: subtitleAttributes)
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
        let resolvedSize = linkStickerRenderingSize(for: resolvedTitle)
        let renderer = UIGraphicsImageRenderer(size: resolvedSize)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: resolvedSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: resolvedSize.height / 2)

            UIColor.white.withAlphaComponent(0.16).setFill()
            path.fill()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            if let linkIcon = UIImage(systemName: "link")?.withTintColor(UIColor(red: 0.29, green: 0.72, blue: 0.98, alpha: 1), renderingMode: .alwaysOriginal) {
                linkIcon.draw(in: CGRect(x: 14, y: 15, width: 15, height: 15))
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            if let linkIcon = UIImage(systemName: "link")?.withTintColor(UIColor(red: 0.29, green: 0.72, blue: 0.98, alpha: 1), renderingMode: .alwaysOriginal) {
                linkIcon.draw(in: CGRect(x: 18, y: 16, width: 18, height: 18))
            }
            (resolvedTitle as NSString).draw(
                in: CGRect(x: 48, y: 14, width: resolvedSize.width - 66, height: 20),
                withAttributes: titleAttributes
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
        
        // ✅ NUEVO: Tamaño más compacto y elegante
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 280, height: 180))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 280, height: 180)
            
            // ✅ Fondo con gradiente elegante (colores de la app)
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.85).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.85).cgColor,
                UIColor.systemPink.withAlphaComponent(0.85).cgColor
            ] as CFArray
            
            context.cgContext.saveGState()
            let mainPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            mainPath.addClip()
            
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 0.5, 1.0]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: rect.width, y: rect.height),
                    options: []
                )
            } else {
                UIColor.systemPurple.withAlphaComponent(0.85).setFill()
                mainPath.fill()
            }
            context.cgContext.restoreGState()
            
            // ✅ Borde con glow sutil
            UIColor.white.withAlphaComponent(0.3).setStroke()
            mainPath.lineWidth = 1.5
            mainPath.stroke()
            
            // ✅ Icono de poll (más elegante que "ENCUESTA")
            let pollIcon = "📊"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            pollIcon.draw(in: CGRect(x: 16, y: 12, width: 20, height: 20), withAttributes: iconAttributes)
            
            // ✅ Pregunta con mejor tipografía
            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let questionText = poll[0].count > 30 ? String(poll[0].prefix(30)) + "..." : poll[0]
            questionText.draw(in: CGRect(x: 16, y: 35, width: 248, height: 40), withAttributes: questionAttributes)
            
            // ✅ Opción 1 con diseño más moderno
            let option1Rect = CGRect(x: 16, y: 85, width: 248, height: 35)
            let option1Path = UIBezierPath(roundedRect: option1Rect, cornerRadius: 17.5)
            
            // Fondo semi-transparente con blur effect
            UIColor.white.withAlphaComponent(0.15).setFill()
            option1Path.fill()
            
            // Borde sutil
            UIColor.white.withAlphaComponent(0.4).setStroke()
            option1Path.lineWidth = 0.8
            option1Path.stroke()
            
            // ✅ Opción 2
            let option2Rect = CGRect(x: 16, y: 130, width: 248, height: 35)
            let option2Path = UIBezierPath(roundedRect: option2Rect, cornerRadius: 17.5)
            
            UIColor.white.withAlphaComponent(0.15).setFill()
            option2Path.fill()
            
            UIColor.white.withAlphaComponent(0.4).setStroke()
            option2Path.lineWidth = 0.8
            option2Path.stroke()
            
            // ✅ Texto de las opciones con mejor espaciado
            let optionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            
            let option1Text = poll[1].count > 22 ? String(poll[1].prefix(22)) + "..." : poll[1]
            let option2Text = poll[2].count > 22 ? String(poll[2].prefix(22)) + "..." : poll[2]
            
            option1Text.draw(in: CGRect(x: 28, y: 94, width: 224, height: 18), withAttributes: optionAttributes)
            option2Text.draw(in: CGRect(x: 28, y: 139, width: 224, height: 18), withAttributes: optionAttributes)
            
            // ✅ Indicador de "Toca para votar" sutil
            let tapText = "Toca para votar"
            let tapAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            tapText.draw(in: CGRect(x: 16, y: 155, width: 248, height: 12), withAttributes: tapAttributes)
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
    
    private func createQuestionSticker(_ question: String) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 120))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 300, height: 120)
            
            // Fondo degradado dinámico - SAFE UNWRAP
            let colors = [
                UIColor.systemTeal.cgColor,
                UIColor.systemBlue.cgColor,
                UIColor.systemPurple.cgColor
            ] as CFArray
            
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()
            
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 0.5, 1.0]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: rect.width, y: rect.height),
                    options: []
                )
            } else {
                // Fallback color
                UIColor.systemBlue.setFill()
                path.fill()
            }
            
            // Overlay glassmorphism
            UIColor.white.withAlphaComponent(0.1).setFill()
            let overlayPath = UIBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 17)
            overlayPath.fill()
            
            // Icono de pregunta
            let questionMark = "?"
            let iconAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]
            questionMark.draw(in: CGRect(x: 20, y: 20, width: 30, height: 30), withAttributes: iconAttributes)
            
            // Texto "PREGÚNTAME"
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .kern: 1.0
            ]
            NSLocalizedString("stickerview.question.askMe", comment: "Ask me header")
                .draw(in: CGRect(x: 60, y: 25, width: 220, height: 15), withAttributes: headerAttributes)
            
            // Pregunta personalizada
            let questionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            
            let truncatedQuestion = question.count > 40 ? String(question.prefix(40)) + "..." : question
            truncatedQuestion.draw(in: CGRect(x: 20, y: 55, width: 260, height: 50), withAttributes: questionAttributes)
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
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 20)
            let colors = [
                UIColor(red: 0.32, green: 0.24, blue: 0.92, alpha: 0.86).cgColor,
                UIColor(red: 0.86, green: 0.28, blue: 0.73, alpha: 0.92).cgColor
            ] as CFArray

            context.cgContext.saveGState()
            path.addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
            }
            context.cgContext.restoreGState()

            UIColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            paragraphStyle.alignment = .center

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let digitAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let colonAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
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
                    UIColor.white.withAlphaComponent(0.18).setFill()
                    boxPath.fill()
                    UIColor.white.withAlphaComponent(0.2).setStroke()
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

struct ModernPollInputView: View {
    let onSelect: ([String]) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @State private var option1 = ""
    @State private var option2 = ""
    @FocusState private var focusedField: Field?
    
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
