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
    @Environment(\.chatListContainerWidth) private var chatListContainerWidth
    @Environment(\.chatOutgoingBubbleColor) private var chatOutgoingBubbleColor
    @State private var snapshot: UIImage?
    @State private var now = Date()

    private var canStopLive: Bool {
        isCurrentUser && isLive && isLiveActive && onStopLive != nil
    }

    private let designBubbleWidth: CGFloat = 276
    private let mapHeight: CGFloat = 150
    private let cardInset: CGFloat = 6

    private var bubbleWidth: CGFloat {
        ChatBubbleLayoutWidth.capped(designBubbleWidth, chatListWidth: chatListContainerWidth)
    }

    private var mapWidth: CGFloat { bubbleWidth - (cardInset * 2) }

    private var neutralCardBackground: Color {
        AdaptiveColors(colorScheme: colorScheme).chatCardBackground
    }

    /// Propias: el panel adopta el color de burbuja del chat; el mapa queda intacto.
    private var cardBackground: Color {
        isCurrentUser ? chatOutgoingBubbleColor : neutralCardBackground
    }

    private var outgoingInk: Color {
        chatBubbleTextColor(for: chatOutgoingBubbleColor)
    }

    private var titleColor: Color {
        if isCurrentUser { return outgoingInk }
        return colorScheme == .dark ? .white : .black
    }

    private var subtitleColor: Color {
        if isCurrentUser { return outgoingInk.opacity(0.75) }
        return colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    /// Sobre el color del chat el rojo/verde pueden perderse: se usa la tinta de la burbuja.
    private var infoIconTint: Color {
        if isCurrentUser { return outgoingInk }
        if isLive {
            return isLiveActive ? .green : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
        }
        return .red
    }

    private var cardStroke: Color {
        if isCurrentUser { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = message.latitude, let lng = message.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var isLive: Bool { message.isLiveLocationMessage }
    private var isLiveActive: Bool { message.isLiveLocationActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                mapThumbnail
                    .padding(.horizontal, cardInset)
                    .padding(.top, cardInset)
                infoBar
            }

            if canStopLive {
                stopLiveButton
            }
        }
        .frame(width: bubbleWidth)
        .frame(minHeight: mapHeight + cardInset + 56 + (canStopLive ? 40 : 0))
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 0.5)
        )
        .onAppear {
            loadSnapshot()
        }
        .onChange(of: message.latitude) { _, _ in
            snapshot = nil
            loadSnapshot()
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
                    .frame(width: mapWidth, height: mapHeight)
                    .clipped()
            } else {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: mapWidth, height: mapHeight)
                    .overlay { ProgressView() }
            }

            // Marcador centrado: tanto la ubicación fija como la live identifican
            // al emisor con su avatar; solo la live detenida se oscurece.
            Group {
                if !message.senderId.isEmpty {
                    LiveLocationAvatarPin(
                        senderId: message.senderId,
                        avatarSize: 40,
                        isActive: !isLive || isLiveActive,
                        isLive: isLive
                    )
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: mapWidth, height: mapHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var infoBar: some View {
        HStack(spacing: 8) {
            AttachmentIconView(
                icon: isLive ? .liveLocation : .location,
                preset: .locationBubbleInfo,
                tintColor: infoIconTint
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(isLive ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(cardBackground)
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
            .background(Color.red.opacity(colorScheme == .dark ? 0.12 : 0.08))
            // Acción destructiva sobre superficie neutra para que el rojo siga legible.
            .background(neutralCardBackground)
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
        let size = CGSize(width: mapWidth, height: mapHeight)
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
        if let senderId, !senderId.isEmpty {
            LiveLocationAvatarPin(
                senderId: senderId,
                avatarSize: 48,
                isActive: !isLive || isLiveActive,
                isLive: isLive
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

// MARK: - Marcador de avatar (ubicación fija + live)

/// Pin blanco continuo (gota): cabeza circular + punta, sin junta círculo/triángulo.
/// La insignia comparte la silueta blanca; solo recorta el avatar debajo del icono.
struct LiveLocationAvatarPin: View {
    let senderId: String
    var avatarSize: CGFloat = 44
    var isActive: Bool = true
    /// `true` → liveLocation icon; `false` → location fija.
    var isLive: Bool = false

    private var headDiameter: CGFloat { avatarSize + 8 }
    /// Altura de la punta ~38% del diámetro de cabeza (diseño B).
    private var tipHeight: CGFloat { headDiameter * 0.38 }
    private var totalHeight: CGFloat { headDiameter + tipHeight }

    /// Hueco del badge (un poco mayor que el de banners para el glifo de location).
    private var cutoutSize: CGFloat { max(18, avatarSize * 0.48) }
    private var badgeShift: CGFloat { 2 }
    /// Glifo casi a tope del hueco; el PNG template rellena poco del frame.
    private var badgeIconSize: CGFloat { cutoutSize * 0.92 }

    private var badgeIcon: AttachmentIcon { isLive ? .liveLocation : .location }
    private var badgeTint: Color {
        if isLive {
            return isActive ? .green : Color.primary.opacity(0.55)
        }
        return .red
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                LocationAvatarPinSilhouette(badgeDiameter: cutoutSize, badgeShift: badgeShift)
                    .fill(.white)
                    .frame(width: headDiameter, height: totalHeight)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

                ZStack {
                    StoryRingAvatarView(userId: senderId, size: avatarSize)

                    if !isActive {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: avatarSize, height: avatarSize)
                    }
                }
                .frame(width: headDiameter, height: headDiameter)
                .reversedMask(alignment: .bottomTrailing) {
                    Circle()
                        .frame(width: cutoutSize, height: cutoutSize)
                        .offset(x: badgeShift, y: badgeShift)
                }
            }
            .drawingGroup(opaque: false)

            Color.clear
                .frame(width: headDiameter, height: headDiameter)
                .overlay(alignment: .bottomTrailing) {
                    pinBadgeIcon
                        .frame(width: cutoutSize, height: cutoutSize)
                        .offset(x: badgeShift, y: badgeShift)
                }
        }
        .frame(width: headDiameter, height: totalHeight)
    }

    /// Icono un pelín más “gordo”: halo mínimo del mismo tint + glifo.
    private var pinBadgeIcon: some View {
        ZStack {
            AttachmentIconView(icon: badgeIcon, size: badgeIconSize, tintColor: badgeTint)
                .blur(radius: 0.35)
                .opacity(0.55)
            AttachmentIconView(icon: badgeIcon, size: badgeIconSize, tintColor: badgeTint)
        }
        .frame(width: badgeIconSize, height: badgeIconSize)
    }
}

/// Silueta compartida: cabeza, punta e insignia con un único relleno.
struct LocationAvatarPinSilhouette: Shape {
    var badgeDiameter: CGFloat = 0
    var badgeShift: CGFloat = 2
    var shortTip: Bool = false

    func path(in rect: CGRect) -> Path {
        let headR = rect.width / 2
        let cx = rect.midX
        let cy = rect.minY + headR
        let tip = CGPoint(x: cx, y: rect.maxY)

        let leftJoin = CGPoint(x: cx - headR * (shortTip ? 0.38 : 0.72), y: cy + headR * (shortTip ? 0.925 : 0.70))
        let rightJoin = CGPoint(x: cx + headR * (shortTip ? 0.38 : 0.72), y: cy + headR * (shortTip ? 0.925 : 0.70))
        let leftCtrl = CGPoint(x: cx - headR * 0.35, y: cy + headR * 1.05)
        let rightCtrl = CGPoint(x: cx + headR * 0.35, y: cy + headR * 1.05)

        let leftAngle = Angle(radians: atan2(leftJoin.y - cy, leftJoin.x - cx))
        let rightAngle = Angle(radians: atan2(rightJoin.y - cy, rightJoin.x - cx))
        let topAngle = Angle.degrees(-90)

        var path = Path()
        // Cima → lado derecho → punta → lado izquierdo → cima.
        path.move(to: CGPoint(x: cx, y: cy - headR))
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: headR,
            startAngle: topAngle,
            endAngle: rightAngle,
            clockwise: false
        )
        path.addQuadCurve(to: tip, control: rightCtrl)
        path.addQuadCurve(to: leftJoin, control: leftCtrl)
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: headR,
            startAngle: leftAngle,
            endAngle: topAngle,
            clockwise: false
        )
        path.closeSubpath()
        if badgeDiameter > 0 {
            path.addEllipse(in: CGRect(
                x: rect.width - badgeDiameter + badgeShift,
                y: rect.width - badgeDiameter + badgeShift,
                width: badgeDiameter,
                height: badgeDiameter
            ))
        }
        return path
    }
}
