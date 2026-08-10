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

enum ChatLocationLiveCountdownFormatter {
    static func text(until expiresAt: Date, now: Date = Date()) -> String {
        let interval = max(0, expiresAt.timeIntervalSince(now))
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
                        .foregroundStyle(.red)
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(isLive ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
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
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
            }
            .foregroundStyle(.red)
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
            return ChatLocationLiveCountdownFormatter.text(until: expiresAt, now: now)
        }
        if let address = message.locationAddress, !address.isEmpty {
            return address
        }
        return nil
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
    /// Hueco para la atribución legal de Apple Maps encima del dock (MapKit / WWDC23).
    static let mapLegalInsetSpacing: CGFloat = 12

    /// Altura visual del dock tipo Find My (cápsula fija, sin detents).
    static let dockCapsuleHeight: CGFloat = 72
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

    private var chromeInk: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }

    private var chromeSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.65) : Color(hex: "0B1215").opacity(0.55)
    }

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
                // Dock cápsula (Find My): no full-bleed → atribución Apple Maps visible a los lados/arriba.
                bottomDock
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

    // MARK: - Dock inferior (cápsula + acciones icono/texto)

    private var bottomDock: some View {
        VStack(spacing: 10) {
            locationInfoCapsule

            HStack(spacing: 0) {
                dockAction(
                    titleKey: "chat.location.directions",
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                    tint: accentColor
                ) { openInMaps(directions: true) }

                dockAction(
                    titleKey: "chat.location.openInMaps",
                    systemImage: "map.fill",
                    tint: chromeInk
                ) { openInMaps(directions: false) }

                if canStopLive {
                    dockStopAction
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: ChatLocationMapMetrics.dockCapsuleHeight)
            .momentsChromeGlass(in: Capsule(), interactive: false)
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.bottom, 6)
    }

    /// Misma columna que el resto del dock; icono = círculo rojo + stop.
    private var dockStopAction: some View {
        Button(action: stopLiveSharing) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(accentColorRed)
                        .frame(width: 28, height: 28)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(height: 28)

                Text(LocalizedStringKey("chat.location.stopSharing"))
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundStyle(chromeSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey("chat.location.stopSharing")))
    }

    private var locationInfoCapsule: some View {
        HStack(spacing: 10) {
            AttachmentIconView(
                icon: isLive ? .liveLocation : .location,
                preset: .locationDetailCard,
                tintColor: markerTint
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(chromeInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(chromeSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .momentsChromeGlass(in: Capsule(), interactive: false)
    }

    private func dockAction(
        titleKey: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 24)
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    .foregroundStyle(chromeSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(titleKey)))
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
            return ChatLocationLiveCountdownFormatter.text(until: expiresAt, now: now)
        }
        if let address = locationAddress, !address.isEmpty { return address }
        return nil
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

// MARK: - Marcador de avatar para ubicación en vivo

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
