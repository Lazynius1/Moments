import FirebaseAuth
import Kingfisher
import SwiftUI

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

struct ModernEmojiSliderInputView: View {
    let onSelect: (String, String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var prompt = ""
    @State private var selectedEmoji = "😍"
    @State private var isEmojiPickerExpanded = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case prompt
    }

    private let presetEmojis = ["😍", "🔥", "😂", "🥹", "🤩", "😮", "😢", "👏", "💯", "🤯"]

    private var palette: StickerDetailPalette {
        StickerDetailPalette(colorScheme: colorScheme)
    }

    private var resolvedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedEmoji: String {
        selectedEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "😍" : selectedEmoji
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("stickerview.createEmojiSlider")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                Text("stickerview.emojiSlider.subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.99, green: 0.56, blue: 0.21))
                        .frame(width: 18, alignment: .leading)

                    TextField(NSLocalizedString("stickerview.emojiSlider.promptPlaceholder", comment: "Emoji slider prompt placeholder"), text: $prompt)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(palette.primaryText)
                        .focused($focusedField, equals: .prompt)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(focusedField == .prompt ? Color(red: 0.99, green: 0.56, blue: 0.21) : palette.fieldStroke, lineWidth: 1.5)
                        )
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presetEmojis, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            HapticManager.shared.lightImpact()
                        } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(palette.fieldFill)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        selectedEmoji == emoji ? Color(red: 0.99, green: 0.56, blue: 0.21) : palette.fieldStroke,
                                                        lineWidth: selectedEmoji == emoji ? 2 : 1
                                                    )
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                isEmojiPickerExpanded.toggle()
                            }
                            HapticManager.shared.lightImpact()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(palette.primaryText)
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(palette.fieldFill)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    (isEmojiPickerExpanded || !presetEmojis.contains(selectedEmoji))
                                                    ? Color(red: 0.99, green: 0.56, blue: 0.21)
                                                    : palette.fieldStroke,
                                                    lineWidth: (isEmojiPickerExpanded || !presetEmojis.contains(selectedEmoji)) ? 2 : 1
                                                )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }

                if isEmojiPickerExpanded {
                    StickerEmojiPalettePicker(selectedEmoji: $selectedEmoji) { emoji in
                        selectedEmoji = emoji
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isEmojiPickerExpanded = false
                        }
                        HapticManager.shared.lightImpact()
                    }
                }

                StickerEmojiSliderCardView(
                    prompt: resolvedPrompt,
                    emoji: resolvedEmoji,
                    value: 0.5
                )
                .frame(width: emojiSliderRenderingSize(prompt: resolvedPrompt).width, height: emojiSliderRenderingSize(prompt: resolvedPrompt).height)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

                Button(action: {
                    onSelect(resolvedPrompt, resolvedEmoji)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "face.smiling.inverse")
                            .font(.system(size: 18, weight: .medium))

                        Text("stickerview.createEmojiSlider")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.99, green: 0.56, blue: 0.21))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focusedField = .prompt
        }
    }
}
struct ModernQuizInputView: View {
    let onSelect: (String, [String], Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @State private var options = ["", "", ""]
    @State private var correctIndex = 0
    @FocusState private var focusedField: Int?

    private var isDarkMode: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("quiz.title", comment: ""))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(isDarkMode ? .white : .black)

                Text(NSLocalizedString("quiz.subtitle", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDarkMode ? .white.opacity(0.6) : .black.opacity(0.5))
            }
            .padding(.bottom, 10)

            // Campo de Pregunta
            VStack(alignment: .leading, spacing: 10) {
                TextField(NSLocalizedString("quiz.question.placeholder", comment: ""), text: $question)
                    .font(.system(size: 18, weight: .bold))
                    .padding()
                    .background(Color.white.opacity(isDarkMode ? 0.1 : 0.05))
                    .cornerRadius(16)
                    .focused($focusedField, equals: -1)

                // Opciones dinámicas
                ForEach(0..<options.count, id: \.self) { index in
                    quizOptionField(index: index)
                }

                // ✅ BOTÓN PARA AÑADIR OPCIÓN EXTRA (Máximo 4) - Liquid Glass Style
                if options.count < 4 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            options.append("")
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(NSLocalizedString("quiz.addOption", comment: ""))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(isDarkMode ? .white : .black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            Color.clear.liquidGlass(in: Capsule(), interactive: true)
                        )
                    }
                    .padding(.top, 4)
                }
            }

            Button(action: {
                let filledOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !question.isEmpty && filledOptions.count >= 2 {
                    onSelect(question, filledOptions, min(correctIndex, filledOptions.count - 1))
                }
            }) {
                Text(NSLocalizedString("quiz.done", comment: ""))
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing))
                    )
                    .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.top, 10)
            .disabled(question.isEmpty || options.filter({!$0.isEmpty}).count < 2)
            .opacity(question.isEmpty || options.filter({!$0.isEmpty}).count < 2 ? 0.5 : 1.0)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        // ✅ TAP FUERA PARA BAJAR TECLADO
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            focusedField = -1
        }
    }

    @ViewBuilder
    private func quizOptionField(index: Int) -> some View {
        HStack {
            TextField(NSLocalizedString("quiz.option.placeholder", comment: "") + " \(index + 1)", text: $options[index])
                .font(.system(size: 16, weight: .medium))
                .focused($focusedField, equals: index)

            Spacer()

            Button(action: {
                correctIndex = index
                HapticManager.shared.lightImpact()
            }) {
                Image(systemName: correctIndex == index ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(correctIndex == index ? .green : .gray.opacity(0.5))
            }
        }
        .padding()
        .background(Color.white.opacity(isDarkMode ? 0.08 : 0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(correctIndex == index ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}


struct ModernPollInputView: View {
    let onSelect: ([String]) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var question = ""
    @State private var option1 = ""
    @State private var option2 = ""
    @FocusState private var focusedField: Field?

    private let maxPollQuestionLength = 44
    private let maxPollOptionLength = 28

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
                        .onChange(of: question) { newValue in
                            if newValue.count > maxPollQuestionLength {
                                question = String(newValue.prefix(maxPollQuestionLength))
                            }
                        }
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
                            .onChange(of: option1) { newValue in
                                if newValue.count > maxPollOptionLength {
                                    option1 = String(newValue.prefix(maxPollOptionLength))
                                }
                            }
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
                            .onChange(of: option2) { newValue in
                                if newValue.count > maxPollOptionLength {
                                    option2 = String(newValue.prefix(maxPollOptionLength))
                                }
                            }
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

    private let maxQuestionLength = 48

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
                        .onChange(of: question) { newValue in
                            if newValue.count > maxQuestionLength {
                                question = String(newValue.prefix(maxQuestionLength))
                            }
                        }
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

