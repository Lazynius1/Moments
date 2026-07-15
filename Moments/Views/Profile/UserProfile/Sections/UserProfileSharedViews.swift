import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// MARK: - ✅ COMPONENTE STATS NO TAPEABLE
struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                .foregroundStyle(.primary)

            Text(label)
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserFlowLayout (sin cambios - ya estaba bien)
struct UserFlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = UserFlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = UserFlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct UserFlowResult {
        var size = CGSize.zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(x: currentX, y: currentY, width: subviewSize.width, height: subviewSize.height))
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - UserScrollOffsetPreferenceKey (sin cambios)
struct UserScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - UserModernBackgroundView con temas
struct UserModernBackgroundView: View {
    let profileImagePath: String?
    let scrollOffset: CGFloat
    let profileTheme: ProfileTheme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Gradiente base basado en el tema del perfil
            if colorScheme == .dark {
                profileTheme.darkBackgroundGradient
            } else {
                profileTheme.backgroundGradient
            }

            // Imagen de perfil como fondo adaptativo
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                GeometryReader { geometry in
                    KFImage(url)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 30)
                        .opacity(colorScheme == .dark ? 0.15 : 0.08)
                        .scaleEffect(1.2)
                        .offset(y: scrollOffset * 0.2)
                        .ignoresSafeArea()
                }
            }

            // Overlay adaptativo para legibilidad
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: colorScheme == .dark ? [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.5),
                            Color.black.opacity(0.7)
                        ] : [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()

            // Overlay de glassmorphism adaptativo
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.03)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - UserMomentPreviewView (sin cambios - ya estaba bien)
struct UserMomentPreviewView: View {
    let moment: Moment
    let onHashtagTap: (String) -> Void

    var body: some View {
        VStack {
            if let imagePath = moment.imagePath, let url = URL(string: imagePath) {
                KFImage(url)
                    .placeholder {
                        Color.gray.opacity(0.2)
                            .frame(width: UIApplication.shared.activeWindowSize.width - 32, height: (UIApplication.shared.activeWindowSize.width - 32) * 0.75)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(ProgressView().tint(.gray))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIApplication.shared.activeWindowSize.width - 32, height: (UIApplication.shared.activeWindowSize.width - 32) * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: UIApplication.shared.activeWindowSize.width - 32, height: (UIApplication.shared.activeWindowSize.width - 32) * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(.gray))
            }
            UserExpandableContentView(
                content: moment.content,
                colorScheme: .dark,
                onHashtagTap: onHashtagTap
            )
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}

// MARK: - ✅ UserExpandableContentView para UserProfileView
struct UserExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false

    private let maxLines = 2
    private let maxCharacters = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MomentHashtagText(
                content: isExpanded ? content : String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                textFont: .system(size: 14),
                hashtagFont: .system(size: 14, weight: .semibold),
                baseColor: .white.opacity(0.95),
                mentionColor: Color(hex: "007AFF"),
                textAlignment: .center,
                shadowColor: .black.opacity(0.8),
                shadowRadius: 3,
                shadowX: 0,
                shadowY: 1,
                onHashtagTap: onHashtagTap,
                onMentionTap: MomentMentionNavigation.openProfile(forUsername:)
            )

            if needsExpansion {
                Button(action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("userProfile.seeLess", comment: "See less") : NSLocalizedString("userProfile.seeMore", comment: "See more"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundStyle(UserProfileColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(UserProfileColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
                .scaleEffect(isExpanded ? 1.0 : 0.95)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isExpanded), value: isExpanded)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

// MARK: - ProfileImageViewer
struct ProfileImageViewer: View {
    let profileImagePath: String?
    let username: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Fondo de cristal esmerilado (Glassmorphism)
            // No usamos ignoresSafeArea para que se vea el "sheet" flotando
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)

            // Capa de "frost" (congelado) para efecto premium
            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.02)

            // Sutil resplandor de la marca (00A896) muy tenue
            LinearGradient(
                colors: [
                    Color(hex: "00A896").opacity(0.02),
                    Color.clear,
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack {
                Spacer()

                // Imagen de perfil
                if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                    KFImage(url)
                        .placeholder {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 300, height: 300)
                                .overlay(
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 120))
                                        .foregroundStyle(.gray.opacity(0.6))
                                )
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIApplication.shared.activeWindowSize.width - 40)
                        .clipShape(Circle())
                        .scaleEffect(scale)
                        .offset(dragOffset)
                        .gesture(
                            SimultaneousGesture(
                                // Gesture de zoom
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = max(0.5, min(3.0, value.magnification))
                                    },
                                // Gesture de arrastre
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        // Si se arrastra hacia abajo lo suficiente, cerrar
                                        if value.translation.height > 100 {
                                            dismiss()
                                        } else {
                                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                                dragOffset = .zero
                                            }
                                        }
                                    }
                            )
                        )
                } else {
                    // Placeholder si no hay imagen
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 300, height: 300)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 120))
                                    .foregroundStyle(.secondary)
                                Text(username)
                                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        )
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                }

                Spacer()
            }
        }
        .onTapGesture {
            dismiss()
        }
    }
}
