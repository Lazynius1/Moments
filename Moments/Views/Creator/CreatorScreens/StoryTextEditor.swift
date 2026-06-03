// MARK: - Filter Selection Implementation
// MARK: - Story Text Editor Implementation

import SwiftUI
import UIKit

struct StoryTextEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @Binding var text: String
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @Binding var textStroke: StoryEditingView.TextStroke
    @Binding var textMotion: StoryEditingView.TextMotion
    @Binding var visualEffect: StoryEditingView.TextEffect
    @Binding var forcesAllCaps: Bool
    var mediaSampleImage: UIImage?

    @State private var isTextFieldFocused = false
    @StateObject private var keyboardMonitor = KeyboardMonitor()
    @State private var activeContext: StoryTextEditorContext = .fonts
    @State private var isEyedropperActive = false
    @State private var suggestedColors: [Color] = []
    @State private var motionPreviewToken = 0

    private var renderConfiguration: StoryTextRenderConfiguration {
        StoryTextRenderConfiguration(
            text: text,
            style: selectedStyle,
            visualEffect: visualEffect,
            textColor: textColor,
            textAlignment: textAlignment,
            textBackgroundFill: textBackgroundFill,
            fontSize: textFontSize,
            textStroke: textStroke,
            forcesAllCaps: forcesAllCaps,
            appliesDisplayTransform: true
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let keyboardInset = max(0, keyboardMonitor.keyboardHeight - proxy.safeAreaInsets.bottom)
            let bottomToolbarLift = keyboardInset > 0
                ? keyboardInset + StoryTextEditorChrome.keyboardChromeGap
                : 0
            let chromeHeight = StoryTextEditorChrome.totalHeight(for: activeContext)

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if isEyedropperActive, let image = mediaSampleImage {
                        textColor = StoryDominantColorsExtractor.sampleColor(
                            at: location,
                            in: image,
                            viewSize: canvasSize
                        )
                        isEyedropperActive = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else {
                        hideKeyboard()
                    }
                }
                .overlay(alignment: .top) {
                    if isEyedropperActive {
                        Text(NSLocalizedString("storyTextEditor.eyedropperHint", comment: "Tap photo to pick color"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .padding(.top, 72)
                    }
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: 12) {
                        FontSizeSlider(value: $textFontSize, range: 16...72)

                        StoryTextEditorInputRepresentable(
                            text: $text,
                            isFocused: $isTextFieldFocused,
                            configuration: renderConfiguration,
                            motion: textMotion,
                            maxWidth: max(canvasSize.width - 108, 120),
                            replayToken: motionPreviewToken
                        )
                        .frame(minHeight: 140, maxHeight: 280)
                    }
                    .frame(maxWidth: .infinity, alignment: alignmentForText(textAlignment))
                    .padding(.leading, 4)
                    .padding(.trailing, 20)

                    Spacer(minLength: 0)
                }
                .padding(.bottom, chromeHeight)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay(alignment: .top) {
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .padding(14)
                    }
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, topBarTopPadding(proxy.safeAreaInsets.top))
            }
            .overlay(alignment: .bottom) {
                StoryMomentsEditorChrome(
                    selectedStyle: $selectedStyle,
                    textColor: $textColor,
                    textAlignment: $textAlignment,
                    textBackgroundFill: $textBackgroundFill,
                    textMotion: $textMotion,
                    visualEffect: $visualEffect,
                    forcesAllCaps: $forcesAllCaps,
                    activeContext: $activeContext,
                    swatchColors: editorPalette,
                    suggestedColors: suggestedColors,
                    onEyedropper: mediaSampleImage != nil ? {
                        isEyedropperActive = true
                    } : nil,
                    onStyleSelect: applyStyleSelection,
                    onBackground: {
                        cycleTextBackgroundFill()
                    }
                )
                .padding(.bottom, safeAreaBottom + StoryTextEditorChrome.chromeBottomPadding)
                .offset(y: -bottomToolbarLift)
                .animation(.easeOut(duration: 0.22), value: bottomToolbarLift)
                .animation(.easeOut(duration: 0.18), value: activeContext)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .all)
        .onAppear {
            suggestedColors = StoryDominantColorsExtractor.extract(from: mediaSampleImage)
            if selectedStyle.preset.usesAllCaps {
                forcesAllCaps = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onChange(of: mediaSampleImage) { _, newImage in
            suggestedColors = StoryDominantColorsExtractor.extract(from: newImage)
        }
        .onChange(of: textMotion) { _, _ in
            motionPreviewToken += 1
        }
        .onChange(of: visualEffect) { _, _ in
            motionPreviewToken += 1
        }
    }

    private func applyStyleSelection(_ style: StoryEditingView.TextStyle) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
            selectedStyle = style
            var legacyEffect = visualEffect
            style.applyPreset(
                textColor: &textColor,
                textBackgroundFill: &textBackgroundFill,
                selectedEffect: &legacyEffect,
                textStroke: &textStroke
            )
            if style == .meme {
                textStroke = .thick
            }
            visualEffect = legacyEffect
            forcesAllCaps = style.preset.usesAllCaps
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func cycleTextBackgroundFill() {
        switch textBackgroundFill {
        case .none:
            textBackgroundFill = .black
            reconcileTextColorForBackground()
        case .black:
            textBackgroundFill = .white
            reconcileTextColorForBackground()
        case .white:
            textBackgroundFill = .none
            if visualEffect == .marker, isDarkColor(textColor) {
                textColor = .black
            }
        }
    }

    private func reconcileTextColorForBackground() {
        switch textBackgroundFill {
        case .black:
            if isDarkColor(textColor) || visualEffect == .neon {
                textColor = .white
            }
        case .white:
            if isLightColor(textColor) || visualEffect == .marker {
                textColor = .black
            }
        case .none:
            break
        }
    }

    private func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)
        var white: CGFloat = 0, alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) { return white > 0.82 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &alpha) {
            return (0.299 * r + 0.587 * g + 0.114 * b) > 0.82
        }
        return false
    }

    private func isDarkColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)
        var white: CGFloat = 0, alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) { return white < 0.22 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &alpha) {
            return (0.299 * r + 0.587 * g + 0.114 * b) < 0.22
        }
        return false
    }

    private func alignmentForText(_ alignment: TextAlignment) -> Alignment {
        switch alignment {
        case .leading:  return .leading
        case .trailing: return .trailing
        default:        return .center
        }
    }


    private var editorTextBackgroundUIColor: UIColor? {
        StoryTextAttributesBuilder.backgroundUIColor(
            fill: textBackgroundFill,
            effect: visualEffect,
            style: selectedStyle
        )
    }

    private var editorPalette: [Color] {
        [
            .white, .black,
            Color(hex: "FF3B30"), Color(hex: "FF9500"), Color(hex: "FFCC00"),
            Color(hex: "34C759"), Color(hex: "007AFF"), Color(hex: "5856D6"),
            Color(hex: "AF52DE"), Color(hex: "FF2D55"), Color(hex: "A2845E"),
            Color(hex: "F2C94C"), Color(hex: "00C7BE"), Color(hex: "8E8E93"),
            Color(hex: "FFD60A"), Color(hex: "BF5AF2"), Color(hex: "64D2FF"),
            Color(hex: "FF6B6B"), Color(hex: "C4B5A5"), Color(hex: "1C1C1E")
        ]
    }

    private func topBarTopPadding(_ safeAreaTop: CGFloat) -> CGFloat {
        let fallbackSafeTop = keyWindowSafeAreaInsets().top
        let resolvedSafeTop = max(safeAreaTop, fallbackSafeTop)
        return resolvedSafeTop + 10
    }

    private func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private var safeAreaBottom: CGFloat {
        keyWindowSafeAreaInsets().bottom
    }
}

// MARK: - TextEffectModifier
struct TextEffectModifier: ViewModifier {
    let effect: StoryEditingView.TextEffect
    let textColor: Color

    func body(content: Content) -> some View {
        if let shadow = effect.shadow(for: textColor) {
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            content
        }
    }
}

// MARK: - StoryStyledTextView
struct StoryStyledTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let configuration: StoryTextRenderConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.keyboardAppearance = .dark
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.tintColor = UIColor(configuration.textColor)
        applyAttributes(to: textView, preserveSelection: false)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        let selectedRange = uiView.selectedRange
        uiView.tintColor = UIColor(configuration.textColor)
        uiView.textAlignment = nsTextAlignment

        if uiView.attributedText.string != configuration.displayText
            || context.coordinator.lastAppliedSignature != attributesSignature {
            applyAttributes(to: uiView, preserveSelection: true)
            context.coordinator.lastAppliedSignature = attributesSignature
            let safeLocation = min(selectedRange.location, uiView.attributedText.length)
            let remaining = uiView.attributedText.length - safeLocation
            uiView.selectedRange = NSRange(location: safeLocation, length: min(selectedRange.length, remaining))
        } else {
            uiView.typingAttributes = StoryTextAttributesBuilder.typingAttributes(for: configuration)
        }

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private var attributesSignature: String {
        [
            configuration.style.rawValue,
            configuration.effect.rawValue,
            configuration.textStroke.rawValue,
            "\(configuration.textColor)",
            "\(configuration.textAlignment)",
            "\(configuration.textBackgroundFill)",
            "\(configuration.fontSize)",
            "\(configuration.forcesAllCaps)",
            configuration.displayText
        ].joined(separator: "|")
    }

    private var nsTextAlignment: NSTextAlignment {
        switch configuration.textAlignment {
        case .leading: return .left
        case .trailing: return .right
        default: return .center
        }
    }

    private func applyAttributes(to textView: UITextView, preserveSelection: Bool) {
        let attributes = StoryTextAttributesBuilder.typingAttributes(for: configuration)
        textView.typingAttributes = attributes
        textView.attributedText = StoryTextAttributesBuilder.attributedString(for: configuration)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StoryStyledTextView
        var lastAppliedSignature: String

        init(parent: StoryStyledTextView) {
            self.parent = parent
            self.lastAppliedSignature = parent.attributesSignature
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.typingAttributes = StoryTextAttributesBuilder.typingAttributes(for: parent.configuration)
        }
    }
}

// MARK: - TextStyleOption (kept for backward compat)
struct TextStyleOption: View {
    let style: StoryEditingView.TextStyle
    let isSelected: Bool
    let onTap: () -> Void

    var stylePreview: String { "Aa" }

    var body: some View {
        Button(action: onTap) {
            Text(stylePreview)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    ZStack {
                        style.backgroundColor
                        if style.backgroundColor == .clear {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )
        }
    }
}

// MARK: - FontSizeSlider
struct FontSizeSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var lastHapticStep: Int = -1

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let progress = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
            let knobY = (1 - progress) * (height - 14)

            ZStack(alignment: .top) {
                // Hairline track
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)

                // Glassmorphic knob
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .offset(x: 0, y: knobY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 7), height - 7)
                        let inverseProgress = 1 - ((clampedY - 7) / max(height - 14, 1))
                        value = range.lowerBound + (inverseProgress * (range.upperBound - range.lowerBound))

                        // Haptic every ~10% of range
                        let totalSteps = 10
                        let currentStep = Int(inverseProgress * CGFloat(totalSteps))
                        if currentStep != lastHapticStep {
                            lastHapticStep = currentStep
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )
        }
        .frame(width: 18, height: 176)
    }
}

// MARK: - ColorOption
struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    private var swatchStrokeColor: Color {
        color == .white ? Color.gray.opacity(0.9) : Color.white.opacity(0.92)
    }

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.white : swatchStrokeColor,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AlignmentButton (kept for backward compat)
struct AlignmentButton: View {
    let alignment: TextAlignment
    @Binding var currentAlignment: TextAlignment
    let icon: String

    var body: some View {
        Button(action: {
            currentAlignment = alignment
        }) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(currentAlignment == alignment ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(currentAlignment == alignment ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(currentAlignment == alignment ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard Monitor
class KeyboardMonitor: NSObject, ObservableObject {
    @Published var keyboardHeight: CGFloat = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillChangeFrame(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let activeWindow: UIWindow? = {
            let windows = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
            if let keyWindow = windows.first(where: { $0.isKeyWindow && !$0.description.contains("RemoteKeyboard") }) {
                return keyWindow
            }
            return windows.first(where: { !$0.description.contains("RemoteKeyboard") }) ?? windows.first
        }()

        let rawHeight: CGFloat
        if let window = activeWindow {
            let convertedFrame = window.convert(keyboardFrame, from: nil)
            rawHeight = max(0, window.bounds.height - convertedFrame.minY)
        } else {
            let screenHeight = UIScreen.main.bounds.height
            rawHeight = max(0, screenHeight - keyboardFrame.minY)
        }

        let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.22

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: duration)) {
                self.keyboardHeight = rawHeight
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: NSNotification) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                self.keyboardHeight = 0
            }
        }
    }
}
