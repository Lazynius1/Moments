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

    init() {}
    init(data: [String: Any]) {
        kind = data["kind"] as? String ?? "default"
        colorHex = data["colorHex"] as? String ?? "DCE8E4"
        storagePath = data["storagePath"] as? String ?? ""
        dimming = min(0.75, max(0, data["dimming"] as? Double ?? 0.2))
    }
    var fields: [String: Any] {
        ["kind": kind, "colorHex": colorHex, "storagePath": storagePath,
         "dimming": dimming, "updatedAt": FieldValue.serverTimestamp()]
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
        if let data = UserDefaults.standard.data(forKey: key), let cached = try? JSONDecoder().decode(ChatWallpaper.self, from: data) {
            apply(cached)
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

struct ConversationWallpaperView: View {
    let conversationId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = ChatWallpaperStore()
    @State private var draft = ChatWallpaper()
    @State private var selection: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var drag: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var busy = false
    @State private var edited = false
    private let previewSize = CGSize(width: 198, height: 352)
    private let colors = ["DCE8E4", "E7DFEE", "DAE7F1", "F2E3D5", "E6E6E6", "253A40", "282033", "171717"]

    var body: some View {
        Form {
            Section {
                Text("chat.wallpaper.private").font(.footnote).foregroundStyle(.secondary)
                preview.frame(maxWidth: .infinity)
            }
            Section {
                Button("chat.wallpaper.default") { edited = true; draft.kind = "default"; photo = nil; drag = .zero; zoom = 1 }
                HStack {
                    Text("chat.wallpaper.color")
                    Spacer()
                    ColorPicker("chat.wallpaper.color", selection: colorBinding, supportsOpacity: false).labelsHidden()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32))], spacing: 12) {
                    ForEach(colors, id: \.self) { hex in
                        Button { edited = true; draft.kind = "color"; draft.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(draft.kind == "color" && draft.colorHex == hex ? Color.primary : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(Text("chat.wallpaper.color"))
                    }
                }
                PhotosPicker(selection: $selection, matching: .images) { Label("chat.wallpaper.photo", systemImage: "photo") }.disabled(busy)
            }
            if draft.kind == "photo", (photo ?? store.image) != nil {
                Section {
                    Text("chat.wallpaper.crop").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { zoom }, set: { value in
                        edited = true; zoom = value; clampDrag(); dragStart = drag
                    }), in: 1...3)
                }
            }
            if draft.kind != "default" {
                Section("chat.wallpaper.dimming") { Slider(value: Binding(get: { draft.dimming }, set: { edited = true; draft.dimming = $0 }), in: 0...0.75) }
            }
        }
        .navigationTitle(Text("chat.wallpaper.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: {
                    if busy { ProgressView() } else { Text("chat.wallpaper.save") }
                }.disabled(busy || conversationId.isEmpty || (draft.kind == "photo" && photo == nil && store.image == nil))
            }
        }
        .task { store.start(conversationId: conversationId) }
        .onReceive(store.$wallpaper) { value in
            if !edited { draft = value }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = await Task.detached(priority: .utility, operation: { ChatWallpaperStore.decode(data) }).value else { throw URLError(.cannotDecodeContentData) }
                    edited = true; photo = image; draft.kind = "photo"; zoom = 1; drag = .zero; dragStart = .zero
                } catch { showErrorBanner() }
            }
        }
    }

    private var preview: some View {
        ZStack {
            ChatWallpaperCanvas(wallpaper: draft, image: photo ?? store.image,
                fallback: AdaptiveColors(colorScheme: colorScheme).chatBackground[0], zoom: zoom, offset: drag)
            VStack(alignment: .leading, spacing: 12) {
                Text("chat.wallpaper.preview").font(.system(size: 16)).padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20))
                HStack { Spacer(); Text("Moments").font(.system(size: 16)).foregroundStyle(.white).padding(12).background(Color(hex: "3E718D"), in: .rect(cornerRadius: 20)) }
                Spacer()
            }.padding(12).allowsHitTesting(false)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(.rect(cornerRadius: 20))
        .gesture(DragGesture().onChanged { value in
            guard (photo ?? store.image) != nil, draft.kind == "photo" else { return }
            edited = true
            drag = CGSize(width: dragStart.width + value.translation.width, height: dragStart.height + value.translation.height); clampDrag()
        }.onEnded { _ in dragStart = drag })
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            guard draft.kind == "photo", (photo ?? store.image) != nil else { return }
            edited = true
            if pinchStart == nil { pinchStart = zoom }
            zoom = min(3, max(1, (pinchStart ?? zoom) * value.magnification))
            clampDrag()
        }.onEnded { _ in pinchStart = nil; dragStart = drag })
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { Color(hex: draft.colorHex) }, set: { value in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            edited = true
            draft.kind = "color"
            draft.colorHex = String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        })
    }
    private func clampDrag() {
        guard let photo = photo ?? store.image else { return }
        let fill = max(previewSize.width / photo.size.width, previewSize.height / photo.size.height)
        let x = max(0, (photo.size.width * fill * zoom - previewSize.width) / 2)
        let y = max(0, (photo.size.height * fill * zoom - previewSize.height) / 2)
        drag.width = min(x, max(-x, drag.width)); drag.height = min(y, max(-y, drag.height))
    }
    private func showErrorBanner() {
        InAppNotificationService.shared.showActionToast(InAppActionToast(systemImage: "exclamationmark.triangle", prefix: NSLocalizedString("chat.wallpaper.error", comment: "Wallpaper error")))
    }
    private func save() {
        busy = true
        let value = draft
        let image = photo ?? ((zoom != 1 || drag != .zero) ? store.image : nil)
        let cropZoom = zoom
        let cropDrag = drag
        Task {
            defer { busy = false }
            do {
                let bytes = await Task.detached(priority: .userInitiated) { () -> Data? in
                    guard let image, value.kind == "photo" else { return nil }
                    let size = CGSize(width: 1080, height: 1920)
                    let fill = max(size.width / image.size.width, size.height / image.size.height) * cropZoom
                    let drawn = CGSize(width: image.size.width * fill, height: image.size.height * fill)
                    let factor = size.width / 198
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                    return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
                        image.draw(in: CGRect(x: (size.width - drawn.width) / 2 + cropDrag.width * factor,
                            y: (size.height - drawn.height) / 2 + cropDrag.height * factor, width: drawn.width, height: drawn.height))
                    }
                }.value
                if image != nil && value.kind == "photo" && bytes == nil { throw URLError(.cannotDecodeContentData) }
                try await store.save(value, photo: bytes, conversationId: conversationId)
                InAppNotificationService.shared.showActionToast(InAppActionToast(systemImage: "checkmark", prefix: NSLocalizedString("chat.wallpaper.saved", comment: "Wallpaper saved")))
                dismiss()
            } catch { showErrorBanner() }
        }
    }
}
