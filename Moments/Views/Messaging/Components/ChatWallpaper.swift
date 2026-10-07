import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import ImageIO

struct ChatWallpaper: Codable, Equatable {
    var kind = "default"
    var colorHex = "DCE8E4"
    var storagePath = ""
    var dimming = 0.2
    var bubbleColorHex = "3F6F8F"
    var presetId = ""

    init() {}
    init(data: [String: Any]) {
        presetId = data["presetId"] as? String ?? ""
        bubbleColorHex = data["bubbleColorHex"] as? String ?? "3F6F8F"
        kind = data["kind"] as? String ?? "default"
        colorHex = data["colorHex"] as? String ?? "DCE8E4"
        storagePath = data["storagePath"] as? String ?? ""
        dimming = min(0.75, max(0, data["dimming"] as? Double ?? 0.2))
    }
    var fields: [String: Any] {
        ["kind": kind, "colorHex": colorHex, "storagePath": storagePath,
         "dimming": dimming, "bubbleColorHex": bubbleColorHex, "presetId": presetId, "updatedAt": FieldValue.serverTimestamp()]
    }
}

@MainActor
final class ChatWallpaperStore: ObservableObject {
    @Published private(set) var wallpaper = ChatWallpaper()
    @Published private(set) var image: UIImage?
    private var listener: ListenerRegistration?
    private var imageTask: Task<Void, Never>?
    private var key = ""
    private var loadedPath = ""

    func start(conversationId: String) {
        guard let uid = Auth.auth().currentUser?.uid, !conversationId.isEmpty else { return }
        let nextKey = "chatWallpaper.\(uid).\(conversationId)"
        guard nextKey != key else { return }
        listener?.remove()
        imageTask?.cancel()
        key = nextKey
        loadedPath = ""
        image = nil
        wallpaper = ChatWallpaper()
        if let data = UserDefaults.standard.data(forKey: key), let cached = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            apply(ChatWallpaper(data: cached))
        }
        listener = Firestore.firestore().collection("users").document(uid)
            .collection("chatWallpapers").document(conversationId).addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot, snapshot.metadata.isFromCache == false || snapshot.exists else { return }
                let value = ChatWallpaper(data: snapshot.data() ?? [:])
                Task { @MainActor [weak self] in
                    guard let self, self.key == nextKey else { return }
                    self.apply(value)
                }
            }
    }

    private func apply(_ value: ChatWallpaper) {
        wallpaper = value
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
        let path = value.kind == "photo" ? value.storagePath : ""
        guard path != loadedPath else { return }
        loadedPath = path
        imageTask?.cancel()
        image = nil
        guard !path.isEmpty, let uid = Auth.auth().currentUser?.uid,
              path.hasPrefix("users/\(uid)/chatWallpapers/") else { return }
        let expectedKey = key
        imageTask = Task { [weak self] in
            let file = Self.cacheURL(path)
            do {
                let bytes: Data
                if let cached = await Task.detached(priority: .utility, operation: { try? Data(contentsOf: file) }).value { bytes = cached }
                else {
                    bytes = try await Storage.storage().reference(withPath: path).data(maxSize: 8 * 1024 * 1024)
                    let cachedBytes = bytes
                    await Task.detached(priority: .utility) { try? cachedBytes.write(to: file, options: .atomic) }.value
                }
                let decoded = await Task.detached(priority: .utility) { Self.decode(bytes) }.value
                guard !Task.isCancelled, let self, self.key == expectedKey, self.loadedPath == path else { return }
                self.image = decoded
            } catch { /* Keep the ordinary background if the private image is unavailable offline. */ }
        }
    }

    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1920
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    nonisolated private static func cacheURL(_ path: String) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ChatWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    func save(_ draft: ChatWallpaper, photo: Data?, conversationId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid, !conversationId.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let previous = wallpaper.storagePath
        var value = draft
        var uploadedPath: String?
        if value.kind == "photo", let photo {
            let path = "users/\(uid)/chatWallpapers/\(conversationId)/\(UUID().uuidString).jpg"
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await Storage.storage().reference(withPath: path).putDataAsync(photo, metadata: metadata)
            value.storagePath = path
            uploadedPath = path
        }
        if value.kind != "photo" { value.storagePath = "" }
        do {
            try await Firestore.firestore().collection("users").document(uid).collection("chatWallpapers")
                .document(conversationId).setData(value.fields)
        } catch {
            if let uploadedPath { try? await Storage.storage().reference(withPath: uploadedPath).delete() }
            throw error
        }
        apply(value)
        if !previous.isEmpty, previous != value.storagePath, previous.hasPrefix("users/\(uid)/chatWallpapers/") {
            try? await Storage.storage().reference(withPath: previous).delete()
        }
    }
    deinit { listener?.remove(); imageTask?.cancel() }
}

struct ChatWallpaperBackground: View {
    let conversationId: String
    let adaptiveColors: AdaptiveColors
    @StateObject private var store = ChatWallpaperStore()
    var body: some View {
        ChatWallpaperCanvas(wallpaper: store.wallpaper, image: store.image, fallback: adaptiveColors.chatBackground[0])
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: "\(Auth.auth().currentUser?.uid ?? ""):\(conversationId)") { store.start(conversationId: conversationId) }
    }
}

struct ChatWallpaperCanvas: View {
    let wallpaper: ChatWallpaper
    let image: UIImage?
    let fallback: Color
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                fallback
                if wallpaper.kind == "color" { Color(hex: wallpaper.colorHex) }
                if wallpaper.kind == "preset", let preset = ChatWallpaperPreset.all.first(where: { $0.id == wallpaper.presetId }) {
                    Image(preset.asset).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height)
                }
                if wallpaper.kind == "photo", let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(zoom).offset(offset)
                }
                if wallpaper.kind != "default" { Color.black.opacity(wallpaper.dimming) }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
    }
}

extension ChatWallpaper {
    /// Color de burbuja guardado en este dispositivo para un chat (sin lecturas de red); por defecto si nunca se abrió.
    static func cachedBubbleColor(conversationId: String) -> Color {
        guard let uid = Auth.auth().currentUser?.uid, !conversationId.isEmpty,
              let data = UserDefaults.standard.data(forKey: "chatWallpaper.\(uid).\(conversationId)"),
              let cached = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Color(hex: ChatWallpaper().bubbleColorHex)
        }
        return Color(hex: ChatWallpaper(data: cached).bubbleColorHex)
    }

    /// Fotos y presets: blanco con sombra; color liso: el que contraste.
    var floatingTextColor: Color? {
        switch kind {
        case "photo", "preset": return .white
        case "color": return chatBubbleTextColor(for: Color(hex: colorHex))
        default: return nil
        }
    }
}

struct ChatWallpaperPreset: Identifiable {
    let id: String
    let bubble: String
    var asset: String { "ChatWallpaper" + id.capitalized }
    static let all = [Self(id: "aurora", bubble: "6746A3"), Self(id: "coast", bubble: "007D77"),
                      Self(id: "dune", bubble: "A44732"), Self(id: "forest", bubble: "35624C"),
                      Self(id: "bloom", bubble: "B04A78"), Self(id: "midnight", bubble: "263F63"),
                      Self(id: "lagoon", bubble: "397487"), Self(id: "clay", bubble: "705239"),
                      Self(id: "cloud", bubble: "D3E4EF"), Self(id: "citrus", bubble: "E0B616"),
                      Self(id: "pearl", bubble: "EA2D70"), Self(id: "paper", bubble: "9D6A43"), Self(id: "ink", bubble: "3C3F45"), Self(id: "ripple", bubble: "BFA88A"), Self(id: "prism", bubble: "098DDC"), Self(id: "orbit", bubble: "C256D8"),
                      Self(id: "brush", bubble: "3F6F8F"), Self(id: "watercolor", bubble: "76A529"), Self(id: "sketch", bubble: "00AB8C"), Self(id: "canvas", bubble: "8F394C")]
}

let chatBubblePalette = [
    "3F6F8F", "D3E4EF", "263F63", "D5DFF0",
    "6746A3", "E5D9F5", "35624C", "D8EDD7",
    "007D77", "CEF0EA", "8F394C", "F8D6DF",
    "A44732", "F9DECF", "705239", "EDE2D0",
    "3C3F45", "E2E3E5", "B04A78", "F8DCEC",
    "746133", "F1E8B7", "397487", "D3EDF3",
    "16A466", "D6FCCF", "6044DA", "E6DFFB",
    "C256D8", "EFD8F3", "E46B50", "FBE1D6",
    "2961EB", "D1E6FB", "098DDC", "D0E1EB",
    "00AB8C", "CFFCEC", "CFC300", "FBF8A9",
    "76A529", "E3FEB9", "EA2D70", "FBD9E5",
    "EE003C", "FAD8DE", "EB351B", "FFDCCB",
    "E0B616", "FCF0D6", "9D6A43", "F2DDD0",
    "BFA88A", "EDE8DD", "004F7A", "D0E2E9"
]
let chatBackgroundPalette = ["DCE8E4", "C8E7E4", "D9EBF3", "E7DFEE", "F2E3D5", "F3D9DE",
                             "E6E6E6", "F5EDCB", "C1D6C1", "A7C3CF", "253A40", "282033",
                             "171717", "314939", "60413F", "4A5365", "84705B", "E4D9CD"]

struct ConversationWallpaperView: View {
    let conversationId: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ChatWallpaperStore()
    @State private var draft = ChatWallpaper()
    @State private var selection: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var busy = false
    @State private var edited = false
    @State private var showPreview = false
    @State private var showBubbles = false
    @State private var showBackgrounds = false
    @State private var showColors = false
    @State private var pendingColors = false

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.fixed(160)), GridItem(.fixed(160))], spacing: 12) {
                        Button { showPreview = true } label: {
                            styleCard(draft, image: photo ?? store.image, selected: true)
                        }.buttonStyle(.plain).accessibilityLabel(Text("chat.wallpaper.current")).accessibilityAddTraits(.isSelected)
                        Button { edited = true; draft = ChatWallpaper(); photo = nil; showPreview = true } label: {
                            styleCard(ChatWallpaper(), image: nil, selected: false)
                        }.buttonStyle(.plain).accessibilityLabel(Text("chat.wallpaper.default"))
                        ForEach(ChatWallpaperPreset.all) { preset in
                            Button {
                                edited = true; photo = nil; draft.kind = "preset"; draft.presetId = preset.id
                                draft.bubbleColorHex = preset.bubble; draft.dimming = 0.12; showPreview = true
                            } label: {
                                styleCard(ChatWallpaper(data: ["kind": "preset", "presetId": preset.id, "bubbleColorHex": preset.bubble, "dimming": 0.0]),
                                    image: nil, selected: false)
                            }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey("chat.wallpaper.preset." + preset.id)))
                        }
                    }.scrollTargetLayout().padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
            } header: { Text("chat.wallpaper.styles") } footer: { Text("chat.wallpaper.stylesHint") }
            Section {
                Button { showBubbles = true } label: {
                    HStack {
                        Label("chat.wallpaper.bubbleColor", systemImage: "bubble")
                        Spacer(); Circle().fill(Color(hex: draft.bubbleColorHex)).frame(width: 26, height: 26)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.foregroundStyle(.primary)
                }
                Button { showBackgrounds = true } label: {
                    HStack {
                        Label("chat.wallpaper.background", systemImage: "photo")
                        Spacer(); ChatWallpaperCanvas(wallpaper: draft, image: photo ?? store.image, fallback: Color(uiColor: .systemBackground))
                            .frame(width: 26, height: 36).clipShape(.rect(cornerRadius: 5))
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.foregroundStyle(.primary)
                }
                Button { showPreview = true } label: { Label("chat.wallpaper.previewTitle", systemImage: "eye") }
            } header: { Text("chat.wallpaper.customize") } footer: { Text("chat.wallpaper.private") }
        }
        .modifier(ChatWallpaperScrollEdgeModifier())
        .navigationTitle(Text("chat.wallpaper.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button { save() } label: {
            if busy { ProgressView() } else { Text("chat.wallpaper.save") }
        }.disabled(busy || conversationId.isEmpty || (draft.kind == "photo" && photo == nil && store.image == nil)) } }
        .sheet(isPresented: $showBubbles) {
            ChatWallpaperColorPicker(colors: chatBubblePalette, selected: draft.bubbleColorHex, title: "chat.wallpaper.bubbleColor") { hex in
                edited = true; draft.bubbleColorHex = hex
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showBackgrounds, onDismiss: { if pendingColors { pendingColors = false; showColors = true } }) { backgroundPicker.presentationDetents([.large]) }
        .sheet(isPresented: $showColors) {
            ChatWallpaperColorPicker(colors: chatBackgroundPalette, selected: draft.colorHex, title: "chat.wallpaper.color") { hex in
                edited = true; draft.kind = "color"; draft.colorHex = hex; photo = nil
            }.presentationDetents([.large])
        }
        .sheet(isPresented: $showPreview) {
            ChatWallpaperPreviewEditor(wallpaper: draft, image: photo ?? store.image) { value, cropped in
                edited = true; draft = value; if let cropped { photo = cropped }; showPreview = false; save()
            }.presentationDetents([.large]).presentationDragIndicator(.hidden).interactiveDismissDisabled(busy)
        }
        .task { store.start(conversationId: conversationId) }
        .onReceive(store.$wallpaper) { if !edited { draft = $0 } }
        .onChange(of: selection) { _, item in
            guard let item else { return }; busy = true
            Task {
                defer { busy = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = await Task.detached(priority: .utility, operation: { ChatWallpaperStore.decode(data) }).value else { throw URLError(.cannotDecodeContentData) }
                    edited = true; photo = image; draft.kind = "photo"; showBackgrounds = false
                    // Wait until the picker sheet has dismissed before showing the preview.
                    try await Task.sleep(for: .milliseconds(350)); showPreview = true
                } catch is CancellationError {} catch { showError() }
            }
        }
    }
    private var backgroundPicker: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $selection, matching: .images) { Label("chat.wallpaper.photo", systemImage: "photo.on.rectangle") }.disabled(busy)
                    Button { pendingColors = true; showBackgrounds = false } label: { Label("chat.wallpaper.color", systemImage: "paintpalette") }
                    Button { edited = true; draft.kind = "default"; photo = nil; showBackgrounds = false } label: { Text("chat.wallpaper.default") }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                        ForEach(ChatWallpaperPreset.all) { preset in
                            Button { edited = true; draft.kind = "preset"; draft.presetId = preset.id; photo = nil; showBackgrounds = false } label: {
                                GeometryReader { proxy in
                                    Image(preset.asset).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                                }.aspectRatio(9.0 / 16.0, contentMode: .fit).clipShape(.rect(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey("chat.wallpaper.preset." + preset.id)))
                        }
                    }
                }
            }.modifier(ChatWallpaperScrollEdgeModifier())
                .navigationTitle(Text("chat.wallpaper.background")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("chat.wallpaper.back") { showBackgrounds = false } } }
        }
    }
    private func styleCard(_ value: ChatWallpaper, image: UIImage?, selected: Bool) -> some View {
        ZStack {
            ChatWallpaperCanvas(wallpaper: value, image: image, fallback: Color(uiColor: .systemBackground))
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(.white).frame(width: 48, height: 24).frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: value.bubbleColorHex)).frame(width: 48, height: 24).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(12)
            if selected { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12) }
        }.containerRelativeFrame(.horizontal, count: 3, spacing: 12)
            .frame(height: 160).clipShape(.rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Color.primary : .clear, lineWidth: 2))
    }
    private func showError() {
        InAppNotificationService.shared.showActionToast(InAppActionToast(systemImage: "exclamationmark.triangle", prefix: NSLocalizedString("chat.wallpaper.error", comment: "")))
    }
    private func save() {
        busy = true; let value = draft; let image = value.kind == "photo" ? photo : nil
        Task {
            defer { busy = false }
            do {
                let bytes = await Task.detached(priority: .utility) { image?.jpegData(compressionQuality: 0.85) }.value
                if image != nil && bytes == nil { throw URLError(.cannotDecodeContentData) }
                try await store.save(value, photo: bytes, conversationId: conversationId)
                InAppNotificationService.shared.showActionToast(InAppActionToast(systemImage: "checkmark", prefix: NSLocalizedString("chat.wallpaper.saved", comment: "")))
                dismiss()
            } catch { showError() }
        }
    }
}

struct ChatWallpaperRowAppearance<Content: View>: View {
    @ObservedObject var store: ChatWallpaperStore
    @ViewBuilder let content: () -> Content
    var body: some View { content().environment(\.chatOutgoingBubbleColor, Color(hex: store.wallpaper.bubbleColorHex)) }
}
