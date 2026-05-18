// MARK: - Filter Selection Implementation
// MARK: - Story Text Editor Implementation

import SwiftUI
import UIKit

struct StoryTextEditor: View {
    @Binding var isPresented: Bool
    @Binding var text: String
    @Binding var selectedStyle: StoryEditingView.TextStyle
    @Binding var selectedEffect: StoryEditingView.TextEffect
    @Binding var textColor: Color
    @Binding var textAlignment: TextAlignment
    @Binding var textBackgroundFill: StoryEditingView.TextBackgroundFill
    @Binding var textFontSize: CGFloat
    @State private var isTextFieldFocused = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var activeTool: EditorTool = .font

    enum EditorTool {
        case font
        case color
        case effect
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let keyboardInset = max(0, keyboardHeight - proxy.safeAreaInsets.bottom)
            let textCanvasLift = keyboardInset > 0 ? min(108, keyboardInset * 0.34) : 0

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                }

                HStack(alignment: .center, spacing: 8) {
                    FontSizeSlider(value: $textFontSize, range: 20...56)

                    StoryStyledTextView(
                        text: $text,
                        isFocused: $isTextFieldFocused,
                        style: selectedStyle,
                        effect: selectedEffect,
                        fontSize: textFontSize,
                        textColor: textColor,
                        textAlignment: textAlignment,
                        backgroundColor: editorTextBackgroundUIColor
                    )
                    .frame(minHeight: 130, maxHeight: 240)
                }
                .frame(maxWidth: .infinity, alignment: alignmentForText(textAlignment))
                .padding(.leading, 2)
                .padding(.trailing, 24)
                .offset(y: -textCanvasLift)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay(alignment: .top) {
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .liquidGlass(in: Circle())
                    }
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Text(NSLocalizedString("storyTextEditor.done", comment: "Done"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .liquidGlass(in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
            }
            .overlay(alignment: .bottom) {
                textEditorBottomToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .offset(y: -textEditorToolbarBottomPadding())
                    .animation(.easeOut(duration: 0.24), value: textEditorToolbarBottomPadding())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .all)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(notification as Foundation.Notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    @ViewBuilder
    private var toolTray: some View {
        switch activeTool {
        case .font:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StoryEditingView.TextStyle.fontPickerStyles, id: \.self) { style in
                        fontPill(for: style)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)

        case .color:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([Color.white, .black, .red, .orange, .yellow, .green, .blue, .purple, .pink], id: \.self) { color in
                        ColorOption(
                            color: color,
                            isSelected: textColor == resolvedColorSelection(for: color)
                        ) {
                            if textBackgroundFill == .white && isLightColor(color) {
                                textColor = .black
                            } else if textBackgroundFill == .black && isDarkColor(color) {
                                textColor = .white
                            } else {
                                textColor = color
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)

        case .effect:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryEditingView.TextEffect.allCases, id: \.self) { effect in
                        effectPill(for: effect)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)
        }
    }

    private var textEditorBottomToolbar: some View {
        VStack(spacing: 10) {
            toolTray

            HStack(spacing: 10) {
                toolButton(
                    isSelected: activeTool == .font,
                    action: { activeTool = .font }
                ) {
                    Text("Aa")
                        .font(.system(size: 24, weight: .regular))
                }

                toolButton(
                    isSelected: activeTool == .color,
                    action: { activeTool = .color }
                ) {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                center: .center
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1.4)
                        )
                }

                toolButton(
                    isSelected: activeTool == .effect,
                    action: { activeTool = .effect }
                ) {
                    Text("≋A")
                        .font(.system(size: 22, weight: .medium))
                }

                toolButton(
                    isSelected: false,
                    action: cycleTextAlignment
                ) {
                    Image(systemName: alignmentIcon)
                        .font(.system(size: 24, weight: .medium))
                }

                toolButton(
                    isSelected: textBackgroundFill != .none,
                    action: cycleTextBackgroundFill
                ) {
                    backgroundFillButtonIcon
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func fontPill(for style: StoryEditingView.TextStyle) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedStyle = style
            }
        } label: {
            Text(style.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedStyle == style ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedStyle == style ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func effectPill(for effect: StoryEditingView.TextEffect) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedEffect = effect
            }
        } label: {
            Text(effect.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selectedEffect == effect ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedEffect == effect ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func toolButton<Content: View>(
        isSelected: Bool,
        foregroundColor: Color = .white,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .foregroundColor(foregroundColor)
                .frame(width: 44, height: 44)
                .background(isSelected ? Color.white.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var alignmentIcon: String {
        switch textAlignment {
        case .leading:
            return "text.alignleft"
        case .trailing:
            return "text.alignright"
        default:
            return "text.aligncenter"
        }
    }

    private var backgroundFillButtonIcon: some View {
        let fillColor: Color = {
            switch textBackgroundFill {
            case .none:
                return .clear
            case .black:
                return Color.black.opacity(0.92)
            case .white:
                return Color.white.opacity(0.96)
            }
        }()

        let strokeColor: Color = textBackgroundFill == .white ? Color.black.opacity(0.22) : Color.white.opacity(0.55)
        let textColor: Color = {
            switch textBackgroundFill {
            case .white:
                return .black.opacity(0.88)
            case .none, .black:
                return .white
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fillColor)
                .frame(width: 24, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1.2)
                )

            Text("A")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(textColor)
        }
    }

    private func cycleTextAlignment() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch textAlignment {
            case .leading:
                textAlignment = .center
            case .center:
                textAlignment = .trailing
            case .trailing:
                textAlignment = .leading
            }
        }
    }

    private func cycleTextBackgroundFill() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch textBackgroundFill {
            case .none:
                textBackgroundFill = .black
                if isDarkColor(textColor) {
                    textColor = .white
                }
            case .black:
                textBackgroundFill = .white
                if isLightColor(textColor) {
                    textColor = .black
                }
            case .white:
                textBackgroundFill = .none
            }
        }
    }

    private func resolvedColorSelection(for color: Color) -> Color {
        if textBackgroundFill == .white && isLightColor(color) {
            return .black
        }
        if textBackgroundFill == .black && isDarkColor(color) {
            return .white
        }
        return color
    }

    private func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)

        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return white > 0.82
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance > 0.82
        }

        return false
    }

    private func isDarkColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)

        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return white < 0.22
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance < 0.22
        }

        return false
    }

    private func alignmentForText(_ alignment: TextAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }

    private func updateKeyboardHeight(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        keyboardHeight = max(0, screenHeight - keyboardFrame.minY)
    }

    private func textEditorToolbarBottomPadding() -> CGFloat {
        if keyboardHeight > 0 {
            return keyboardHeight + 52
        }
        return 60
    }

    private var editorTextBackgroundUIColor: UIColor? {
        switch textBackgroundFill {
        case .none:
            return selectedEffect.uiBackgroundColor
        case .black:
            return UIColor.black.withAlphaComponent(0.58)
        case .white:
            return UIColor.white.withAlphaComponent(0.90)
        }
    }
}

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

struct StoryStyledTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let style: StoryEditingView.TextStyle
    let effect: StoryEditingView.TextEffect
    let fontSize: CGFloat
    let textColor: Color
    let textAlignment: TextAlignment
    let backgroundColor: UIColor?

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
        textView.tintColor = UIColor(textColor)
        textView.typingAttributes = typingAttributes()
        textView.attributedText = NSAttributedString(string: text, attributes: typingAttributes())
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        let selectedRange = uiView.selectedRange
        let attributes = typingAttributes()

        uiView.tintColor = UIColor(textColor)
        uiView.textAlignment = nsTextAlignment
        uiView.typingAttributes = attributes

        if uiView.attributedText.string != text || context.coordinator.lastAppliedSignature != attributesSignature {
            uiView.attributedText = NSAttributedString(string: text, attributes: attributes)
            context.coordinator.lastAppliedSignature = attributesSignature

            let safeLocation = min(selectedRange.location, uiView.attributedText.length)
            let remaining = uiView.attributedText.length - safeLocation
            uiView.selectedRange = NSRange(location: safeLocation, length: min(selectedRange.length, remaining))
        }

        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private var attributesSignature: String {
        let background = backgroundColor?.description ?? "nil"
        return [
            style.rawValue,
            effect.rawValue,
            "\(textColor.description)",
            "\(textAlignment)",
            background,
            "\(fontSize)",
            style.uiFont(size: fontSize).fontName
        ].joined(separator: "|")
    }

    private var nsTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .leading:
            return .left
        case .trailing:
            return .right
        default:
            return .center
        }
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.uiFont(size: fontSize),
            .foregroundColor: UIColor(textColor),
            .paragraphStyle: paragraphStyle
        ]

        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }

        if let shadow = effect.nsShadow(for: UIColor(textColor)) {
            attributes[.shadow] = shadow
        }

        return attributes
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
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.typingAttributes = parent.typingAttributes()
        }
    }
}

struct TextStyleOption: View {
    let style: StoryEditingView.TextStyle
    let isSelected: Bool
    let onTap: () -> Void

    var stylePreview: String {
        switch style {
        case .modern: return "Aa"
        case .classic: return "Aa"
        case .poster: return "AA"
        case .editorial: return "Aa"
        case .rounded: return "Aa"
        case .signature: return "Aa"
        case .marker: return "Aa"
        case .neon: return "AA"
        case .typewriter: return "Aa"
        case .handwritten: return "Aa"
        case .bold: return "Aa"
        case .chalk: return "Aa"
        }
    }

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

struct FontSizeSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let progress = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
            let knobY = (1 - progress) * (height - 18)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .offset(y: knobY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(gesture.location.y, 9), height - 9)
                        let inverseProgress = 1 - ((clampedY - 9) / max(height - 18, 1))
                        value = range.lowerBound + (inverseProgress * (range.upperBound - range.lowerBound))
                    }
            )
        }
        .frame(width: 18, height: 176)
    }
}

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(color == .white ? Color.gray : Color.white, lineWidth: 1.2)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

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
