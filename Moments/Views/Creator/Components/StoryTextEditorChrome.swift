import SwiftUI

// MARK: - Moments: 2 filas (contexto + toolbar). 6 tools en toolbar (sin IA).

enum StoryTextEditorChrome {
    static let selectionFill = Color.white
    static let chipIdleFill = Color.white.opacity(0.14)
    static let toolbarFill = Color.white.opacity(0.14)
    static let toolbarHeight: CGFloat = 44
    static let contextRowHeight: CGFloat = 40
    static let chromeSpacing: CGFloat = 8
    /// Extra gap between keyboard top and chrome.
    static let keyboardChromeGap: CGFloat = 18
    static let chromeBottomPadding: CGFloat = 12

    static var totalHeight: CGFloat {
        contextRowHeight + chromeSpacing + toolbarHeight
    }

    static func totalHeight(for context: StoryTextEditorContext) -> CGFloat {
        contextRowHeight + chromeSpacing + toolbarHeight
    }
}

enum StoryTextEditorContext: Equatable {
    case fonts
    case colors
    case motion
    case visual
}

struct StoryMomentsFontRow: View {
    @Binding var selectedStyle: StoryEditingView.TextStyle
    let onSelect: (StoryEditingView.TextStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StoryEditingView.TextStyle.fontPickerStyles, id: \.self) { style in
                    fontChip(style)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func fontChip(_ style: StoryEditingView.TextStyle) -> some View {
        let isSelected = selectedStyle == style

        return Button {
            onSelect(style)
        } label: {
            Text(style.displayName)
                .font(style.font(size: 15))
                .foregroundColor(isSelected ? .black : .white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? StoryTextEditorChrome.selectionFill : StoryTextEditorChrome.chipIdleFill)
                )
        }
        .buttonStyle(.plain)
    }
}

struct StoryTextEditorContextRow: View {
    let context: StoryTextEditorContext
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Binding var textColor: Color
    @Binding var textMotion: StoryEditingView.TextMotion
    @Binding var visualEffect: StoryEditingView.TextEffect
    let swatchColors: [Color]
    let suggestedColors: [Color]
    var onEyedropper: (() -> Void)?
    let onStyleSelect: (StoryEditingView.TextStyle) -> Void

    var body: some View {
        Group {
            switch context {
            case .fonts:
                StoryMomentsFontRow(selectedStyle: $selectedStyle, onSelect: onStyleSelect)
            case .colors:
                colorContext
            case .motion:
                pillContext(
                    items: StoryEditingView.TextMotion.momentsToolbarMotions.map { ($0.displayName, $0) },
                    isSelected: { textMotion == $0 },
                    onSelect: { textMotion = $0 }
                )
            case .visual:
                pillContext(
                    items: StoryEditingView.TextEffect.momentsVisualToolbar.map { ($0.momentsToolbarLabel, $0) },
                    isSelected: { visualEffect == $0 },
                    onSelect: { visualEffect = $0 }
                )
            }
        }
        .frame(height: StoryTextEditorChrome.contextRowHeight)
        .animation(.easeOut(duration: 0.18), value: context)
    }

    private var colorContext: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Apple's native Color Picker
                ColorPicker("", selection: $textColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 24, height: 24)

                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))

                // Moments backgrounds: Light (#FAF9F6) & Dark (#0B1215)
                ColorOption(color: Color(hex: "FAF9F6"), isSelected: textColor == Color(hex: "FAF9F6")) {
                    textColor = Color(hex: "FAF9F6")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                ColorOption(color: Color(hex: "0B1215"), isSelected: textColor == Color(hex: "0B1215")) {
                    textColor = Color(hex: "0B1215")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))

                ForEach(Array(suggestedColors.enumerated()), id: \.offset) { _, color in
                    ColorOption(color: color, isSelected: textColor == color) {
                        textColor = color
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                ForEach(Array(swatchColors.enumerated()), id: \.offset) { _, color in
                    ColorOption(color: color, isSelected: textColor == color) {
                        textColor = color
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                if let onEyedropper {
                    Button(action: onEyedropper) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func pillContext<T: Equatable>(
        items: [(String, T)],
        isSelected: @escaping (T) -> Bool,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let (title, value) = item
                    Button {
                        onSelect(value)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSelected(value) ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected(value) ? StoryTextEditorChrome.selectionFill : StoryTextEditorChrome.chipIdleFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - 6 tools: Aa · color · motion · background · align · outline

struct StoryMomentsTextToolbar: View {
    @Binding var activeContext: StoryTextEditorContext
    @Binding var forcesAllCaps: Bool
    let styleUsesCaps: Bool
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    let selectedColor: Color
    let onAlignment: () -> Void
    let onBackground: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            toolbarIcon(
                label: forcesAllCaps || styleUsesCaps ? "AA" : "Aa",
                isActive: activeContext == .fonts
            ) {
                selectContext(.fonts)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    forcesAllCaps.toggle()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            )

            toolbarDivider

            toolbarAccessoryToggle(isActive: activeContext == .colors) {
                colorWheelIcon
            } action: {
                selectContext(.colors)
            }

            toolbarDivider

            toolbarAccessoryToggle(
                isActive: activeContext == .motion,
                systemName: "text.line.first.and.arrowtriangle.forward"
            ) {
                selectContext(.motion)
            }

            toolbarDivider

            toolbarIcon(
                label: "A",
                isActive: activeContext == .visual
            ) {
                selectContext(.visual)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(activeContext == .visual ? .yellow : .white.opacity(0.7))
                    .offset(x: 4, y: -2)
            }

            toolbarDivider

            toolbarIcon(systemName: alignmentIcon, isActive: true, action: onAlignment)

            toolbarDivider

            toolbarBackgroundButton(action: onBackground)
        }
        .frame(height: StoryTextEditorChrome.toolbarHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(StoryTextEditorChrome.toolbarFill)
        )
        .padding(.horizontal, 12)
    }

    private func selectContext(_ context: StoryTextEditorContext) {
        withAnimation(.easeOut(duration: 0.18)) {
            if activeContext == context, context != .fonts {
                activeContext = .fonts
            } else {
                activeContext = context
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var colorWheelIcon: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [.red, .yellow, .green, .blue, .purple, .red],
                    center: .center
                )
            )
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
    }

    private var alignmentIcon: String {
        switch textAlignment {
        case .leading: return "text.alignleft"
        case .trailing: return "text.alignright"
        default: return "text.aligncenter"
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 24)
    }

    private func toolbarIcon(
        label: String? = nil,
        systemName: String? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label)
                        .font(.system(size: 15, weight: .bold))
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: StoryTextEditorChrome.toolbarHeight)
        }
        .buttonStyle(.plain)
    }

    private func toolbarAccessoryToggle(
        isActive: Bool,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(isActive ? .white : .white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .frame(height: StoryTextEditorChrome.toolbarHeight)
        }
        .buttonStyle(.plain)
    }

    private func toolbarAccessoryToggle<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: StoryTextEditorChrome.toolbarHeight)
        }
        .buttonStyle(.plain)
    }

    private func toolbarBackgroundButton(action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundPreviewFill)
                    .frame(width: 22, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(textBackgroundFill == .none ? Color.white.opacity(0.55) : Color.clear, lineWidth: 1)
                    )
                Text("A")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textForegroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: StoryTextEditorChrome.toolbarHeight)
        }
        .buttonStyle(.plain)
    }

    private var backgroundPreviewFill: Color {
        switch textBackgroundFill {
        case .none:
            return .clear
        case .solid:
            return selectedColor
        case .semiTransparent:
            return selectedColor.opacity(0.70)
        case .inverted:
            return contrastColorIsDark ? .white : .black
        }
    }

    private var textForegroundColor: Color {
        switch textBackgroundFill {
        case .none:
            return .white
        case .solid, .semiTransparent:
            return contrastColorIsDark ? .black : .white
        case .inverted:
            return selectedColor
        }
    }

    private var contrastColorIsDark: Bool {
        let uiColor = UIColor(selectedColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.68
    }
}

struct StoryMomentsEditorChrome: View {
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textMotion: StoryEditingView.TextMotion
    @Binding var visualEffect: StoryEditingView.TextEffect
    @Binding var forcesAllCaps: Bool
    @Binding var activeContext: StoryTextEditorContext

    let swatchColors: [Color]
    let suggestedColors: [Color]
    var onEyedropper: (() -> Void)?
    let onStyleSelect: (StoryEditingView.TextStyle) -> Void
    let onBackground: () -> Void

    var body: some View {
        VStack(spacing: StoryTextEditorChrome.chromeSpacing) {
            StoryTextEditorContextRow(
                context: activeContext,
                selectedStyle: $selectedStyle,
                textColor: $textColor,
                textMotion: $textMotion,
                visualEffect: $visualEffect,
                swatchColors: swatchColors,
                suggestedColors: suggestedColors,
                onEyedropper: onEyedropper,
                onStyleSelect: onStyleSelect
            )

            StoryMomentsTextToolbar(
                activeContext: $activeContext,
                forcesAllCaps: $forcesAllCaps,
                styleUsesCaps: selectedStyle.preset.usesAllCaps,
                textAlignment: $textAlignment,
                textBackgroundFill: $textBackgroundFill,
                selectedColor: textColor,
                onAlignment: {
                    switch textAlignment {
                    case .center: textAlignment = .leading
                    case .leading: textAlignment = .trailing
                    default: textAlignment = .center
                    }
                },
                onBackground: onBackground
            )
        }
    }
}
