import SwiftUI

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
    @State private var isLoadingMore = false
    @State private var loadError = false
    @State private var hasMorePages = true
    @State private var nextOffset = 0
    @State private var activeMode: ChatGiphyService.Mode = .trending
    @State private var activeQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?

    private let pageSize = 24

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
                .onAppear {
                    triggerLoadMoreIfNeeded(for: gif)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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
                    .onAppear {
                        triggerLoadMoreIfNeeded(for: gif)
                    }
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
                    .onAppear {
                        triggerLoadMoreIfNeeded(for: gif)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if isLoadingMore {
            ProgressView()
                .tint(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    var body: some View {
        ChatAttachmentScrollUnderSearchLayout {
            searchField
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(query: newValue)
                }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if showsPinnedRecents, let onSelectRecent {
                    pinnedRecentsSection(onSelectRecent: onSelectRecent)
                }

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
                    paginationFooter
                } else {
                    gifMasonryGrid
                    paginationFooter
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadTrending() }
        .onDisappear {
            searchTask?.cancel()
            loadMoreTask?.cancel()
        }
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
        .padding(.top, 8)
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
        resetPagination()
        activeMode = .trending
        activeQuery = ""
        fetchPage(offset: 0, append: false)
    }

    private func scheduleSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !trimmed.isEmpty else {
            loadTrending()
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            resetPagination()
            activeMode = .search
            activeQuery = trimmed
            fetchPage(offset: 0, append: false)
        }
    }

    private func resetPagination() {
        loadMoreTask?.cancel()
        nextOffset = 0
        hasMorePages = true
        isLoadingMore = false
    }

    private func triggerLoadMoreIfNeeded(for gif: GiphyGif) {
        guard gif.id == results.last?.id else { return }
        loadMoreIfNeeded()
    }

    private func loadMoreIfNeeded() {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }
        fetchPage(offset: nextOffset, append: true)
    }

    private func fetchPage(offset: Int, append: Bool) {
        if append {
            guard !isLoadingMore else { return }
            isLoadingMore = true
            loadMoreTask?.cancel()
            loadMoreTask = Task {
                await performFetch(offset: offset, append: true)
            }
        } else {
            searchTask?.cancel()
            loadMoreTask?.cancel()
            isLoading = true
            loadError = false
            results = []
            searchTask = Task {
                await performFetch(offset: offset, append: false)
            }
        }
    }

    @MainActor
    private func performFetch(offset: Int, append: Bool) async {
        do {
            let page = try await ChatGiphyService.shared.fetch(
                function: kind.function,
                mode: activeMode,
                query: activeMode == .search ? activeQuery : nil,
                offset: offset,
                limit: pageSize
            )
            if Task.isCancelled { return }

            if append {
                let existingIDs = Set(results.map(\.id))
                let newItems = page.items.filter { !existingIDs.contains($0.id) }
                results.append(contentsOf: newItems)
                isLoadingMore = false
            } else {
                results = page.items
                isLoading = false
            }

            nextOffset = page.nextOffset
            hasMorePages = page.hasMore
            loadError = false
        } catch {
            if Task.isCancelled { return }
            if append {
                isLoadingMore = false
            } else {
                loadError = true
                isLoading = false
            }
        }
    }
}
