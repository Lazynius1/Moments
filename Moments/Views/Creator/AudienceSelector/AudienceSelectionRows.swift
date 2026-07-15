import SwiftUI

// MARK: - Fila de Lista Personalizada
struct CustomListRow: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icono
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.system(size: legacyPoppinsSize(13)))
                    }
                    .foregroundStyle(.gray)
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: list.color ?? "00A896"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          Color(hex: list.color ?? "00A896").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color(hex: list.color ?? "00A896").opacity(0.5) :
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Opción de audiencia (lista plana, sin cajas)
struct AudienceGridCard: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let onTap: () -> Void

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var iconColor: Color {
        if audience == .bestFriends {
            return Color(hex: "34C759")
        }
        return primaryText
    }

    private var gridIconSize: CGFloat {
        switch audience {
        case .everyone, .mutuals, .bestFriends, .custom, .customList:
            return AudienceIconMetrics.gridCardEmphasis
        case .onlyMe:
            return AudienceIconMetrics.gridCard
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                AudienceIconView(
                    audience: audience,
                    size: gridIconSize,
                    tintColor: iconColor
                )
                .frame(width: 40, height: 40)
                .opacity(isSelected ? 1 : 0.42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(audience.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(primaryText)
                        .opacity(isSelected ? 1 : 0.82)

                    Text(audience.description)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(primaryText.opacity(0.55))
                        .opacity(isSelected ? 1 : 0.72)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(primaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                        )
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}



// MARK: - Tarjeta de Lista Personalizada (Carousel)
struct CustomListCard: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // ✅ Icono con color personalizado
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(hex: list.color ?? "00A896"))
                }
                
                // ✅ Información de la lista
                VStack(spacing: 2) {
                    Text(list.name)
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text("\(list.members.count) personas")
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
            .frame(width: 96)
            .opacity(isSelected ? 1 : 0.55)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                        )
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isPressed), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            isPressed = pressing
        })
    }
}

// MARK: - Fila de Lista Personalizada (ESTILO MODERNO)
struct CustomListRowModern: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // ✅ Icono con color personalizado
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.15 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // ✅ Información de la lista
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.system(size: legacyPoppinsSize(13)))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // ✅ Checkmark o chevron
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: list.color ?? "00A896"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ?
                                Color(hex: list.color ?? "00A896").opacity(0.3) :
                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        })
    }
}

// MARK: - Fila de Opción de Audiencia
struct AudienceOptionRow: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let customCount: Int?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icono
                ZStack {
                    Circle()
                        .fill(isSelected ?
                              Color(hex: "007AFF").opacity(0.2) :
                              (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .frame(width: 48, height: 48)

                    AudienceIconView(
                        audience: audience,
                        size: AudienceIconMetrics.row,
                        tintColor: isSelected ?
                            Color(hex: "007AFF") :
                            (colorScheme == .dark ? .white : .black)
                    )
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(audience.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    if let count = customCount {
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), count))
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(.gray)
                    } else {
                        Text(audience.description)
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(.gray)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color(hex: "007AFF"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          Color(hex: "007AFF").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color(hex: "007AFF").opacity(0.5) :
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
