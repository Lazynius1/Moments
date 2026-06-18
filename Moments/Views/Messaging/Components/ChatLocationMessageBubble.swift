import SwiftUI
import MapKit
import CoreLocation

// MARK: - Snapshot cache (memoria)

final class ChatMapSnapshotCache {
    static let shared = ChatMapSnapshotCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 80 }

    private func key(lat: Double, lng: Double, size: CGSize, scheme: ColorScheme) -> NSString {
        let rLat = (lat * 1000).rounded() / 1000
        let rLng = (lng * 1000).rounded() / 1000
        return "\(rLat),\(rLng),\(Int(size.width))x\(Int(size.height)),\(scheme == .dark ? "d" : "l")" as NSString
    }

    func image(lat: Double, lng: Double, size: CGSize, scheme: ColorScheme) -> UIImage? {
        cache.object(forKey: key(lat: lat, lng: lng, size: size, scheme: scheme))
    }

    func store(_ image: UIImage, lat: Double, lng: Double, size: CGSize, scheme: ColorScheme) {
        cache.setObject(image, forKey: key(lat: lat, lng: lng, size: size, scheme: scheme))
    }
}

// MARK: - Burbuja de ubicación

struct ChatLocationMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    var accentColor: Color = .blue
    var accentColorRed: Color = .red
    var onStopLive: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot: UIImage?
    @State private var showDetail = false
    @State private var now = Date()

    private var canStopLive: Bool {
        isCurrentUser && isLive && isLiveActive && onStopLive != nil
    }

    private let bubbleWidth: CGFloat = 276
    private let mapHeight: CGFloat = 150

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = message.latitude, let lng = message.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var isLive: Bool { message.isLiveLocationMessage }
    private var isLiveActive: Bool { message.isLiveLocationActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showDetail = true
            } label: {
                VStack(spacing: 0) {
                    mapThumbnail
                    infoBar
                }
            }
            .buttonStyle(.plain)

            if canStopLive {
                stopLiveButton
            }
        }
        .frame(width: bubbleWidth)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear {
            loadSnapshot()
        }
        .onChange(of: message.latitude) { _, _ in
            snapshot = nil
            loadSnapshot()
        }
        .fullScreenCover(isPresented: $showDetail) {
            if let coordinate {
                ChatLocationDetailView(
                    coordinate: coordinate,
                    locationName: message.locationName,
                    locationAddress: message.locationAddress,
                    isLive: isLive,
                    isLiveActive: isLiveActive,
                    expiresAt: message.liveLocationExpiresAt,
                    canStopLive: canStopLive,
                    senderId: message.senderId,
                    accentColor: accentColor,
                    accentColorRed: accentColorRed,
                    onStopLive: onStopLive
                )
            }
        }
        .task(id: isLiveActive) {
            // Solo refresca el reloj mientras la ubicación en vivo está activa.
            // Las burbujas estáticas o ya detenidas no programan ningún timer.
            guard isLiveActive else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var mapThumbnail: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: bubbleWidth, height: mapHeight)
                    .clipped()
            } else {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: bubbleWidth, height: mapHeight)
                    .overlay { ProgressView() }
            }

            // Marcador centrado: avatar para ubicación en vivo, pin para estática.
            Group {
                if isLive {
                    LiveLocationAvatarPin(
                        senderId: message.senderId,
                        avatarSize: 40,
                        isActive: isLiveActive
                    )
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)
                }
            }
            .frame(width: bubbleWidth, height: mapHeight)
        }
    }

    private var infoBar: some View {
        HStack(spacing: 8) {
            AttachmentIconView(
                icon: isLive ? .liveLocation : .location,
                preset: .locationBubbleInfo,
                tintColor: isLive && isLiveActive
                    ? .green
                    : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(isLive ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.6))
    }

    private var stopLiveButton: some View {
        Button {
            onStopLive?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 14))
                Text(LocalizedStringKey("chat.location.stopSharing"))
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: bubbleWidth)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var titleText: String {
        if isLive {
            return NSLocalizedString(
                isLiveActive ? "chat.location.liveSharing" : "chat.location.liveEnded",
                comment: ""
            )
        }
        if let name = message.locationName, !name.isEmpty {
            return name
        }
        return NSLocalizedString("common.location", comment: "")
    }

    private var subtitleText: String? {
        if isLive, isLiveActive, let expiresAt = message.liveLocationExpiresAt {
            let remaining = max(0, expiresAt.timeIntervalSince(now))
            return formattedCountdown(remaining)
        }
        if let address = message.locationAddress, !address.isEmpty {
            return address
        }
        return nil
    }

    private func formattedCountdown(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let value: String
        if hours > 0 {
            value = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            value = String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: NSLocalizedString("chat.location.liveRemaining", comment: ""), value)
    }

    private func loadSnapshot() {
        guard let coordinate else { return }
        let size = CGSize(width: bubbleWidth, height: mapHeight)
        if let cached = ChatMapSnapshotCache.shared.image(
            lat: coordinate.latitude, lng: coordinate.longitude, size: size, scheme: colorScheme
        ) {
            snapshot = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        let snapshotter = MKMapSnapshotter(options: options)
        let scheme = colorScheme
        snapshotter.start(with: .global(qos: .userInitiated)) { snap, _ in
            guard let snap else { return }
            ChatMapSnapshotCache.shared.store(
                snap.image, lat: coordinate.latitude, lng: coordinate.longitude, size: size, scheme: scheme
            )
            DispatchQueue.main.async {
                self.snapshot = snap.image
            }
        }
    }
}

// MARK: - Detalle fullscreen

private enum ChatLocationMapMetrics {
    static var displayCornerRadius: CGFloat {
        let width = UIScreen.main.bounds.width
        if width >= 430 { return 62 }
        if width >= 428 { return 53.33 }
        if width >= 402 { return 62 }
        if width >= 393 { return 55 }
        if width >= 390 { return 47.33 }
        if width >= 375 { return 39 }
        return 24
    }

    static var bottomCardTopCornerRadius: CGFloat { 28 }

    /// Espacio entre la tarjeta y la atribución legal de Apple Maps (recomendación MapKit / WWDC23).
    static let mapLegalInsetSpacing: CGFloat = 18

    static var bottomCardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: bottomCardTopCornerRadius,
            bottomLeadingRadius: displayCornerRadius,
            bottomTrailingRadius: displayCornerRadius,
            topTrailingRadius: bottomCardTopCornerRadius,
            style: .continuous
        )
    }
}

struct ChatLocationDetailView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String?
    let locationAddress: String?
    var isLive: Bool = false
    var isLiveActive: Bool = false
    var expiresAt: Date? = nil
    var canStopLive: Bool = false
    var senderId: String? = nil
    var accentColor: Color = .blue
    var accentColorRed: Color = .red
    var onStopLive: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var position: MapCameraPosition
    @State private var mapStyleIsHybrid = false
    @State private var now = Date()

    init(
        coordinate: CLLocationCoordinate2D,
        locationName: String?,
        locationAddress: String?,
        isLive: Bool = false,
        isLiveActive: Bool = false,
        expiresAt: Date? = nil,
        canStopLive: Bool = false,
        senderId: String? = nil,
        accentColor: Color = .blue,
        accentColorRed: Color = .red,
        onStopLive: (() -> Void)? = nil
    ) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.isLive = isLive
        self.isLiveActive = isLiveActive
        self.expiresAt = expiresAt
        self.canStopLive = canStopLive
        self.senderId = senderId
        self.accentColor = accentColor
        self.accentColorRed = accentColorRed
        self.onStopLive = onStopLive
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )))
    }

    private var markerTint: Color { isLive && isLiveActive ? .green : .red }

    var body: some View {
        ZStack {
            Map(position: $position) {
                Annotation(
                    locationName ?? NSLocalizedString("common.location", comment: ""),
                    coordinate: coordinate
                ) {
                    locationMarker
                }
            }
            .mapStyle(mapStyleIsHybrid ? .hybrid : .standard)
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: ChatLocationMapMetrics.mapLegalInsetSpacing) {
                bottomCard
                    .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 0) {
                topControls
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
        .task(id: isLiveActive) {
            guard isLive, isLiveActive else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Marcador

    @ViewBuilder
    private var locationMarker: some View {
        if isLive, let senderId {
            LiveLocationAvatarPin(
                senderId: senderId,
                avatarSize: 48,
                isActive: isLiveActive
            )
        } else {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white, markerTint)
                .shadow(radius: 3)
        }
    }

    // MARK: - Controles superiores

    private var topControls: some View {
        HStack(alignment: .top) {
            MomentsGlassIconButton(systemName: "xmark", size: 42, iconSize: 16) { dismiss() }
            Spacer()
            VStack(spacing: 10) {
                MomentsGlassIconButton(
                    systemName: mapStyleIsHybrid ? "map.fill" : "globe.americas.fill",
                    size: 42,
                    iconSize: 16
                ) { mapStyleIsHybrid.toggle() }
                MomentsGlassIconButton(systemName: "location.fill", size: 42, iconSize: 16) { recenter() }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tarjeta inferior

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AttachmentIconView(
                    icon: isLive ? .liveLocation : .location,
                    preset: .locationDetailCard,
                    tintColor: markerTint
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(isLive ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.55))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                actionButton(
                    titleKey: "chat.location.directions",
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: accentColor
                ) { openInMaps(directions: true) }

                actionButton(
                    titleKey: "chat.location.openInMaps",
                    systemImage: "map.fill",
                    tint: nil
                ) { openInMaps(directions: false) }
            }

            if canStopLive {
                actionButton(
                    titleKey: "chat.location.stopSharing",
                    systemImage: "stop.circle.fill",
                    tint: accentColorRed
                ) { stopLiveSharing() }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .safeAreaPadding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .momentsChromeGlass(in: ChatLocationMapMetrics.bottomCardShape, interactive: false)
    }

    private var actionButtonStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private func actionButton(
        titleKey: String,
        systemImage: String,
        tint: Color?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(LocalizedStringKey(titleKey))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(tint == nil ? (colorScheme == .dark ? .white : .black) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .momentsChromeGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true,
                tint: tint.map { $0.opacity(0.92) }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(actionButtonStrokeColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var titleText: String {
        if isLive {
            return NSLocalizedString(
                isLiveActive ? "chat.location.liveSharing" : "chat.location.liveEnded",
                comment: ""
            )
        }
        if let name = locationName, !name.isEmpty { return name }
        return NSLocalizedString("common.location", comment: "")
    }

    private var subtitleText: String? {
        if isLive, isLiveActive, let expiresAt {
            let remaining = max(0, expiresAt.timeIntervalSince(now))
            return formattedCountdown(remaining)
        }
        if let address = locationAddress, !address.isEmpty { return address }
        return nil
    }

    private func formattedCountdown(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let value: String
        if hours > 0 {
            value = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            value = String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: NSLocalizedString("chat.location.liveRemaining", comment: ""), value)
    }

    // MARK: - Acciones

    private func recenter() {
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
    }

    private func stopLiveSharing() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onStopLive?()
        }
    }

    private func openInMaps(directions: Bool) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = locationName ?? NSLocalizedString("common.location", comment: "")
        var options: [String: Any] = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate)
        ]
        if directions {
            options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDriving
        }
        mapItem.openInMaps(launchOptions: options)
    }
}

// MARK: - Marcador de avatar para ubicación en vivo (estilo WhatsApp)

struct LiveLocationAvatarPin: View {
    let senderId: String
    var avatarSize: CGFloat = 44
    var isActive: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: avatarSize + 8, height: avatarSize + 8)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

                StoryRingAvatarView(userId: senderId, size: avatarSize)

                if !isActive {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: avatarSize, height: avatarSize)
                }
            }

            // Punta del pin
            Triangle()
                .fill(.white)
                .frame(width: 16, height: 10)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .offset(y: -2)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
