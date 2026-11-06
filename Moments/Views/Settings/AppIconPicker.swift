import SwiftUI

/// Iconos de la app. El clásico es el principal (claro, oscuro y tintado); el resto son alternativos.
enum MomentsAppIcon: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case night = "Night"
    case purple = "Purple"
    case purpleFlat = "PurpleFlat"
    case whiteFlat = "WhiteFlat"
    case grape = "Grape"
    case ink = "Ink"
    case silver = "Silver"
    case gold = "Gold"
    case glow = "Glow"
    case outline = "Outline"
    case cosmic = "Cosmic"
    case pixel = "Pixel"
    case pride = "Pride"
    case prideFlag = "PrideFlag"
    case prideRing = "PrideRing"
    case fire = "Fire"
    case chrome = "Chrome"
    case neon = "Neon"
    case slime = "Slime"
    case flowers = "Flowers"
    case planet = "Planet"
    // Navidad
    case santaHat = "SantaHat"
    case candyCane = "CandyCane"
    case snow = "Snow"
    case baubles = "Baubles"
    case lights = "Lights"
    case gingerbread = "Gingerbread"
    case christmasTree = "ChristmasTree"
    case snowman = "Snowman"

    var id: String { rawValue }

    /// Iconos de temporada: solo se ofrecen en Navidad (ver `ChristmasSeason`).
    var isChristmas: Bool {
        switch self {
        case .santaHat, .candyCane, .snow, .baubles, .lights, .gingerbread, .christmasTree, .snowman: return true
        default: return false
        }
    }

    /// Temporada de Navidad según la región del dispositivo (la app es global):
    /// por defecto del 1 de noviembre al 6 de enero; en Filipinas empieza en septiembre
    /// y donde se sigue el calendario ortodoxo dura hasta el 19 de enero.
    static func isChristmasSeason(_ date: Date = Date(), region: String? = Locale.current.region?.identifier) -> Bool {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        let window = ChristmasSeason.window(for: region)
        if month >= window.startMonth { return true }
        return month == 1 && day <= window.endDayOfJanuary
    }

    /// Lo que ofrece el selector: fuera de temporada, sin los de Navidad salvo el que ya esté puesto.
    @MainActor
    static var available: [MomentsAppIcon] {
        let current = current
        let inSeason = isChristmasSeason()
        return allCases.filter { !$0.isChristmas || inSeason || $0 == current }
    }

    /// Nombre del set de iconos alternativo; nil vuelve al principal.
    var alternateIconName: String? {
        self == .classic ? nil : "AppIcon-\(rawValue)"
    }

    var thumbnail: Image { Image("AppIconThumbnail-\(rawValue)") }

    var title: String { NSLocalizedString("appIcon.name.\(rawValue)", comment: "App icon name") }

    @MainActor
    static var current: MomentsAppIcon {
        guard let name = UIApplication.shared.alternateIconName else { return .classic }
        return allCases.first { $0.alternateIconName == name } ?? .classic
    }
}

/// Fila de Ajustes que abre el selector de iconos.
struct AppIconSection: View {
    @State private var isShowingPicker = false
    @State private var currentIcon = MomentsAppIcon.current

    var body: some View {
        SettingsRow(
            icon: "app.badge",
            title: NSLocalizedString("settings.appIcon.title", comment: "App icon"),
            subtitle: currentIcon.title,
            action: { isShowingPicker = true }
        )
        .sheet(isPresented: $isShowingPicker, onDismiss: { currentIcon = MomentsAppIcon.current }) {
            AppIconPicker()
        }
    }
}

#if DEBUG
/// Acceso al selector privado para el modo captura.
struct ScreenshotAppIconPickerHost: View {
    var body: some View {
        AppIconPicker()
    }
}
#endif

/// Carrusel de iconos: el del centro se elige; los de los lados giran, se encogen y se desenfocan.
private struct AppIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activeIcon: MomentsAppIcon?
    @State private var scrollOffset: CGFloat = 0
    @State private var hapticsTrigger = false
    @State private var isApplying = false

    private let icons = MomentsAppIcon.available
    private static let brandPurple = Color(red: 0x5B / 255, green: 0x2C / 255, blue: 0x6F / 255)

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let size = proxy.size
                let iconSize = size.height * 0.86

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(icons) { icon in
                            iconView(icon, iconSize: iconSize)
                                .id(icon)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                // Los de los lados giran: sin recorte no se cortan en recto.
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollPosition(id: $activeIcon)
                .safeAreaPadding(.horizontal, (size.width - iconSize) / 2)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentOffset.x + $0.contentInsets.leading
                } action: { _, newValue in
                    scrollOffset = newValue / iconSize
                }
            }

            titles
                .padding(.top, 14)
            indicator
                .padding(.top, 4)

            bottomBar
        }
        .padding(.top, 28)
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: activeIcon) { oldValue, _ in oldValue != nil }
        .sensoryFeedback(.success, trigger: hapticsTrigger)
        .onAppear {
            if activeIcon == nil { activeIcon = MomentsAppIcon.current }
        }
    }

    private func iconView(_ icon: MomentsAppIcon, iconSize: CGFloat) -> some View {
        icon.thumbnail
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            .frame(width: iconSize, height: iconSize)
            .visualEffect { content, proxy in
                let minX = proxy.frame(in: .scrollView).minX
                let progress = min(abs(minX / iconSize), 1)
                return content
                    .scaleEffect(1 - progress * 0.3)
                    .blur(radius: progress * 4)
                    .offset(x: minX / 2)
                    .rotationEffect(.degrees(progress * -Double(iconSize) / 2))
            }
            .accessibilityLabel(icon.title)
    }

    private var indicator: some View {
        let index = icons.firstIndex(of: activeIcon ?? .classic) ?? 0
        return HStack(spacing: 3) {
            Text(String(format: "%02d", index + 1))
                .foregroundStyle(Self.brandPurple)
                .contentTransition(.numericText(value: Double(index)))
            Text("/")
            Text(String(format: "%02d", icons.count))
        }
        .font(.footnote.bold())
        .foregroundStyle(.secondary)
        .monospaced()
        .animation(.easeInOut(duration: 0.25), value: activeIcon)
        .accessibilityHidden(true)
    }

    private var titles: some View {
        ZStack {
            ForEach(Array(icons.enumerated()), id: \.element) { index, icon in
                let progress = scrollOffset - CGFloat(index)
                Text(icon.title)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .offset(x: progress * -150)
                    .opacity(1 - abs(progress) * 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var bottomBar: some View {
        let isActive = activeIcon == MomentsAppIcon.current
        return VStack(spacing: 15) {
            Text("appIcon.picker.description")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            activateButton(isActive: isActive)
                .disabled(isActive || isApplying)
                .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func activateButton(isActive: Bool) -> some View {
        let button = Button(action: apply) {
            Text(isActive ? "appIcon.picker.active" : "appIcon.picker.activate")
                .contentTransition(.numericText())
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .tint(Self.brandPurple)

        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    private func apply() {
        guard let icon = activeIcon, icon != MomentsAppIcon.current else { return }
        isApplying = true
        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
            Task { @MainActor in
                isApplying = false
                guard error == nil else { return }
                hapticsTrigger.toggle()
                dismiss()
            }
        }
    }
}

/// Ventana de Navidad por región: mes de inicio (hasta diciembre) y último día de enero.
enum ChristmasSeason {
    private static let orthodoxRegions: Set<String> = ["RU", "UA", "BY", "RS", "ME", "MK", "GE", "MD", "ET", "ER", "EG", "AM"]

    static func window(for region: String?) -> (startMonth: Int, endDayOfJanuary: Int) {
        switch region?.uppercased() {
        case "PH": return (9, 6)
        case let code? where orthodoxRegions.contains(code): return (11, 19)
        default: return (11, 6)
        }
    }
}
