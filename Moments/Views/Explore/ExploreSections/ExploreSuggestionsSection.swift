import SwiftUI
import Kingfisher

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isSearchFocused: Bool // ✅ Cambiar a Simple Binding para sincronizar
    let onSearch: (String) -> Void
    @FocusState private var internalFocus: Bool // ✅ FocusState interno

    var body: some View {


        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSearchFocused
                                    ? Color.primary.opacity(0.28)
                                    : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSearchFocused ? Color.primary : .secondary)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isSearchFocused), value: isSearchFocused)

                    TextField("explore.search.placeholder", text: $searchText)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(.primary)
                        .focused($internalFocus)
                        .onChange(of: internalFocus) { _, newValue in
                            isSearchFocused = newValue
                        }
                        .onChange(of: searchText) { _, newValue in
                             onSearch(newValue)
                        }


                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            onSearch("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.momentsPressIcon)
                        .transition(MotionPolicy.Transition.enterPop)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 40)

            if isSearchFocused {
                Button(NSLocalizedString("explore.search.cancel", comment: "")) {
                    searchText = ""
                    onSearch("")
                    isSearchFocused = false
                }
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchFocused)
    }
}

// MARK: - Estados de Carga y Error
struct LoadingStateView: View {
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotationAngle)
            }

            VStack(spacing: 8) {
                Text("explore.loading")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.primary)

                Text("explore.loading.subtitle")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 80)
        .onAppear { rotationAngle = 360 }
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    )

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                Text("explore.error.title")
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: legacyPoppinsSize(16)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("explore.error.retry")
                    }
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 50)
                    .padding(.horizontal, 22)
                    .contentShape(Capsule())
                }
                .buttonStyle(.momentsPress)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - Suggested people: a quiet avatar row above the grid
struct SuggestedUsersSection: View {
    let users: [AppUser]
    let onUserTap: (AppUser) -> Void
    let onShowMore: () -> Void
    var profileZoomNamespace: Namespace.ID? = nil

    var body: some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("explore.suggestedUsers.title")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("explore.suggestedUsers.seeMore", action: onShowMore)
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(users) { user in
                            SuggestedUserAvatar(user: user, profileZoomNamespace: profileZoomNamespace) {
                                onUserTap(user)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SuggestedUserAvatar: View {
    let user: AppUser
    var profileZoomNamespace: Namespace.ID?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 44)
                    .userProfileZoomSource(userId: user.id, namespace: profileZoomNamespace, cornerRadius: 22)
                Text(user.username)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(user.username))
    }
}

// MARK: - Tarjeta de Resultado de Búsqueda
struct SearchResultCard: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let commonInterests: Int
    var profileZoomNamespace: Namespace.ID? = nil
    let onFollow: () -> Void
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)

            HStack(spacing: 16) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .userProfileZoomSource(
                        userId: user.id,
                        namespace: profileZoomNamespace,
                        cornerRadius: 32
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("@\(user.username)")
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(.primary)

                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: user.id, size: 14)
                    }

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if commonInterests > 0 {
                        Text(String(format: NSLocalizedString("explore.commonInterests", comment: "Common interests"), commonInterests))
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                ModernFollowButton(
                    state: buttonState,
                    isLoading: false,
                    colorScheme: colorScheme,
                    targetUserId: user.id,
                    action: onFollow
                )
            }
            .padding(20)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onTap() }
    }
}

// MARK: - Botón de Seguir
struct FollowButton: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            onTap()
        }) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                Text(buttonText)
            }
            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .momentsChromeGlass(in: Capsule(), interactive: buttonState.isActionable)
        }
        .buttonStyle(.momentsPressSubtle)
        .disabled(!buttonState.isActionable)
        .opacity(isPassiveState ? 0.78 : 1)
    }

    private var buttonText: String {
        switch buttonState {
        case .ownProfile:
            return NSLocalizedString("explore.button.ownProfile", comment: "Your profile")
        case .blocked:
            return NSLocalizedString("explore.button.blocked", comment: "Blocked")
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .mutuals:
            return NSLocalizedString("audience.type.mutuals", comment: "")
        case .canFollow:
            return NSLocalizedString("explore.button.follow", comment: "Follow")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "Request")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "Requested")
        case .requestPendingCancellable:
            return NSLocalizedString("followButton.cancelRequest", comment: "Cancel request")
        }
    }

    private var buttonIcon: String {
        switch buttonState {
        case .following:
            return "checkmark"
        case .mutuals:
            return "person.2.fill"
        case .canFollow, .canRequestFollow:
            return "plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .blocked:
            return "xmark"
        case .ownProfile:
            return "person"
        }
    }

    private var isPassiveState: Bool {
        if case .requestPending = buttonState {
            return true
        }
        return false
    }
}

// MARK: - Componentes Auxiliares
struct ProfileImageeView: View {
    let imagePath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let imagePath = imagePath, let url = getImageURL(from: imagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                            )
                    }
                    .onFailure { error in
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white)
                    )
            }
        }
    }
}

struct EmptyMomentsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle())
                }

            VStack(spacing: 8) {
                Text("explore.noMoments")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.primary)

                Text("explore.noMoments.subtitle")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .momentsEmptyStateAppear()
    }
}

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle())
                }

            VStack(spacing: 8) {
                Text("explore.noUsers")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.primary)

                Text("explore.noUsers.subtitle")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
        .momentsEmptyStateAppear()
    }
}
