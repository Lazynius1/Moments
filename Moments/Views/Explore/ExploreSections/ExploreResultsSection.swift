import SwiftUI

// MARK: - 🎨 Componente de resultados de búsqueda mejorado
struct SmartSearchResultsView: View {
    let searchQuery: String
    let users: [AppUser]
    let moments: [Moment]
    let userButtonStates: [String: FollowButtonState]
    let currentUserInterests: [String]
    let onFollowUser: (String) -> Void
    let onUserTap: (AppUser) -> Void
    var zoomNamespace: Namespace.ID? = nil
    var profileZoomNamespace: Namespace.ID? = nil
    let onMomentTap: (Moment, Int, [Moment]) -> Void

    var searchType: SearchDisplayType {
        if searchQuery.hasPrefix("#") {
            return .hashtag
        } else if searchQuery.hasPrefix("@") {
            return .users
        } else if !users.isEmpty && !moments.isEmpty {
            return .mixed
        } else if !users.isEmpty {
            return .users
        } else if !moments.isEmpty {
            return .moments
        } else {
            return .empty
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header con tipo de búsqueda
            searchHeader

            // Resultados según el tipo
            switch searchType {
            case .hashtag:
                hashtagResultsView

            case .users:
                usersResultsView

            case .moments:
                momentsResultsView

            case .mixed:
                mixedResultsView

            case .empty:
                EmptySearchView()
            }
        }
    }

    // ✅ Header inteligente
    private var searchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Icono según tipo de búsqueda
            Image(systemName: headerIcon)
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: "667eea"))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .padding(.horizontal, 24)
    }

    // ✅ Resultados de hashtags
    private var hashtagResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(format: NSLocalizedString("explore.search.moments", comment: "Search moments"), searchQuery))
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(moments.count)")
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(Color(hex: "667eea"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "667eea").opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)

            // Grid de momentos
            MomentsSearchGrid(moments: moments, zoomNamespace: zoomNamespace, onMomentTap: onMomentTap)
        }
    }

    // ✅ Resultados de usuarios — mismos MiniUserCard que `.mixed` (sin SearchResultCard)
    private var usersResultsView: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: 16, alignment: .top)],
            spacing: 16
        ) {
            ForEach(users) { user in
                MiniUserCard(
                    user: user,
                    onTap: { onUserTap(user) }
                )
            }
        }
        .padding(.horizontal, 24)
    }

    // ✅ Resultados de momentos
    private var momentsResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("explore.search.results")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(moments.count)")
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(Color(hex: "667eea"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "667eea").opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)

            MomentsSearchGrid(moments: moments, zoomNamespace: zoomNamespace, onMomentTap: onMomentTap)
        }
    }

    // ✅ Resultados mixtos
    private var mixedResultsView: some View {
        VStack(spacing: 24) {
            // Usuarios encontrados
            if !users.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("explore.search.users")
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(users.count)")
                            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(users.prefix(5)) { user in
                                MiniUserCard(
                                    user: user,
                                    onTap: { onUserTap(user) }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }

            // Momentos encontrados
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("explore.search.moments.tab")
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(moments.count)")
                            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    MomentsSearchGrid(moments: moments, zoomNamespace: zoomNamespace, onMomentTap: onMomentTap)
                }
            }
        }
    }

    // ✅ Propiedades computadas para el header
    private var headerTitle: String {
        switch searchType {
        case .hashtag:
            return String(format: NSLocalizedString("explore.search.hashtag.title", comment: ""), searchQuery)
        case .users:
            return searchQuery.hasPrefix("@") ? String(format: NSLocalizedString("explore.search.user.title", comment: ""), String(searchQuery.dropFirst())) : NSLocalizedString("explore.search.users.title", comment: "")
        case .moments:
            return NSLocalizedString("explore.search.moments.title", comment: "")
        case .mixed:
            return String(format: NSLocalizedString("explore.search.results.title", comment: ""), searchQuery)
        case .empty:
            return NSLocalizedString("explore.search.empty.title", comment: "")
        }
    }

    private var headerSubtitle: String {
        switch searchType {
        case .hashtag:
            return String(format: NSLocalizedString("explore.search.moments.found", comment: ""), moments.count)
        case .users:
            return String(format: NSLocalizedString("explore.search.users.found", comment: ""), users.count)
        case .moments:
            return String(format: NSLocalizedString("explore.search.moments.found", comment: ""), moments.count)
        case .mixed:
            return String(format: NSLocalizedString("explore.search.mixed.found", comment: ""), users.count, moments.count)
        case .empty:
            return NSLocalizedString("explore.search.empty.subtitle", comment: "")
        }
    }

    private var headerIcon: String {
        switch searchType {
        case .hashtag:
            return "number"
        case .users:
            return "person.2"
        case .moments:
            return "photo.stack"
        case .mixed:
            return "magnifyingglass"
        case .empty:
            return "questionmark"
        }
    }
}

// MARK: - 📱 Componentes auxiliares
enum SearchDisplayType {
    case hashtag, users, moments, mixed, empty
}

struct MomentsSearchGrid: View {
    let moments: [Moment]
    var zoomNamespace: Namespace.ID? = nil
    let onMomentTap: (Moment, Int, [Moment]) -> Void

    var body: some View {
        ExploreMomentsBentoGrid(
            moments: moments,
            zoomNamespace: zoomNamespace,
            zoomIDPrefix: "explore-search",
            onMomentTap: onMomentTap
        )
    }
}

struct MiniUserCard: View {
    let user: AppUser
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )

                HStack(spacing: 2) {
                    Text("@\(user.username)")
                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: user.id, size: 8)
                }
            }
        }
        .frame(width: 80)
    }
}

// MARK: - Componente de Búsquedas Recientes
struct RecentSearchesView: View {
    let searches: [CachedSearch]
    let onSearchSelected: (CachedSearch) -> Void
    let onClearAll: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("explore.recentSearches.title", comment: ""))
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !searches.isEmpty {
                    Button(action: onClearAll) {
                        Text(NSLocalizedString("explore.recentSearches.clearAll", comment: ""))
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 24)

            if searches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text(NSLocalizedString("explore.recentSearches.empty", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(searches) { search in
                        Button(action: { onSearchSelected(search) }) {
                            HStack(spacing: 16) {
                                Image(systemName: searchIcon(for: search.type))
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(search.query)
                                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                                        .foregroundStyle(.primary)

                                    Text(searchTypeLabel(for: search.type))
                                        .font(.system(size: legacyPoppinsSize(12)))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 10)
    }

    private func searchIcon(for type: String) -> String {
        switch type {
        case "user": return "person.fill"
        case "hashtag": return "number"
        default: return "magnifyingglass"
        }
    }

    private func searchTypeLabel(for type: String) -> String {
        switch type {
        case "user": return NSLocalizedString("search.type.user", comment: "")
        case "hashtag": return NSLocalizedString("search.type.hashtag", comment: "")
        default: return NSLocalizedString("search.type.recent", comment: "")
        }
    }
}
