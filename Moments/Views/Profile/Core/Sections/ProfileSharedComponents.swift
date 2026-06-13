import SwiftUI

// MARK: - Vista de carga
struct ModernLoadingView: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(ProfileColors.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [ProfileColors.accent, ProfileColors.textPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }

                            Text("profile.loading")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(ProfileColors.textSecondary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Vista de error
struct ModernErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    )

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 35))
                    .foregroundColor(.red.opacity(0.8))
            }

            VStack(spacing: 12) {
                Text("profile.error.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(ProfileColors.textPrimary)

                Text(errorMessage)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                    Text("profile.error.retryButton")
                        .font(.custom("Poppins-SemiBold", size: 14))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(ProfileColors.accent)
                .clipShape(Capsule())
                .shadow(color: ProfileColors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 40)
    }
}

struct ExpandableBioView: View {
    let bio: String
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bio)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(ProfileColors.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 15))
                        .lineLimit(3)
                        .background(GeometryReader { geometry in
                            Color.clear.onAppear {
                                DispatchQueue.main.async {
                                    // Mejor cálculo: si supera 100 caracteres o tiene más de 2 saltos de línea
                                    needsExpansion = bio.count > 100 || bio.filter { $0 == "\n" }.count > 2
                                }
                            }
                        })
                        .hidden()
                )
                .animation(.easeInOut(duration: 0.3), value: isExpanded)

            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("profile.content.seeLess", comment: "See less text") : NSLocalizedString("profile.content.seeMore", comment: "See more text"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(ProfileColors.accent)
                        .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flow Layout para intereses
struct ProfileFlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
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

// MARK: - Preference Key para scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ProfileIdentityMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum ProfileHeaderCollapseMetrics {
    /// Altura de la fila de botones (topBar original en git: iconos 36pt).
    static let chromeHeight: CGFloat = 36
    /// Padding superior del chrome flotante sobre el safe area.
    static let topChromePadding: CGFloat = 4
    /// Espacio entre topBar y avatar en git: VStack(10) + padding(.top, 18).
    static let identitySectionGap: CGFloat = 28
    /// Padding del bloque header en el scroll (ProfileShellComponents).
    static let headerTopPadding: CGFloat = 4
    static var topContentInset: CGFloat { chromeHeight + identitySectionGap }
    static let collapseDistance: CGFloat = 52

    static func progress(for identityMinY: CGFloat, scrollContentMinY: CGFloat) -> CGFloat {
        let collapseStartY = topContentInset + headerTopPadding

        let fromIdentity: CGFloat = {
            guard identityMinY.isFinite, identityMinY < 10_000 else { return 0 }
            guard identityMinY < collapseStartY else { return 0 }
            return min(max((collapseStartY - identityMinY) / collapseDistance, 0), 1)
        }()

        let scrolled = max(-scrollContentMinY, 0)
        let scrollTrigger = max(topContentInset * 0.55, 20)
        let fromScroll = min(max((scrolled - scrollTrigger) / collapseDistance, 0), 1)
        return max(fromIdentity, fromScroll)
    }
}
