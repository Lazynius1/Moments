import SwiftUI
import UIKit

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
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundColor(ProfileColors.textPrimary)

                Text(errorMessage)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                    Text("profile.error.retryButton")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
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
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundColor(ProfileColors.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.system(size: legacyPoppinsSize(15)))
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
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isExpanded), value: isExpanded)

            if needsExpansion {
                Button(action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("profile.content.seeLess", comment: "See less text") : NSLocalizedString("profile.content.seeMore", comment: "See more text"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
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

enum ProfileAvatarNoteMetrics {
    static let maxLength = 28
    static let columnWidth: CGFloat = 96
}

/// Nota corta bajo el avatar: vibe, emojis o frase breve.
struct ProfileAvatarNoteView: View {
    let note: String?
    let isEditable: Bool
    var onSave: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var displayText: String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var shouldShow: Bool {
        isEditable || displayText != nil
    }

    var body: some View {
        Group {
            if shouldShow {
                content
                    .frame(width: ProfileAvatarNoteMetrics.columnWidth)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            TextField(
                NSLocalizedString("profile.avatarNote.placeholder", comment: "Avatar note placeholder"),
                text: $draft
            )
            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { commitEdit() }
            .onChange(of: draft) { _, newValue in
                if newValue.contains("\n") {
                    draft = newValue
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    commitEdit()
                    return
                }
                if newValue.count > ProfileAvatarNoteMetrics.maxLength {
                    draft = String(newValue.prefix(ProfileAvatarNoteMetrics.maxLength))
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused && isEditing {
                    commitEdit()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        commitEdit()
                    }
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                }
            }
            .onAppear {
                draft = displayText ?? ""
                isFocused = true
            }
        } else if let displayText {
            Text(displayText)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isEditable else { return }
                    draft = displayText
                    isEditing = true
                }
        } else if isEditable {
            Text(NSLocalizedString("profile.avatarNote.placeholder", comment: "Avatar note placeholder"))
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    draft = ""
                    isEditing = true
                }
        }
    }

    private func commitEdit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?(trimmed)
        isEditing = false
        isFocused = false
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

struct ProfileTabsMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

final class IntensityBlurUIView: UIVisualEffectView {
    private var animator: UIViewPropertyAnimator?

    deinit {
        animator?.stopAnimation(true)
    }

    func setIntensity(_ intensity: CGFloat) {
        let clampedIntensity = min(max(intensity, 0), 1)

        guard clampedIntensity > 0 else {
            animator?.stopAnimation(true)
            animator = nil
            effect = nil
            return
        }

        animator?.stopAnimation(true)
        effect = nil
        animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .regular)
        }
        animator?.pausesOnCompletion = true
        animator?.fractionComplete = clampedIntensity
    }
}

struct ProfileBackdropBlur: UIViewRepresentable {
    var intensity: CGFloat
    var maxFraction: CGFloat = 0.14

    func makeUIView(context: Context) -> IntensityBlurUIView {
        let view = IntensityBlurUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }

    func updateUIView(_ view: IntensityBlurUIView, context: Context) {
        view.setIntensity(intensity * maxFraction)
    }
}

struct ProfileProgressiveBlurBackground: View {
    let progress: CGFloat
    var fadeTail: CGFloat = 48
    var maxBlurFraction: CGFloat = 0.14

    var body: some View {
        ProfileBackdropBlur(intensity: progress, maxFraction: maxBlurFraction)
            .padding(.bottom, -fadeTail)
            .mask(Self.fadeMask(fadeTail: fadeTail))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    fileprivate static func fadeMask(fadeTail: CGFloat) -> some View {
        LinearGradient(
            stops: gradientStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.bottom, -fadeTail)
    }

    fileprivate static let gradientStops: [Gradient.Stop] = [
        .init(color: .black, location: 0),
        .init(color: .black, location: 0.25),
        .init(color: .black.opacity(0.55), location: 0.6),
        .init(color: .black.opacity(0.2), location: 0.85),
        .init(color: .black.opacity(0), location: 1)
    ]
}

/// Drop progresivo del chrome sticky: híbrido blur + Liquid Glass en iOS 26+.
struct ProfileProgressiveChromeBackdrop: View {
    let progress: CGFloat
    var fadeTail: CGFloat = ProfileChromeGlassMetrics.chromeBackdropFadeTail
    var maxBlurFraction: CGFloat = ProfileChromeGlassMetrics.chromeBackdropMaxBlurFraction
    var glassOnly: Bool = false
    var blurOnly: Bool = false

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                if blurOnly {
                    blurOnlyBackdrop
                } else if glassOnly {
                    glassOnlyBackdrop
                } else {
                    hybridGlassBackdrop
                }
            } else {
                if blurOnly {
                    ProfileProgressiveBlurBackground(
                        progress: progress,
                        fadeTail: fadeTail,
                        maxBlurFraction: maxBlurFraction
                    )
                } else if glassOnly {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(clampedProgress)
                        .padding(.bottom, -fadeTail)
                        .mask(ProfileProgressiveBlurBackground.fadeMask(fadeTail: fadeTail))
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                } else {
                    ProfileProgressiveBlurBackground(
                        progress: progress,
                        fadeTail: fadeTail,
                        maxBlurFraction: maxBlurFraction
                    )
                }
            }
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var blurOnlyBackdrop: some View {
        ProfileProgressiveBlurBackground(
            progress: progress,
            fadeTail: fadeTail,
            maxBlurFraction: maxBlurFraction
        )
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var glassOnlyBackdrop: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular, in: Rectangle())
            .opacity(clampedProgress)
            .padding(.bottom, -fadeTail)
            .mask(ProfileProgressiveBlurBackground.fadeMask(fadeTail: fadeTail))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var hybridGlassBackdrop: some View {
        ZStack {
            ProfileBackdropBlur(intensity: clampedProgress, maxFraction: maxBlurFraction)
                .opacity(clampedProgress * 0.45)

            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: Rectangle())
                .opacity(clampedProgress * 0.92)

            Rectangle()
                .fill(.clear)
                .glassEffect(.identity, in: Rectangle())
                .opacity(max(0, (clampedProgress - 0.42) / 0.58) * 0.35)
        }
        .padding(.bottom, -fadeTail)
        .mask(ProfileProgressiveBlurBackground.fadeMask(fadeTail: fadeTail))
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

/// Mismo contenedor del chrome sticky del perfil: padding + blur de 2 capas.
struct ProfileStickyChromeContainer<Chrome: View, Tabs: View>: View {
    let blurProgress: CGFloat
    var blurFadeTail: CGFloat = ProfileChromeGlassMetrics.chromeBackdropFadeTail
    var maxBlurFraction: CGFloat = ProfileChromeGlassMetrics.chromeBackdropMaxBlurFraction
    var glassOnly: Bool = false
    var blurOnly: Bool = false
    var tintOpacity: CGFloat = 0
    var horizontalPadding: CGFloat = 20
    let tabsArePinned: Bool
    @ViewBuilder let chrome: () -> Chrome
    @ViewBuilder let pinnedTabs: () -> Tabs

    init(
        blurProgress: CGFloat,
        blurFadeTail: CGFloat = ProfileChromeGlassMetrics.chromeBackdropFadeTail,
        maxBlurFraction: CGFloat = ProfileChromeGlassMetrics.chromeBackdropMaxBlurFraction,
        glassOnly: Bool = false,
        blurOnly: Bool = false,
        tintOpacity: CGFloat = 0,
        horizontalPadding: CGFloat = 20,
        tabsArePinned: Bool = false,
        @ViewBuilder chrome: @escaping () -> Chrome,
        @ViewBuilder pinnedTabs: @escaping () -> Tabs = { EmptyView() }
    ) {
        self.blurProgress = blurProgress
        self.blurFadeTail = blurFadeTail
        self.maxBlurFraction = maxBlurFraction
        self.glassOnly = glassOnly
        self.blurOnly = blurOnly
        self.tintOpacity = tintOpacity
        self.horizontalPadding = horizontalPadding
        self.tabsArePinned = tabsArePinned
        self.chrome = chrome
        self.pinnedTabs = pinnedTabs
    }

    var body: some View {
        VStack(spacing: 8) {
            chrome()
            if tabsArePinned {
                pinnedTabs()
                    .transition(.opacity)
            }
        }
        .padding(.top, ProfileHeaderCollapseMetrics.topChromePadding)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, tabsArePinned ? 8 : 0)
        .background {
            ZStack {
                ProfileProgressiveChromeBackdrop(
                    progress: blurProgress,
                    fadeTail: blurFadeTail,
                    maxBlurFraction: maxBlurFraction,
                    glassOnly: glassOnly,
                    blurOnly: blurOnly
                )

                if tintOpacity > 0 {
                    Rectangle()
                        .fill(.white.opacity(tintOpacity))
                        .padding(.bottom, -blurFadeTail)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.28),
                                    .init(color: .black.opacity(0.45), location: 0.68),
                                    .init(color: .black.opacity(0), location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .padding(.bottom, -blurFadeTail)
                        )
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum ProfileHeaderCollapseMetrics {
    static let chromeHeight: CGFloat = 36
    static let topChromePadding: CGFloat = 4
    static let identitySectionGap: CGFloat = 28
    static let headerTopPadding: CGFloat = 4
    static let pinnedTabsHeight: CGFloat = ProfileChromeGlassMetrics.pillBarHeight
    /// Blur fijo en ubicación: intensidad típica del perfil al hacer scroll (no al máximo).
    static let fixedLocationChromeBlurProgress: CGFloat = 0.68
    /// Cola más corta que con tabs pegadas — feed de detalle (explorer, single…).
    static let feedDetailChromeBlurFadeTail: CGFloat = ProfileChromeGlassMetrics.feedDetailBlurFadeTail
    /// Cola más corta que con tabs pegadas — el del mapa no debe llegar tan abajo.
    static let locationChromeBlurFadeTail: CGFloat = ProfileChromeGlassMetrics.feedDetailBlurFadeTail
    static var topContentInset: CGFloat { chromeHeight + identitySectionGap }
    /// Altura del chrome sticky con slot de tabs (como perfil con tabs pegadas).
    static var stickyChromeBlurRegionHeight: CGFloat {
        topChromePadding + chromeHeight + 8 + pinnedTabsHeight + 8
    }
    static var stickyChromeContentInset: CGFloat { stickyChromeBlurRegionHeight }
    /// Espacio superior del feed en detalle estilo feed (ubicación, explorer…).
    static var feedStyleDetailTopInset: CGFloat {
        topChromePadding + chromeHeight + 12
    }
    /// Alias histórico — ubicación y explorer comparten inset.
    static var locationFeedTopInset: CGFloat { feedStyleDetailTopInset }

    static let feedStoriesChromeHeight: CGFloat = 88

    /// Misma curva que `progress(forTabsMinY:)` pero el marcador del feed descansa en `contentTopInset`.
    static func feedScrollChromeBlurProgress(contentMinY: CGFloat, contentTopInset: CGFloat) -> CGFloat {
        guard contentMinY.isFinite, contentMinY < 10_000 else { return 0 }
        let start = contentTopInset
        guard contentMinY < start else { return 0 }
        return min(max((start - contentMinY) / tabsFadeLead, 0), 1)
    }

    /// Para detalles tipo explorer/map: sin blur al inicio; empieza solo cuando el contenido
    /// ya se ha desplazado hacia arriba respecto a su posicion inicial.
    static func detailScrollChromeBlurProgress(
        contentMinY: CGFloat,
        initialContentMinY: CGFloat,
        fadeLead: CGFloat = 64
    ) -> CGFloat {
        guard contentMinY.isFinite, initialContentMinY.isFinite else { return 0 }
        let upwardTravel = initialContentMinY - contentMinY
        guard upwardTravel > 0 else { return 0 }
        return min(max(upwardTravel / fadeLead, 0), 1)
    }

    static var tabsPinY: CGFloat { topChromePadding + chromeHeight + 8 }
    static let tabsFadeLead: CGFloat = 96
    static func progress(forTabsMinY tabsMinY: CGFloat) -> CGFloat {
        guard tabsMinY.isFinite, tabsMinY < 10_000 else { return 0 }
        let start = tabsPinY + tabsFadeLead
        guard tabsMinY < start else { return 0 }
        return min(max((start - tabsMinY) / tabsFadeLead, 0), 1)
    }

    static func tabsArePinned(tabsMinY: CGFloat) -> Bool {
        tabsMinY.isFinite && tabsMinY <= tabsPinY + 0.5
    }
}

/// Tipografía del título en chrome sticky (feed + perfil al hacer scroll).
enum StickyChromeTitleTypography {
    static let font: Font = .system(size: 17, weight: .semibold)
}

struct StickyChromeBarLayout<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                leading()

                Spacer(minLength: 0)

                trailing()
            }

            center()
                .padding(.horizontal, 56)
        }
        .frame(height: ProfileHeaderCollapseMetrics.chromeHeight)
    }
}

/// Chrome fijo con título centrado y chevron (detalle feed: ubicación, explorer…).
struct FeedPinnedTopChrome: View {
    let title: String
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        StickyChromeBarLayout {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: adaptiveColors.primary,
                preset: .navigationBack,
                action: onDismiss
            )
        } center: {
            Text(title)
                .font(StickyChromeTitleTypography.font)
                .foregroundColor(adaptiveColors.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } trailing: {
            Color.clear
                .frame(
                    width: MomentsGlassButtonPreset.navigationBack.controlSize,
                    height: MomentsGlassButtonPreset.navigationBack.controlSize
                )
        }
    }
}
