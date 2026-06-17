import SwiftUI

// MARK: - Sticker picker overlay (bottom sheet)

struct ChatStickerPickerSheetOverlay: View {
    @Binding var activeSheet: ChatAttachmentSheetKind?
    let accentColor: Color
    let onSelect: (ChatStickerAsset) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var recents: [ChatStickerAsset] = []

    var body: some View {
        if activeSheet == .sticker {
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
                            kind: .sticker,
                            accentColor: accentColor,
                            onSelect: { gif in
                                if let asset = ChatStickerAsset(gif: gif) {
                                    onSelect(asset)
                                }
                                dismiss()
                            },
                            onBack: dismiss,
                            recents: recents,
                            onSelectRecent: { sticker in
                                onSelect(sticker)
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
            .onAppear { recents = ChatRecentStickersStore.load() }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            activeSheet = nil
        }
    }
}
