import SwiftUI
import UIKit

struct ChatWallpaperScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

struct ChatWallpaperColorPicker: View {
    let colors: [String]
    let selected: String
    let title: LocalizedStringKey
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            onSelect(hex); dismiss()
                        } label: {
                            Circle().fill(Color(hex: hex)).aspectRatio(1, contentMode: .fit)
                                .overlay { if selected == hex { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(chatBubbleTextColor(for: Color(hex: hex))) } }
                                .padding(5).overlay(Circle().stroke(selected == hex ? Color.primary : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(Text("#" + hex)).accessibilityAddTraits(selected == hex ? .isSelected : [])
                    }
                }.padding(24)
            }.modifier(ChatWallpaperScrollEdgeModifier())
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("chat.wallpaper.back") { dismiss() } } }
        }
    }
}

struct ChatWallpaperPreviewEditor: View {
    let wallpaper: ChatWallpaper
    let image: UIImage?
    let onApply: (ChatWallpaper, UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ChatWallpaper()
    @State private var dark = false
    @State private var showBrightness = false
    @State private var showColors = false
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var translation: CGSize = .zero
    @State private var busy = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = geometry.size
                let colors = AdaptiveColors(colorScheme: dark ? .dark : .light)
                ZStack(alignment: .bottom) {
                    ChatWallpaperCanvas(wallpaper: draft, image: image, fallback: colors.chatBackground[0], zoom: zoom,
                        offset: bounded(CGSize(width: offset.width + translation.width, height: offset.height + translation.height), size: size))
                        .contentShape(Rectangle())
                        .gesture(DragGesture().updating($translation) { value, state, _ in if !busy && draft.kind == "photo" { state = value.translation } }
                            .onEnded { value in
                                if draft.kind == "photo" { offset = bounded(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), size: size) }
                            })
                        .simultaneousGesture(MagnifyGesture().onChanged { value in
                            if !busy && draft.kind == "photo" { zoom = min(4, max(1, zoomStart * value.magnification)) }
                        }.onEnded { _ in zoomStart = zoom; offset = bounded(offset, size: size) })
                        .onTapGesture(count: 2) { zoom = 1; zoomStart = 1; offset = .zero }
                    VStack(spacing: 18) {
                        GlassmorphicDateHeader(date: Date())
                        HStack { ChatTextBubbleView(text: NSLocalizedString("chat.wallpaper.crop", comment: ""), isOutgoing: false, reactions: nil, onReaction: { _ in }); Spacer(minLength: 24) }
                        HStack { Spacer(minLength: 24); ChatTextBubbleView(text: NSLocalizedString("chat.wallpaper.private", comment: ""), isOutgoing: true, reactions: nil, onReaction: { _ in }) }
                        Spacer()
                    }.padding(.horizontal, 18).padding(.top, 22)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.chatListContainerWidth, size.width)
                        .environment(\.chatOutgoingBubbleColor, Color(hex: draft.bubbleColorHex))
                        .allowsHitTesting(false)
                    HStack(alignment: .bottom) {
                        Button { showColors = true } label: {
                            Circle().fill(Color(hex: draft.bubbleColorHex)).frame(width: 38, height: 38).padding(7)
                                .overlay(Circle().stroke(.white, lineWidth: 2)).momentsChromeGlass(in: Circle(), style: .tinted)
                        }.buttonStyle(.plain).accessibilityLabel(Text("chat.wallpaper.bubbleColor"))
                        Spacer()
                        VStack(spacing: 12) {
                            if showBrightness {
                                Slider(value: $draft.dimming, in: 0...0.75)
                                    .frame(width: 180).rotationEffect(.degrees(-90)).frame(width: 48, height: 200)
                                    .padding(8).background(.background, in: .rect(cornerRadius: 22))
                                    .accessibilityLabel(Text("chat.wallpaper.dimming"))
                            }
                            Button {
                                dark.toggle(); showBrightness.toggle()
                            } label: {
                                Image(systemName: dark ? "sun.max" : "moon").font(.system(size: 22, weight: .medium))
                                    .frame(width: 52, height: 52).momentsChromeGlass(in: Circle(), style: .tinted)
                            }.buttonStyle(.plain).accessibilityLabel(Text("chat.wallpaper.dimming"))
                        }
                    }.padding(22)
                }.clipped()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.disabled(busy) }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                busy = true; let value = draft; let position = bounded(offset, size: size); let scale = zoom
                                Task {
                                    let cropped = await Task.detached(priority: .utility) { () -> UIImage? in
                                        guard value.kind == "photo", let image else { return nil }
                                        let output = CGSize(width: 1080, height: max(1, (1080 * size.height / size.width).rounded()))
                                        let fill = max(output.width / image.size.width, output.height / image.size.height) * scale
                                        let width = image.size.width * fill; let height = image.size.height * fill; let factor = output.width / size.width
                                        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                                        return UIGraphicsImageRenderer(size: output, format: format).image { _ in
                                            image.draw(in: CGRect(x: (output.width - width) / 2 + position.width * factor,
                                                y: (output.height - height) / 2 + position.height * factor, width: width, height: height))
                                        }
                                    }.value
                                    onApply(value, cropped)
                                }
                            } label: { if busy { ProgressView() } else { Text("chat.wallpaper.save") } }.disabled(busy)
                        }
                    }
            }.navigationTitle(Text("chat.wallpaper.previewTitle")).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showColors) {
                    ChatWallpaperColorPicker(colors: chatBubblePalette, selected: draft.bubbleColorHex, title: "chat.wallpaper.bubbleColor") { draft.bubbleColorHex = $0 }
                }
                .onAppear { draft = wallpaper; dark = colorScheme == .dark }
        }.interactiveDismissDisabled(busy)
    }
    private func bounded(_ value: CGSize, size: CGSize) -> CGSize {
        guard draft.kind == "photo", let image else { return .zero }
        let fill = max(size.width / image.size.width, size.height / image.size.height) * zoom
        let x = max(0, (image.size.width * fill - size.width) / 2); let y = max(0, (image.size.height * fill - size.height) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
}
