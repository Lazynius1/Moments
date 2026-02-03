import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct PhotoTagSelectionView: View {
    @Binding var mediaItem: CreatorMedia
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingUserSearch = false
    @State private var pendingTagLocation: CGPoint? = nil
    @State private var selectedTagId: String? = nil
    
    var body: some View {
        ZStack {
            // 1. Dynamic Background (Immersive)
            (colorScheme == .dark ? Color.black : Color(uiColor: .systemBackground))
                .ignoresSafeArea()
            
            // 2. Main Content
            VStack(spacing: 0) {
                // Header Space
                Spacer().frame(height: 60)
                
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
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    
                    Spacer()
                    
                    Text(NSLocalizedString("creator.tagPeople", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("creator.tag.done", comment: ""))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10) // Adjustment for safe area
                
                Spacer()
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) } // Maintain safe area logic
            
            // 4. Custom Search Sheet Overlay
            if showingUserSearch {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring()) { showingUserSearch = false }
                        pendingTagLocation = nil
                    }
                
                VStack {
                    Spacer()
                    TagUserSearchSheet(onSelect: { user in
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
                        
                        withAnimation(.spring()) {
                            showingUserSearch = false
                            pendingTagLocation = nil
                        }
                    }, onCancel: {
                        withAnimation(.spring()) {
                            showingUserSearch = false
                            pendingTagLocation = nil
                        }
                    })
                    .transition(.move(edge: .bottom))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                onTap()
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Glassmorphic Search Sheet
struct TagUserSearchSheet: View {
    let onSelect: (AppUser) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // Cache recent searches ideally, but using direct firestore for now
    private let firestoreService = FirestoreService()
    
    var body: some View {
        VStack(spacing: 20) {
            // Handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            
            // Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("", text: $searchText)
                    .placeholder(when: searchText.isEmpty) {
                        Text(NSLocalizedString("creator.tag.search", comment: "")).foregroundColor(.secondary)
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
            }
            .padding()
            .background(Color.primary.opacity(0.05)) // Dynamic subtle background
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Results
            if isSearching {
                ProgressView()
                    .tint(.primary)
                    .frame(height: 100)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                Text(NSLocalizedString("common.noResults", value: "No users found", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(searchResults, id: \.id) { user in
                            Button(action: { onSelect(user) }) {
                                HStack(spacing: 12) {
                                    // Avatar
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
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                    
                                    // Info
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.username)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Add Icon
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(Color.primary.opacity(0.3))
                                }
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxHeight: 350)
            }
        }
        .padding(.bottom, 20)
        .background(.ultraThinMaterial) // Adapts to light/dark
        .cornerRadius(24, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.1 : 0.3), radius: 10, x: 0, y: -5)
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
