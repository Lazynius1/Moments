import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// ✅ REUSABLE: Sistema de colores adaptativos
struct AdaptiveColors {
    let colorScheme: ColorScheme
    
    var background: Color {
        colorScheme == .dark ? .black : .white
    }

    var surfaceBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }
    
    // Colores principales
    var primary: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var secondary: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }
    
    var tertiary: Color {
        colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.8)
    }
    
    // Colores de acento
    var accent: Color {
        Color(hex: "007AFF") // Royal Blue (Premium)
    }
    
    var accentSecondary: Color {
        colorScheme == .dark ? Color(hex: "007AFF").opacity(0.3) : Color(hex: "007AFF").opacity(0.6)
    }
    
    // Colores de fondo
    var cardBackground: Material {
        .ultraThinMaterial
    }
    
    var overlayStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.2), Color(hex: "007AFF").opacity(0.3)] :
        [Color.black.opacity(0.1), Color(hex: "007AFF").opacity(0.4)]
    }
    
    // Colores para botones
    var buttonStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.3), Color(hex: "007AFF").opacity(0.3)] :
        [Color.black.opacity(0.2), Color(hex: "007AFF").opacity(0.5)]
    }
    
    var buttonGradient: [Color] {
        colorScheme == .dark ?
        [Color(hex: "007AFF"), Color.white.opacity(0.8)] :
        [Color(hex: "007AFF"), Color.black.opacity(0.7)]
    }
    
    // Sombras
    var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.1) : .black.opacity(0.15)
    }
}

// ✅ REUSABLE: ModernActionButtons (Glow Rail)
struct ModernActionButtons: View {
    let moment: Moment
    @Binding var isSaved: Bool
    @Binding var isSaveLoading: Bool
    @Binding var commentCount: Int
    let onComment: () -> Void
    let onSave: () -> Void
    let onContextMenu: () -> Void 
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme
    @Binding var isImmersive: Bool

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            HStack(spacing: 8) {
                // ✅ REACCIONES
                EpicReactionButton(
                    moment: moment,
                    showCount: moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts
                )
                .environmentObject(firestoreService)
                
                // ✅ COMENTARIOS
                if !moment.disableComments {
                    Button(action: onComment) {
                        iconButton(
                            attachmentIcon: .comments,
                            color: commentCount > 0 ? .blue : adaptiveColors.primary,
                            secondaryColor: commentCount > 0 ? .purple : adaptiveColors.secondary,
                            isActive: commentCount > 0,
                            count: commentCount
                        )
                    }
                    .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
                }
                
                // ✅ GUARDAR
                if moment.allowSharing {
                    Button(action: onSave) {
                        if isSaveLoading {
                            ProgressView()
                                .frame(width: 44, height: 44)
                                .tint(colorScheme == .dark ? .white : .black)
                        } else {
                            iconButton(
                                attachmentIcon: .bookmark,
                                color: isSaved ? .yellow : adaptiveColors.primary,
                                secondaryColor: isSaved ? .orange : adaptiveColors.secondary,
                                isActive: isSaved
                            )
                        }
                    }
                    .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
                }
                
                // ✅ OPCIONES (Ellipsis integrada)
                Button(action: onContextMenu) {
                    iconButton(
                        systemName: "ellipsis",
                        color: adaptiveColors.primary,
                        secondaryColor: adaptiveColors.secondary,
                        isActive: false
                    )
                }
                .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
            }
            .padding(6)
            .momentsChromeGlass(in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            .opacity(isImmersive ? 0 : 1)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isImmersive), value: isImmersive)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
    
    // ✅ Función auxiliar para botones de icono compactos con soporte para contador
    @ViewBuilder
    private func iconButton(
        attachmentIcon: AttachmentIcon? = nil,
        systemName: String? = nil,
        color: Color,
        secondaryColor: Color,
        isActive: Bool,
        count: Int? = nil
    ) -> some View {
        let gradient = LinearGradient(
            colors: [color, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    .frame(width: 44, height: 44)

                if let attachmentIcon {
                    AttachmentIconView(
                        icon: attachmentIcon,
                        preset: .rail,
                        style: gradient
                    )
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(gradient)
                }
            }
            .scaleEffect(isActive ? 1.05 : 1.0)
            
            // ✅ BADGE DE CONTADOR (Estilo Epic)
            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isActive ? color : Color.gray.opacity(0.6))
                    )
                    .offset(x: 4, y: -4)
            }
        }
    }
}

// ✅ REUSABLE: ModernFollowButton
struct ModernFollowButton: View {
    enum Style {
        case standard
        case compact
    }

    let state: FollowButtonState
    let isLoading: Bool
    let colorScheme: ColorScheme
    var style: Style = .standard
    let action: () -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isCompact: Bool { style == .compact }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            action()
        }) {
            HStack(spacing: isCompact ? 4 : 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(adaptiveColors.primary)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: isCompact ? 11 : 14, weight: .semibold))
                }
                
                Text(title)
                    .font(.system(size: legacyPoppinsSize(isCompact ? 11 : 14), weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(isCompact ? 0.82 : 1)
                    .allowsTightening(isCompact)
            }
            .foregroundStyle(adaptiveColors.primary)
            .padding(.horizontal, isCompact ? 10 : 16)
            .padding(.vertical, isCompact ? 6 : 8)
            .momentsChromeGlass(in: Capsule(), interactive: state.isActionable)
        }
        .disabled(isLoading || !state.isActionable)
        .opacity(isPassiveState ? 0.78 : 1)
    }

    private var title: String {
        switch state {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .requestPendingCancellable:
            return NSLocalizedString("feed.follow.cancelRequest", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    private var iconName: String {
        switch state {
        case .following:
            return "person.fill.checkmark"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .blocked:
            return "slash.circle"
        default:
            return "person.badge.plus"
        }
    }

    private var isPassiveState: Bool {
        if case .requestPending = state {
            return true
        }
        return false
    }
}
