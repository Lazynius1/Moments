import SwiftUI
import Kingfisher
import AVFoundation

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
                                LinearGradient(
                                    colors: isSearchFocused ?
                                        [Color(hex: "667eea").opacity(0.6), Color(hex: "764ba2").opacity(0.4)] :
                                        [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .background(
                        IntelligentGlow(
                            isFocused: isSearchFocused,
                            cornerRadius: 10,
                            colors: [
                                Color(hex: "667eea"),
                                Color(hex: "764ba2"),
                                Color(hex: "6B73FF")
                            ]
                        )
                    )
                    .shadow(
                        color: isSearchFocused ? Color(hex: "667eea").opacity(0.2) : .black.opacity(0.05),
                        radius: isSearchFocused ? 6 : 4,
                        x: 0,
                        y: isSearchFocused ? 3 : 2
                    )

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isSearchFocused ? Color(hex: "667eea") : .secondary)
                        .animation(.easeInOut(duration: 0.3), value: isSearchFocused)

                    TextField("explore.search.placeholder", text: $searchText)
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.primary)
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
                                .foregroundColor(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
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
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(Color(hex: "667eea"))
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
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotationAngle)
            }

            VStack(spacing: 8) {
                Text("explore.loading")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)

                Text("explore.loading.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.red)
            }

            VStack(spacing: 12) {
                Text("explore.error.title")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("explore.error.retry")
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "667eea").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - Sección de Usuarios Sugeridos
struct SuggestedUsersSection: View {
    let users: [AppUser]
    let moments: [Moment] // ✅ Recibimos momentos ya filtrados
    let currentUserInterests: [String]
    let userButtonStates: [String: FollowButtonState]
    let onFollowUser: (String) -> Void
    let onUserTap: (AppUser) -> Void
    let onShowMore: () -> Void

    var body: some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("explore.suggestedUsers.title")
                            .font(.custom("Poppins-SemiBold", size: 20))
                            .foregroundColor(.primary)

                        Text("explore.suggestedUsers.subtitle")
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("explore.suggestedUsers.seeMore") {
                        onShowMore()
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "667eea"))
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(users) { user in
                            // ✅ Buscar el último momento visible de este usuario
                            let latestMoment = moments.first(where: { $0.authorId == user.id })

                            SuggestedUserCard(
                                user: user,
                                backgroundMoment: latestMoment,
                                commonInterests: Set(user.interests).intersection(Set(currentUserInterests)).count,
                                buttonState: userButtonStates[user.id] ?? .canFollow,
                                onFollow: { onFollowUser(user.id) },
                                onTap: { onUserTap(user) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

// MARK: - Tarjeta de Usuario Sugerido
struct SuggestedUserCard: View {
    let user: AppUser
    let backgroundMoment: Moment? // ✅ Momento para el fondo
    let commonInterests: Int
    let buttonState: FollowButtonState
    let onFollow: () -> Void
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // ✅ FONDO: Imagen del momento o Gradiente
            GeometryReader { geometry in
                // ✅ NUEVO: Priorizar thumbnailUrl (video) o imagePath (imagen) para el fondo
                let url = backgroundMoment?.previewImageURLString.flatMap { getImageURL(from: $0) }

                if let bgUrl = url {
                    KFImage(bgUrl)
                        .placeholder {
                            defaultBackground
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 132, height: 176)
                        .clipped()
                        .blur(radius: 4)
                        .overlay(
                            // Overlay oscuro para legibilidad
                            LinearGradient(
                                colors: [.black.opacity(0.50), .black.opacity(0.18)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                } else {
                    defaultBackground
                }
            }

            // ✅ CONTENIDO
            VStack(spacing: 9) {
                Spacer()

                // Profile Image with Glow
                ZStack {
                    Circle()
                        .fill(Color(hex: "667eea").opacity(0.3))
                        .frame(width: 48, height: 48)
                        .blur(radius: 6)

                    ProfileImageeView(imagePath: user.profileImagePath, size: 42)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 1.5)
                        )
                }

                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(user.username)
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(.white) // ✅ Texto blanco siempre
                            .lineLimit(1)
                            .shadow(radius: 2)

                        VerifiedBadgeView(userId: user.id, size: 10)
                    }

                    if commonInterests > 0 {
                        Text(String(format: NSLocalizedString("explore.commonInterests", comment: "Common interests"), commonInterests))
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.white.opacity(0.82))
                            .lineLimit(1)
                    } else {
                        Text(NSLocalizedString("explore.suggestedUsers.suggestedForYou", comment: ""))
                             .font(.custom("Poppins-Medium", size: 10))
                             .foregroundColor(.white.opacity(0.82))
                    }
                }

                Button(action: onFollow) {
                    Text(buttonTitle)
                        .font(.custom("Poppins-SemiBold", size: 11))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule(), interactive: buttonState.isActionable)
                }
                .disabled(!buttonState.isActionable)
                .opacity(isPassiveButtonState ? 0.78 : 1)
            }
            .padding(10)
            .padding(.bottom, 8)
        }
        .frame(width: 132, height: 176)
        .background(Color.black) // Fallback color
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            isPressed = isPressing
        }, perform: {})
    }

    private var defaultBackground: some View {
        LinearGradient(
            colors: [Color(hex: "667eea").opacity(0.2), Color(hex: "764ba2").opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // Patrón sutil o efecto glass
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var buttonTitle: String {
        switch buttonState {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    private var isPassiveButtonState: Bool {
        if case .requestPending = buttonState {
            return true
        }
        return false
    }
}

// MARK: - Tarjeta de Resultado de Búsqueda
struct SearchResultCard: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let commonInterests: Int
    let onFollow: () -> Void
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)

            HStack(spacing: 16) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("@\(user.username)")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.primary)

                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: user.id, size: 14)
                    }

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    if commonInterests > 0 {
                        Text(String(format: NSLocalizedString("explore.commonInterests", comment: "Common interests"), commonInterests))
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(Color(hex: "667eea"))
                    }
                }

                Spacer()

                if buttonState.isActionable {
                    FollowButton(
                        user: user,
                        buttonState: buttonState,
                        onTap: onFollow
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: buttonState == .following ? "checkmark" :
                              buttonState == .requestPending ? "clock" : "xmark")
                        Text(buttonState.buttonText)
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
            .padding(20)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
}

// MARK: - Botón de Seguir
struct FollowButton: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                Text(buttonText)
            }
            .font(.custom("Poppins-SemiBold", size: 14))
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .liquidGlass(in: Capsule(), interactive: buttonState.isActionable)
        }
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
        case .canFollow:
            return NSLocalizedString("explore.button.follow", comment: "Follow")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "Request")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "Requested")
        }
    }

    private var buttonIcon: String {
        switch buttonState {
        case .following:
            return "checkmark"
        case .canFollow, .canRequestFollow:
            return "plus"
        case .requestPending:
            return "clock"
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

// MARK: - Grid Dinámico (Quilt Pattern)
struct DynamicMomentsGrid: View {
    let moments: [Moment]
    let onMomentTap: (Moment) -> Void

    // El patrón se repite cada 12 items: 3, 3, 3(1L+2S), 3, 3(2S+1R) NO, CORRECCIÓN:
    // Mejor ciclo: Row(3) -> BigLeft(3 consumidos) -> Row(3) -> BigRight(3 consumidos). Total 12 items.

    var body: some View {
        VStack(spacing: 4) {
            let chunked = moments.chunked(into: 12)

            ForEach(0..<chunked.count, id: \.self) { index in
                let chunk = chunked[index]
                let items = Array(chunk)

                // Renderizar el bloque de 12 (o menos si es el final)
                DynamicGridBlock(items: items, onMomentTap: onMomentTap)
            }
        }
    }
}

struct DynamicGridBlock: View {
    let items: [Moment] // Up to 12 items
    let onMomentTap: (Moment) -> Void

    var body: some View {
        // Calcular filas basados en disponibilidad
        // Fila 1: 0,1,2 (3 items)
        if items.count >= 3 {
             MomentsRowView(moments: Array(items[0..<3]), onTap: onMomentTap)
        } else {
             MomentsRowView(moments: items, onTap: onMomentTap)
        }

        // Bloque Big Left: 3,4,5 (3 items) -> Index 3 es Big
        if items.count >= 6 {
            BigLeftRowView(moments: Array(items[3..<6]), onTap: onMomentTap)
        } else if items.count > 3 {
            // Remainder row
            MomentsRowView(moments: Array(items[3..<items.count]), onTap: onMomentTap)
        }

        // Fila 3: 6,7,8 (3 items)
        if items.count >= 9 {
             MomentsRowView(moments: Array(items[6..<9]), onTap: onMomentTap)
        } else if items.count > 6 {
             MomentsRowView(moments: Array(items[6..<items.count]), onTap: onMomentTap)
        }

        // Bloque Big Right: 9,10,11 (3 items) -> Index 11 es Big
        if items.count >= 12 {
            BigRightRowView(moments: Array(items[9..<12]), onTap: onMomentTap)
        } else if items.count > 9 {
            // Remainder row
            MomentsRowView(moments: Array(items[9..<items.count]), onTap: onMomentTap)
        }
    }
}

// Fila Standard de 3 items
struct MomentsRowView: View {
    let moments: [Moment]
    let onTap: (Moment) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let width = (geo.size.width - (spacing * 2)) / 3
            HStack(spacing: spacing) {
                ForEach(moments) { moment in
                    MomentCard(moment: moment, onTap: { onTap(moment) })
                        .frame(width: width, height: width)
                        .clipped()
                }
                // Spacer si hay menos de 3 para alinear a la izquierda
                if moments.count < 3 {
                    Spacer()
                }
            }
        }
        .aspectRatio(3.0/1.0, contentMode: .fit) // Si son 3 cuadrados, ratio 3:1. Si menos, se ajusta el HStack
        .frame(height: UIScreen.main.bounds.width / 3) // Altura aproximada para layout
    }
}

// Bloque Grande Izquierda: [ Big(2x2) ] [ Small / Small ]
struct BigLeftRowView: View {
    let moments: [Moment] // Expects 3 items: [Big, Small, Small]
    let onTap: (Moment) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let oneUnit = (geo.size.width - (spacing * 2)) / 3
            let twoUnits = oneUnit * 2 + spacing

            HStack(alignment: .top, spacing: spacing) {
                // Item 0: Grande
                if moments.indices.contains(0) {
                    MomentCard(moment: moments[0], onTap: { onTap(moments[0]) })
                        .frame(width: twoUnits, height: twoUnits)
                        .clipped()
                }

                VStack(spacing: spacing) {
                    if moments.indices.contains(1) {
                        MomentCard(moment: moments[1], onTap: { onTap(moments[1]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                    if moments.indices.contains(2) {
                        MomentCard(moment: moments[2], onTap: { onTap(moments[2]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width / 3) * 2 + 4)
    }
}

// Bloque Grande Derecha: [ Small / Small ] [ Big(2x2) ]
struct BigRightRowView: View {
    let moments: [Moment] // Expects 3 items: [Small, Small, Big]
    let onTap: (Moment) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let oneUnit = (geo.size.width - (spacing * 2)) / 3
            let twoUnits = oneUnit * 2 + spacing

            HStack(alignment: .top, spacing: spacing) {
                // Stack Izquierda: Items 0, 1
                VStack(spacing: spacing) {
                    if moments.indices.contains(0) {
                        MomentCard(moment: moments[0], onTap: { onTap(moments[0]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                    if moments.indices.contains(1) {
                        MomentCard(moment: moments[1], onTap: { onTap(moments[1]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                }

                // Item 2: Grande
                if moments.indices.contains(2) {
                    MomentCard(moment: moments[2], onTap: { onTap(moments[2]) })
                        .frame(width: twoUnits, height: twoUnits)
                        .clipped()
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width / 3) * 2 + 4)
    }
}

// MARK: - Tarjeta de Moment
struct MomentCard: View {
    let moment: Moment
    let onTap: () -> Void

    var body: some View {
        ScreenshotProtectedView(
            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
        ) {
            Button(action: onTap) {
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.gray.opacity(0.08))

                        if let mediaItem = moment.primaryVisibleMediaItem, mediaItem.type == .video {
                            ExploreVideoThumbnailView(videoUrl: mediaItem.url, thumbnailUrl: mediaItem.thumbnailUrl ?? moment.thumbnailUrl)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                                .overlay(
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 22, height: 22)

                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                    }
                                    .padding(7),
                                    alignment: .bottomTrailing
                                )
                        } else if let imagePath = moment.previewImageURLString, let url = getImageURL(from: imagePath) {
                            KFImage(url)
                                .placeholder {
                                    Color.gray.opacity(0.2)
                                }
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private var momentContent: some View {
        EmptyView() // Not used in this simplified version
    }
}


// MARK: - Video Thumbnail View
struct ExploreVideoThumbnailView: View {
    let videoUrl: String
    let thumbnailUrl: String? // ✅ Nuevo
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let thumbUrl = thumbnailUrl, let url = URL(string: thumbUrl) {
                // ✅ NUEVO: Usar miniatura pre-generada
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.1)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard let url = URL(string: videoUrl) else {
            isLoading = false
            return
        }

        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 240, height: 240) // 2x para retina

        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 1))]) { _, cgImage, _, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let cgImage = cgImage {
                    self.thumbnailImage = UIImage(cgImage: cgImage)
                }
            }
        }
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
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
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
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

struct EmptyMomentsView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    )

                Image(systemName: "photo.stack")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                Text("explore.noMoments")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)

                Text("explore.noMoments.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
    }
}

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    )

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                Text("explore.noUsers")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)

                Text("explore.noUsers.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }
}
