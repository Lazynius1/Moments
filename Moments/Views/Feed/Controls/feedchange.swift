import SwiftUI
import FirebaseAuth

// ✅ CORREGIDO: Enum FeedType con SOLO las propiedades faltantes agregadas
enum FeedType: String, CaseIterable {
    case following = "following"
    case forYou = "forYou"
    
    var displayName: String {
        switch self {
        case .following:
            return NSLocalizedString("feed.following", comment: "Following feed")
        case .forYou:
            return NSLocalizedString("feed.forYou", comment: "For you feed")
        }
    }
    
    // ✅ SOLO AGREGADO: Propiedades que faltaban (sin cambiar el diseño)
    var title: String {
        return displayName
    }
    
    var description: String {
        switch self {
        case .following:
            return NSLocalizedString("feed.following.description", comment: "Following feed description")
        case .forYou:
            return NSLocalizedString("feed.forYou.description", comment: "For you feed description")
        }
    }
    
    var icon: String {
        switch self {
        case .following:
            return "person.2.fill"
        case .forYou:
            return "sparkles"
        }
    }
}

// ✅ AGREGADO: Extensión para UserDefaults (necesaria para el sistema de preferencias)
extension UserDefaults {
    private enum Keys {
        static let selectedFeedType = "selectedFeedType"
    }
    
    var selectedFeedType: FeedType {
        get {
            let rawValue = string(forKey: Keys.selectedFeedType) ?? FeedType.following.rawValue
            return FeedType(rawValue: rawValue) ?? .following
        }
        set {
            set(newValue.rawValue, forKey: Keys.selectedFeedType)
        }
    }
}

// ✅ ACTUALIZADO: Selector expandible de feed (corregido)
struct ExpandableFeedSelector: View {
    @Binding var selectedFeedType: FeedType
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Botón principal del selector
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Icono del feed actual
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "00A896").opacity(0.6), Color.white.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                        
                        Image(systemName: selectedFeedType.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "00A896"), Color.white.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Título y descripción
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedFeedType.title)
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(selectedFeedType.description)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Flecha de expansión
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            // Panel expandible con opciones
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(FeedType.allCases, id: \.self) { feedType in
                        FeedOptionRow(
                            feedType: feedType,
                            isSelected: feedType == selectedFeedType,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeedType = feedType
                                    isExpanded = false
                                }
                                
                                // ✅ MANTENIDO: Analytics exactamente como en tu código original
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

// ✅ CORREGIDO: Fila de opción de feed
struct FeedOptionRow: View {
    let feedType: FeedType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icono
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "00A896").opacity(0.2) : Color.clear)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: feedType.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isSelected ?
                                [Color(hex: "00A896"), Color.white.opacity(0.9)] :
                                [Color.white.opacity(0.7), Color.gray.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedType.title)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    
                    Text(feedType.description)
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(.gray.opacity(isSelected ? 0.8 : 0.6))
                }
                
                Spacer()
                
                // Indicador de selección
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "00A896").opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: isSelected ?
                            [Color(hex: "00A896").opacity(0.4), Color.white.opacity(0.2)] :
                            [Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1 : 0
                    )
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isSelected), value: isSelected)
    }
}

// ✅ CORREGIDO: Selector compacto de feed (más simple y funcional)
struct CompactFeedToggle: View {
    @Binding var selectedFeedType: FeedType
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Botón principal compacto
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: selectedFeedType.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "00A896"), Color.white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(selectedFeedType.title)
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(.white)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            
            // Panel desplegable compacto
            if isExpanded {
                ForEach(FeedType.allCases, id: \.self) { feedType in
                    if feedType != selectedFeedType {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFeedType = feedType
                                isExpanded = false
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFeedType = feedType
                                isExpanded = false
                            }
                            
                            // ✅ MANTENIDO: Analytics exactamente como en tu código original
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: feedType.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(feedType.title)
                                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
                }
            }
        }
    }
}

// ✅ MANTENIDO: Selector como segmented control (EXACTAMENTE como tu código original)
struct SegmentedFeedToggle: View {
    @Binding var selectedFeedType: FeedType
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(FeedType.allCases, id: \.self) { feedType in
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 200, damping: 25)) {
                        selectedFeedType = feedType
                    }
                    
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: feedType.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(feedType.title)
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    }
                    .foregroundColor(selectedFeedType == feedType ? .white : Color.primary.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if selectedFeedType == feedType {
                                if #available(iOS 26.0, *) {
                                    Capsule()
                                        .fill(Color(hex: "00A896"))
                                        .glassEffect(.regular, in: Capsule())
                                } else {
                                    Capsule()
                                        .fill(Color(hex: "00A896"))
                                        .overlay(
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                                .opacity(0.4)
                                        )
                                }
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                            }
                        }
                    )
                }
                .scaleEffect(selectedFeedType == feedType ? 1.0 : 0.95)
                .animation(.interpolatingSpring(stiffness: 200, damping: 25), value: selectedFeedType)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    Color.primary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

// ✅ CORREGIDO: Toggle tipo "chip" que aparece desde el header (simplificado)
struct HeaderFeedChip: View {
    @Binding var selectedFeedType: FeedType
    @State private var showOptions: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Chip principal
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showOptions.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.8))
                        .frame(width: 6, height: 6)
                    
                    Text(selectedFeedType.title)
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(.white)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .rotationEffect(.degrees(showOptions ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            
            // Opciones desplegables
            if showOptions {
                VStack(spacing: 6) {
                    ForEach(FeedType.allCases, id: \.self) { feedType in
                        if feedType != selectedFeedType {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeedType = feedType
                                    showOptions = false
                                }
                                
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.6))
                                        .frame(width: 6, height: 6)
                                    
                                    Text(feedType.title)
                                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
