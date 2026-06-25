import SwiftUI
import MapKit
import Kingfisher

struct EditMomentPayload {
    let content: String
    let audience: ContentAudience
    let customListId: String?
    let customViewers: [String]
    let taggedUsers: [String]
    let mentionedUsers: [String]
    let locationName: String
    let locationCoordinate: CLLocationCoordinate2D?
    let mediaItems: [MediaItem]?
}

struct EditMomentView: View {
    let moment: Moment
    let onSave: (EditMomentPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var editedContent: String
    @State private var selectedAudience: ContentAudience
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var customSelectedUsers: [String]
    @State private var initialCustomSelectedUsers: [String]
    @State private var taggedUsers: [String]
    @State private var locationName: String
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var editedMediaItems: [MediaItem]
    @State private var isSaving = false
    @State private var showingAudiencePicker = false
    @State private var showingTagPicker = false
    @State private var showingLocationPicker = false

    private let firestoreService = FirestoreService.shared

    init(moment: Moment, onSave: @escaping (EditMomentPayload) -> Void) {
        self.moment = moment
        self.onSave = onSave
        _editedContent = State(initialValue: moment.content)
        _selectedAudience = State(initialValue: ContentAudience(rawValue: moment.audience ?? ContentAudience.everyone.rawValue) ?? .everyone)
        _selectedListId = State(initialValue: moment.customListId)
        _selectedListName = State(initialValue: nil)
        _customSelectedUsers = State(initialValue: [])
        _initialCustomSelectedUsers = State(initialValue: [])
        _taggedUsers = State(initialValue: moment.taggedUsers ?? [])
        _locationName = State(initialValue: moment.location ?? "")
        _selectedLocation = State(initialValue: moment.locationCoordinate?.toCLLocationCoordinate2D)
        _editedMediaItems = State(initialValue: moment.mediaItems ?? [])
    }

    var body: some View {
        NavigationView {
            ZStack {
                background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        EditMomentPreviewCard(moment: moment)
                            .padding(.top, 12)

                        textSection
                        detailsSection

                        if isAudienceLocked {
                            moderationFootnote
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .principal) {
                    Text(NSLocalizedString("editMoment.title", comment: "Edit moment"))
                        .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveChanges) {
                        Text(NSLocalizedString("editMoment.save", comment: "Save"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundColor(hasChanges && !isSaving
                                ? (colorScheme == .dark ? .white : .black)
                                : (colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35)))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }
                    .disabled(!hasChanges || isSaving)
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingAudiencePicker) {
                AudienceSelectionView(
                    selectedAudience: $selectedAudience,
                    selectedListId: $selectedListId,
                    selectedListName: $selectedListName,
                    customSelectedUsers: $customSelectedUsers
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingTagPicker) {
                EditMomentPhotoTagSheet(
                    moment: moment,
                    mediaItems: $editedMediaItems,
                    taggedUsers: $taggedUsers
                )
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(
                    selectedLocation: $selectedLocation,
                    locationName: $locationName
                )
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(colorScheme == .dark ? .white : .black)
                        Text(NSLocalizedString("editMoment.saving", comment: "Saving"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .task {
                hydrateCustomAudienceIfNeeded()
            }
            .onChange(of: selectedAudience) { _, _ in
                hydrateCustomAudienceIfNeeded()
            }
            .onChange(of: selectedListId) { _, _ in
                hydrateCustomAudienceIfNeeded()
            }
        }
    }

    private var background: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(hex: "071118"), Color(hex: "0F1822"), Color(hex: "121A25")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "F5F7FB"), Color.white, Color(hex: "EDF1F7")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: NSLocalizedString("editMoment.section.text", value: "Texto", comment: "Edit moment text section"),
                subtitle: NSLocalizedString("editMoment.placeholder", comment: "Placeholder")
            )

            ZStack(alignment: .topLeading) {
                if editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(NSLocalizedString("editMoment.placeholder", comment: "Placeholder"))
                        .font(.system(size: legacyPoppinsSize(16)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.32))
                        .padding(.top, 12)
                        .padding(.leading, 10)
                }

                TextEditor(text: $editedContent)
                    .font(.system(size: legacyPoppinsSize(16)))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 130)
            }
            .padding(10)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: NSLocalizedString("editMoment.section.details", value: "Detalles", comment: "Edit moment details section"),
                subtitle: NSLocalizedString("editMoment.section.details.subtitle", value: "Audiencia, ubicación y personas", comment: "Edit moment details subtitle")
            )

            VStack(spacing: 4) {
                detailRow(
                    audience: selectedAudience,
                    title: NSLocalizedString("audience.title", comment: "Audience"),
                    value: audienceSummaryText,
                    subtitle: isAudienceLocked ? NSLocalizedString("editMoment.audience.locked", value: "Bloqueado por moderación", comment: "Audience locked by moderation") : selectedAudience.description,
                    locked: isAudienceLocked,
                    action: {
                        if !isAudienceLocked {
                            showingAudiencePicker = true
                        }
                    }
                )

                detailRow(
                    icon: "mappin.and.ellipse",
                    title: NSLocalizedString("editMoment.location.title", value: "Ubicación", comment: "Edit moment location title"),
                    value: locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSLocalizedString("editMoment.location.add", value: "Añadir ubicación", comment: "Add location") : locationName,
                    subtitle: selectedLocation == nil ? NSLocalizedString("editMoment.location.subtitle.empty", value: "Puedes añadir o cambiar el lugar", comment: "Location subtitle empty") : NSLocalizedString("editMoment.location.subtitle.set", value: "Toca para cambiar o quitar", comment: "Location subtitle set"),
                    action: { showingLocationPicker = true }
                )

                detailRow(
                    icon: "person.crop.circle.badge.plus",
                    title: NSLocalizedString("editMoment.tags.title", value: "Etiquetas", comment: "Edit moment tags title"),
                    value: tagsSummaryText,
                    subtitle: NSLocalizedString("editMoment.tags.subtitle", value: "Añade o quita personas etiquetadas", comment: "Edit moment tags subtitle"),
                    action: { showingTagPicker = true }
                )
            }
        }
    }

    private var moderationFootnote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.65))

            Text(NSLocalizedString("editMoment.audience.locked.explainer", value: "Este momento fue limitado por moderación y su audiencia no se puede cambiar desde aquí.", comment: "Audience locked explainer"))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text(subtitle)
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(
        icon: String? = nil,
        audience: ContentAudience? = nil,
        title: String,
        value: String,
        subtitle: String,
        locked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let audience {
                        AudienceIconView(
                            audience: audience,
                            size: AudienceIconMetrics.row,
                            colorScheme: colorScheme
                        )
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.62))

                    Text(value)
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.48))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.32))
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private var audienceSummaryText: String {
        switch selectedAudience {
        case .customList:
            return selectedListName ?? NSLocalizedString("audience.type.customList", comment: "Custom list audience type")
        case .custom:
            if customSelectedUsers.isEmpty {
                return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
            }
            return String(format: NSLocalizedString("audience.people.count", comment: "People count"), customSelectedUsers.count)
        default:
            return selectedAudience.title
        }
    }

    private var tagsSummaryText: String {
        if taggedUsers.isEmpty {
            return NSLocalizedString("editMoment.tags.add", value: "Añadir personas", comment: "Add tagged people")
        }
        return String(format: NSLocalizedString("editMoment.tags.count", value: "%d personas", comment: "Tagged people count"), taggedUsers.count)
    }

    private var isAudienceLocked: Bool {
        moment.isModerationHidden == true
    }

    private var hasChanges: Bool {
        if editedContent != moment.content { return true }
        if selectedAudience.rawValue != (moment.audience ?? ContentAudience.everyone.rawValue) { return true }
        if selectedListId != moment.customListId { return true }
        if selectedAudience == .custom && Set(customSelectedUsers) != Set(initialCustomSelectedUsers) { return true }
        if Set(taggedUsers) != Set(moment.taggedUsers ?? []) { return true }
        if normalizedPhotoTags != normalizedMomentPhotoTags { return true }
        if normalizedLocationName != normalizedMomentLocationName { return true }
        if selectedLocation?.latitude != moment.locationCoordinate?.latitude { return true }
        if selectedLocation?.longitude != moment.locationCoordinate?.longitude { return true }
        return false
    }

    private var normalizedLocationName: String {
        locationName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedMomentLocationName: String {
        (moment.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPhotoTags: [PhotoTag] {
        editedMediaItems.first(where: { $0.type == .image })?.tags ?? []
    }

    private var normalizedMomentPhotoTags: [PhotoTag] {
        moment.mediaItems?.first(where: { $0.type == .image })?.tags ?? []
    }

    private func hydrateCustomAudienceIfNeeded() {
        if selectedAudience == .custom {
            firestoreService.getCustomAudience(contentType: "moment", authorId: moment.authorId) { viewers in
                DispatchQueue.main.async {
                    self.customSelectedUsers = viewers
                    self.initialCustomSelectedUsers = viewers
                }
            }
        }

        if selectedAudience == .customList,
           let selectedListId,
           selectedListName == nil {
            firestoreService.fetchCustomListDetails(listId: selectedListId, ownerId: moment.authorId) { result in
                guard case .success(let list) = result else { return }
                DispatchQueue.main.async {
                    self.selectedListName = list.name
                }
            }
        }
    }

    private func saveChanges() {
        guard hasChanges else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            isSaving = true
        }

        let contentSnapshot = editedContent
        let audienceSnapshot = selectedAudience
        let selectedListSnapshot = selectedListId
        let customViewersSnapshot = selectedAudience == .custom ? customSelectedUsers : []
        let taggedUsersSnapshot = taggedUsers
        let locationNameSnapshot = normalizedLocationName
        let locationSnapshot = selectedLocation
        let mediaItemsSnapshot = editedMediaItems

        Task {
            let mentionIds = await MomentMentionResolver.resolveUserIds(from: contentSnapshot)
            let payload = EditMomentPayload(
                content: contentSnapshot,
                audience: audienceSnapshot,
                customListId: audienceSnapshot == .customList ? selectedListSnapshot : nil,
                customViewers: customViewersSnapshot,
                taggedUsers: taggedUsersSnapshot,
                mentionedUsers: mentionIds,
                locationName: locationNameSnapshot,
                locationCoordinate: locationSnapshot,
                mediaItems: mediaItemsSnapshot
            )

            await MainActor.run {
                onSave(payload)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSaving = false
                    }
                    dismiss()
                }
            }
        }
    }
}

private struct EditMomentPhotoTagSheet: View {
    let moment: Moment
    @Binding var mediaItems: [MediaItem]
    @Binding var taggedUsers: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var creatorMedia: CreatorMedia?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        NavigationView {
            ZStack {
                Group {
                    if let creatorMediaBinding = creatorMediaBinding {
                        PhotoTagSelectionView(
                            mediaItem: creatorMediaBinding,
                            onClose: { dismiss() }
                        )
                    } else if isLoading {
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(colorScheme == .dark ? .white : .black)
                            Text(NSLocalizedString("editMoment.tags.loading", value: "Cargando imagen…", comment: "Loading image for tag editor"))
                                .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.66))
                        }
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: loadFailed ? "exclamationmark.triangle" : "photo")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.55))

                            Text(NSLocalizedString("editMoment.tags.unavailable", value: "No hemos podido abrir el editor de etiquetas.", comment: "Tags editor unavailable"))
                                .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)

                            Button(action: { dismiss() }) {
                                Text(NSLocalizedString("common.ok", value: "OK", comment: "OK"))
                                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .momentsChromeGlass(in: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 28)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadEditorMediaIfNeeded()
            }
            .onDisappear {
                syncBackIfNeeded()
            }
        }
    }

    private var creatorMediaBinding: Binding<CreatorMedia>? {
        guard creatorMedia != nil else { return nil }
        return Binding(
            get: { creatorMedia! },
            set: { creatorMedia = $0 }
        )
    }

    private var editableImageMediaItem: MediaItem? {
        mediaItems.first(where: { $0.type == .image && !($0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) })
            ?? moment.mediaItems?.first(where: { $0.type == .image && !($0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) })
    }

    private var preservedLegacyTaggedUsers: [String] {
        let originalSpatialTaggedUsers = Set((moment.mediaItems ?? []).flatMap { $0.tags ?? [] }.map(\.userId))
        let originalTaggedUsers = Set(moment.taggedUsers ?? [])
        return Array(originalTaggedUsers.subtracting(originalSpatialTaggedUsers))
    }

    private func loadEditorMediaIfNeeded() {
        guard creatorMedia == nil, !isLoading else { return }
        guard let item = editableImageMediaItem,
              let url = URL(string: item.url) else {
            loadFailed = true
            return
        }

        isLoading = true
        KingfisherManager.shared.retrieveImage(with: url) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let value):
                    let ratio = item.resolvedAspectRatioValue ?? max(value.image.size.width / max(value.image.size.height, 1), 0.8)
                    creatorMedia = CreatorMedia(
                        id: item.id,
                        image: value.image,
                        videoURL: nil,
                        type: .image,
                        aspectRatio: .fromRatio(ratio),
                        recommendedAspectRatio: .fromRatio(ratio),
                        hasEdits: false,
                        thumbnailURL: item.thumbnailUrl.flatMap(URL.init(string:)),
                        tags: item.tags
                    )
                case .failure:
                    loadFailed = true
                }
            }
        }
    }

    private func syncBackIfNeeded() {
        guard let creatorMedia else { return }
        guard let imageIndex = mediaItems.firstIndex(where: { $0.id == creatorMedia.id }) else { return }

        let updatedTags = creatorMedia.tags
        let currentItem = mediaItems[imageIndex]
        mediaItems[imageIndex] = MediaItem(
            id: currentItem.id,
            type: currentItem.type,
            url: currentItem.url,
            aspectRatio: currentItem.aspectRatio,
            thumbnailUrl: currentItem.thumbnailUrl,
            videoDuration: currentItem.videoDuration,
            videoFileSize: currentItem.videoFileSize,
            videoResolution: currentItem.videoResolution,
            tags: updatedTags,
            moderationState: currentItem.moderationState,
            moderationReason: currentItem.moderationReason,
            moderationCategory: currentItem.moderationCategory,
            moderationConfidence: currentItem.moderationConfidence,
            moderatedAt: currentItem.moderatedAt
        )

        let spatialTaggedUsers = mediaItems
            .flatMap { $0.tags ?? [] }
            .map(\.userId)
        taggedUsers = Array(Set(spatialTaggedUsers).union(preservedLegacyTaggedUsers))
    }
}

private struct EditMomentPreviewCard: View {
    let moment: Moment

    var body: some View {
        VStack(spacing: 12) {
            if let imageURL = moment.previewImageURLString, let url = URL(string: imageURL) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(moment.primaryVisibleMediaItem?.resolvedAspectRatioValue ?? 4.0 / 5.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.gray.opacity(0.18))
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    )
            }
        }
        .padding(10)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
