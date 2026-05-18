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
                        .foregroundColor(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.custom("Poppins-Regular", size: 13))
                    }
                    .foregroundColor(.gray)
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
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

// MARK: - Tarjeta de Audiencia en Grid
struct AudienceGridCard: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var iconColor: Color {
        if audience == .bestFriends {
            return Color(hex: "34C759")
        }
        return colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: audience.icon)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 60, height: 60)
                
                // ✅ Texto
                VStack(spacing: 4) {
                    Text(audience.title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(audience.description)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                isSelected ?
                                Color(hex: "007AFF").opacity(0.4) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: "007AFF").opacity(0.1) : Color.clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
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
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                }
                
                // ✅ Información de la lista
                VStack(spacing: 2) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text("\(list.members.count) personas")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
            .frame(width: 110, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected ?
                                Color(hex: list.color ?? "00A896").opacity(0.6) :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: list.color ?? "00A896").opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
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
                        .foregroundColor(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // ✅ Información de la lista
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.custom("Poppins-Regular", size: 13))
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // ✅ Checkmark o chevron
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle(), interactive: true)
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
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
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
                    
                    Image(systemName: audience.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ?
                                       Color(hex: "007AFF") : (colorScheme == .dark ? .white : .black))
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(audience.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if let count = customCount {
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), count))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.gray)
                    } else {
                        Text(audience.description)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "007AFF"))
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

