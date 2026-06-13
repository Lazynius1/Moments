import SwiftUI
import UIKit

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
            .font(.custom("Poppins-Medium", size: 12))
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
                    .font(.custom("Poppins-SemiBold", size: 15))
                }
            }
            .onAppear {
                draft = displayText ?? ""
                isFocused = true
            }
        } else if let displayText {
            Text(displayText)
                .font(.custom("Poppins-Medium", size: 12))
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
                .font(.custom("Poppins-Medium", size: 12))
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
        animator?.stopAnimation(true)
        effect = nil
        animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .regular)
        }
        animator?.pausesOnCompletion = true
        animator?.fractionComplete = min(max(intensity, 0.0001), 1)
    }
}

struct ProfileBackdropBlur: UIViewRepresentable {
    var intensity: CGFloat
    var maxFraction: CGFloat = 0.07

    func makeUIView(context: Context) -> IntensityBlurUIView {
        IntensityBlurUIView()
    }

    func updateUIView(_ view: IntensityBlurUIView, context: Context) {
        view.setIntensity(intensity * maxFraction)
    }
}


struct ProfileProgressiveBlurBackground: View {
    let progress: CGFloat
    var fadeTail: CGFloat = 48

    var body: some View {
        ProfileBackdropBlur(intensity: progress)
            .padding(.bottom, -fadeTail)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.25),
                        .init(color: .black.opacity(0.55), location: 0.6),
                        .init(color: .black.opacity(0.2), location: 0.85),
                        .init(color: .black.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.bottom, -fadeTail)
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

enum ProfileHeaderCollapseMetrics {
    static let chromeHeight: CGFloat = 36
    static let topChromePadding: CGFloat = 4
    static let identitySectionGap: CGFloat = 28
    static let headerTopPadding: CGFloat = 4
    static var topContentInset: CGFloat { chromeHeight + identitySectionGap }
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
