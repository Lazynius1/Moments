import SwiftUI

// MARK: - GIF picker overlay (bottom sheet)

struct ChatGiphyPickerSheetOverlay: View {
    @Binding var activeSheet: ChatAttachmentSheetKind?
    let accentColor: Color
    let onSelect: (ChatGiphyAsset) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if activeSheet == .gif {
            GeometryReader { proxy in
                let bottomPadding = ChatInputBarLayout.attachmentSheetBottomInset(
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                let sheetHeight = ChatAttachmentSheetMetrics.sheetHeight(
                    containerHeight: proxy.size.height
                )

                ZStack(alignment: .bottom) {
                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16)
                        .ignoresSafeArea()
                        .onTapGesture { dismiss() }

                    ChatAttachmentSheetSurface(height: sheetHeight) {
                        ChatGiphyPickerContent(
                            kind: .gif,
                            accentColor: accentColor,
                            onSelect: { gif in
                                if let asset = ChatGiphyAsset(gif: gif) {
                                    onSelect(asset)
                                }
                                dismiss()
                            }
                        )
                    }
                    .padding(.horizontal, ChatAttachmentSheetMetrics.horizontalInset)
                    .padding(.bottom, bottomPadding)
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: activeSheet)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(45)
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            activeSheet = nil
        }
    }
}

// MARK: - Shared Giphy picker content (GIF or sticker)

struct ChatGiphyPickerContent: View {
    enum Kind {
        case gif
        case sticker

        var function: ChatGiphyService.FunctionName {
            switch self {
            case .gif: return .gifs
            case .sticker: return .stickers
            }
        }

        var searchPlaceholderKey: String {
            switch self {
            case .gif: return "chat.giphy.searchGif"
            case .sticker: return "chat.giphy.searchSticker"
            }
        }
    }

    let kind: Kind
    let accentColor: Color
    let onSelect: (GiphyGif) -> Void
    /// Stickers recientes opcionales (solo para `.sticker`).
    var recents: [ChatStickerAsset] = []
    var onSelectRecent: ((ChatStickerAsset) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var results: [GiphyGif] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError = false
    @State private var searchTask: Task<Void, Never>?

    private let maxRecentCount = 8

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    }

    private var gridSpacing: CGFloat { 6 }
    private var stickerCellInset: CGFloat { 8 }
    private var gifColumnSpacing: CGFloat { 6 }

    private var displayedRecents: [ChatStickerAsset] {
        Array(recents.prefix(maxRecentCount))
    }

    private var showsPinnedRecents: Bool {
        kind == .sticker
            && !displayedRecents.isEmpty
            && onSelectRecent != nil
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    /// Reparte ítems en dos columnas (estilo masonry IG: flujo alterno).
    private var gifColumns: ([GiphyGif], [GiphyGif]) {
        var left: [GiphyGif] = []
        var right: [GiphyGif] = []
        for (index, gif) in results.enumerated() {
            if index.isMultiple(of: 2) {
                left.append(gif)
            } else {
                right.append(gif)
            }
        }
        return (left, right)
    }

    private var stickerGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
            ForEach(results) { gif in
                Button {
                    HapticManager.shared.lightImpact()
                    onSelect(gif)
                } label: {
                    stickerPickerCell(for: gif)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    private var gifMasonryGrid: some View {
        let columns = gifColumns
        return HStack(alignment: .top, spacing: gifColumnSpacing) {
            LazyVStack(spacing: gifColumnSpacing) {
                    ForEach(columns.0) { gif in
                    Button {
                        HapticManager.shared.lightImpact()
                        onSelect(gif)
                    } label: {
                        gifPickerCell(for: gif)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            LazyVStack(spacing: gifColumnSpacing) {
                ForEach(columns.1) { gif in
                    Button {
                        HapticManager.shared.lightImpact()
                        onSelect(gif)
                    } label: {
                        gifPickerCell(for: gif)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.top, 14)
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(query: newValue)
                }

            if showsPinnedRecents, let onSelectRecent {
                pinnedRecentsSection(onSelectRecent: onSelectRecent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !loadError {
                        giphySectionHeader
                    }

                    if isLoading {
                        ProgressView()
                            .tint(accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if loadError {
                        stateMessage(key: "chat.giphy.error")
                    } else if results.isEmpty {
                        stateMessage(key: "chat.giphy.empty")
                    } else if kind == .sticker {
                        stickerGrid
                    } else {
                        gifMasonryGrid
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ChatAttachmentSheetCanvasBackground() }
        .onAppear { loadTrending() }
        .onDisappear { searchTask?.cancel() }
    }

    private var giphySectionHeader: some View {
        HStack {
            Text(LocalizedStringKey("chat.giphy.brand"))
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(secondaryText)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, showsPinnedRecents ? 4 : 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func pinnedRecentsSection(onSelectRecent: @escaping (ChatStickerAsset) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("chat.giphy.recents"))
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(secondaryText)
                .padding(.horizontal, 16)

            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(displayedRecents) { sticker in
                    Button {
                        HapticManager.shared.lightImpact()
                        onSelectRecent(sticker)
                    } label: {
                        recentStickerGridCell(url: sticker.downloadURL)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        ChatAttachmentSearchField(
            placeholderKey: kind.searchPlaceholderKey,
            text: $searchText,
            onClear: { loadTrending() }
        )
    }

    @ViewBuilder
    private func recentStickerGridCell(url: URL?) -> some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let inner = side - stickerCellInset * 2
            AnimatedGIFView(url: url)
                .frame(width: inner, height: inner)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func stateMessage(key: String) -> some View {
        Text(LocalizedStringKey(key))
            .font(.custom("Poppins-Regular", size: 14))
            .foregroundColor(secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func stickerPickerCell(for gif: GiphyGif) -> some View {
        let url = URL(string: gif.images.fixed_height.url)

        GeometryReader { proxy in
            let side = proxy.size.width
            let inner = side - stickerCellInset * 2
            AnimatedGIFView(url: url)
                .frame(width: inner, height: inner)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func gifPickerCell(for gif: GiphyGif) -> some View {
        let url = URL(string: gif.images.fixed_height.url)
        let ratio = gif.previewAspectRatio
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        AnimatedGIFView(url: url)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .clipShape(shape)
    }

    private func loadTrending() {
        searchTask?.cancel()
        isLoading = true
        loadError = false
        searchTask = Task {
            do {
                let gifs = try await ChatGiphyService.shared.fetch(function: kind.function, mode: .trending)
                if Task.isCancelled { return }
                results = gifs
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                loadError = true
                isLoading = false
            }
        }
    }

    private func scheduleSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !trimmed.isEmpty else {
            loadTrending()
            return
        }
        isLoading = true
        loadError = false
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            do {
                let gifs = try await ChatGiphyService.shared.fetch(
                    function: kind.function,
                    mode: .search,
                    query: trimmed
                )
                if Task.isCancelled { return }
                results = gifs
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                loadError = true
                isLoading = false
            }
        }
    }
}
