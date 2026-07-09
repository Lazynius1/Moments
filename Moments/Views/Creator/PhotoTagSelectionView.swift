import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct PhotoTagSelectionView: View {
    @Binding var mediaItem: CreatorMedia
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingUserSearch = false
    @State private var pendingTagLocation: CGPoint? = nil
    @State private var selectedTagId: String? = nil
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            // 2. Main Content
            VStack(spacing: 0) {
                // Header Space
                Spacer().frame(height: 84)
                
                // Image Container
                ZStack {
                    // The Photo
                    Image(uiImage: mediaItem.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12) // Subtle corner radius for modern feel
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4) // Shadow for depth in light mode
                        .overlay(
                            // Gesture Reader & Tags
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        let x = location.x / geo.size.width
                                        let y = location.y / geo.size.height
                                        addTagAt(x: x, y: y)
                                    }
                                
                                // Existing Tags
                                ForEach(mediaItem.tags ?? []) { tag in
                                    TagView(tag: tag, isSelected: selectedTagId == tag.id, containerSize: geo.size) {
                                        selectedTagId = tag.id
                                    } onDelete: {
                                        removeTag(tag.id)
                                    }
                                }

                                if let pendingLocation = pendingTagLocation {
                                    PendingTagMarker(
                                        location: pendingLocation,
                                        containerSize: geo.size
                                    )
                                }
                            }
                        )
                }
                .padding(.horizontal)
                .frame(maxHeight: .infinity)

                // Footer Hint
                Text(NSLocalizedString("creator.tag.instructions", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 40)
            }
            
            // 3. Floating Custom Header
            VStack {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button(action: { closeEditor() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(NSLocalizedString("creator.tagPeople", comment: ""))
                            .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Spacer()

                        Button(action: { closeEditor() }) {
                            Text(NSLocalizedString("creator.tag.done", comment: ""))
                                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .momentsChromeGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                Spacer()
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) } // Maintain safe area logic
            
            // 4. Search Overlay
            if showingUserSearch {
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08).ignoresSafeArea()
                    .onTapGesture {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) { showingUserSearch = false }
                        pendingTagLocation = nil
                    }
                
                VStack {
                    Spacer()
                    TagUserSearchOverlay(onSelect: { user in
                        if let location = pendingTagLocation {
                            let newTag = PhotoTag(
                                userId: user.id,
                                username: user.username,
                                x: Double(location.x),
                                y: Double(location.y)
                            )
                            var currentTags = mediaItem.tags ?? []
                            currentTags.append(newTag)
                            mediaItem.tags = currentTags
                            
                            // Haptic success
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                        
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            showingUserSearch = false
                            pendingTagLocation = nil
                        }
                    }, onCancel: {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            showingUserSearch = false
                            pendingTagLocation = nil
                        }
                    })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(2)
            }
        }
    }
    
    private func addTagAt(x: Double, y: Double) {
        pendingTagLocation = CGPoint(x: x, y: y)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingUserSearch = true
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func removeTag(_ id: String) {
        var currentTags = mediaItem.tags ?? []
        currentTags.removeAll(where: { $0.id == id })
        mediaItem.tags = currentTags
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func closeEditor() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

struct PendingTagMarker: View {
    let location: CGPoint
    let containerSize: CGSize

    var body: some View {
        let xPos = location.x * containerSize.width
        let yPos = location.y * containerSize.height

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 28, height: 28)

            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        .position(x: xPos, y: yPos)
        .allowsHitTesting(false)
        .transition(MotionPolicy.Transition.enterPop)
    }
}

// MARK: - Individual Tag View (Refined)
struct TagView: View {
    let tag: PhotoTag
    let isSelected: Bool
    let containerSize: CGSize
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        let xPos = CGFloat(tag.x) * containerSize.width
        let yPos = CGFloat(tag.y) * containerSize.height
        
        VStack(spacing: 0) {
            // Tag Bubble
            HStack(spacing: 8) {
                Text(tag.username)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                if isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 20, height: 20)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial) // Glass effect
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            
            // Triangle Pointer
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundColor(.secondary) // Match glass somewhat
                .rotationEffect(.degrees(180))
                .offset(y: -3)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .position(x: xPos, y: yPos - 35)
        .onTapGesture {
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                onTap()
            }
        }
        .transition(MotionPolicy.Transition.enterPop)
    }
}

// MARK: - Inline Search Overlay
struct TagUserSearchOverlay: View {
    let onSelect: (AppUser) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // Cache recent searches ideally, but using direct firestore for now
    private let firestoreService = FirestoreService()

    private var shouldShowResultsPanel: Bool {
        isSearching || !searchText.isEmpty
    }

    private var resultsPanelHeight: CGFloat {
        let rowHeight: CGFloat = 67
        let visibleRows = min(max(searchResults.count, 1), 3)
        return CGFloat(visibleRows) * rowHeight
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("", text: $searchText)
                    .placeholder(when: searchText.isEmpty) {
                        Text(NSLocalizedString("creator.tag.search", comment: ""))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onChange(of: searchText) { _, newValue in
                        searchUsers(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .momentsChromeGlass(in: Capsule(), interactive: true)

            if shouldShowResultsPanel {
                Group {
                    if isSearching {
                        UserRowSkeletonList(rows: 2, avatarSize: 42)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 88)
                    } else if searchResults.isEmpty {
                        Text(NSLocalizedString("common.noResults", value: "No users found", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 88)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(searchResults, id: \.id) { user in
                                    Button(action: { onSelect(user) }) {
                                        HStack(spacing: 12) {
                                            Group {
                                                if let profileUrl = user.profileImagePath, let url = URL(string: profileUrl) {
                                                    AsyncImage(url: url) { img in
                                                        img.resizable().aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Color.gray.opacity(0.3)
                                                    }
                                                } else {
                                                    Image(systemName: "person.circle.fill")
                                                        .resizable()
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            .frame(width: 42, height: 42)
                                            .clipShape(Circle())

                                            Text(user.username)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.primary)

                                            Spacer()

                                            Image(systemName: "plus")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)
                                                .frame(width: 28, height: 28)
                                                .momentsChromeGlass(in: Circle(), interactive: true)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if user.id != searchResults.last?.id {
                                        Divider().opacity(0.25)
                                    }
                                }
                            }
                        }
                        .frame(height: resultsPanelHeight)
                    }
                }
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .onAppear {
            isSearchFocused = true // Auto focus
        }
    }
    
    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        firestoreService.searchUsers(query: query, limit: 10) { result in
            DispatchQueue.main.async {
                isSearching = false
                if case .success(let users) = result {
                    searchResults = users
                }
            }
        }
    }
}



fileprivate func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.impactOccurred()
}
