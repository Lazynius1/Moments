import SwiftUI
import UIKit

struct StoryTextOverlayLabel: UIViewRepresentable {
    let configuration: StoryTextRenderConfiguration
    var maxWidth: CGFloat = UIScreen.main.bounds.width - 80

    func makeUIView(context: Context) -> StoryTextOverlayContainerView {
        StoryTextOverlayContainerView()
    }

    func updateUIView(_ view: StoryTextOverlayContainerView, context: Context) {
        view.apply(configuration: configuration, maxWidth: maxWidth)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StoryTextOverlayContainerView, context: Context) -> CGSize? {
        StoryTextAttributesBuilder.overlayContentSize(for: configuration, maxWidth: maxWidth)
    }
}

// MARK: - Editor input (efectos inline + teclado)

struct StoryTextEditorInputRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let configuration: StoryTextRenderConfiguration
    let motion: StoryEditingView.TextMotion
    let maxWidth: CGFloat
    let replayToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> StoryTextEditorInputContainerView {
        let view = StoryTextEditorInputContainerView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: StoryTextEditorInputContainerView, context: Context) {
        context.coordinator.parent = self
        view.apply(
            configuration: configuration,
            maxWidth: maxWidth,
            motion: motion,
            replayToken: replayToken,
            isFocused: isFocused
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StoryTextEditorInputContainerView, context: Context) -> CGSize? {
        let content = StoryTextAttributesBuilder.measuredSize(for: configuration, maxWidth: maxWidth)
        return CGSize(width: max(80, content.width), height: max(140, min(280, content.height + 24)))
    }

    final class Coordinator: NSObject, StoryTextEditorInputContainerDelegate {
        var parent: StoryTextEditorInputRepresentable

        init(parent: StoryTextEditorInputRepresentable) {
            self.parent = parent
        }

        func editorInputDidChangeText(_ newText: String) {
            parent.text = newText
        }

        func editorInputDidFocusChange(_ focused: Bool) {
            if parent.isFocused != focused {
                parent.isFocused = focused
            }
        }
    }
}

protocol StoryTextEditorInputContainerDelegate: AnyObject {
    func editorInputDidChangeText(_ newText: String)
    func editorInputDidFocusChange(_ focused: Bool)
}

final class StoryTextEditorInputContainerView: UIView, UITextViewDelegate {
    weak var delegate: StoryTextEditorInputContainerDelegate?

    private let effectView = StoryTextOverlayContainerView()
    private let textView = UITextView()
    private var appliedSignature: String = ""
    private var latestConfiguration = StoryTextRenderConfiguration(
        text: "",
        style: .modern,
        visualEffect: .none,
        textColor: .white,
        textAlignment: .center,
        textBackgroundFill: .none,
        fontSize: 30,
        textStroke: .none
    )
    private var latestMaxWidth: CGFloat = 280
    private var latestMotion: StoryEditingView.TextMotion = .none
    private var latestReplayToken: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(effectView)
        addSubview(textView)
        textView.delegate = self
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.keyboardAppearance = .dark
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        configuration: StoryTextRenderConfiguration,
        maxWidth: CGFloat,
        motion: StoryEditingView.TextMotion,
        replayToken: Int,
        isFocused: Bool
    ) {
        latestConfiguration = configuration
        latestMaxWidth = maxWidth
        latestMotion = motion
        latestReplayToken = replayToken

        let contentSize = StoryTextAttributesBuilder.measuredSize(for: configuration, maxWidth: maxWidth)
        let resolvedHeight = max(140, min(280, contentSize.height + 24))
        let resolvedFrame = CGRect(
            origin: .zero,
            size: CGSize(width: max(80, contentSize.width), height: resolvedHeight)
        )
        effectView.frame = resolvedFrame
        textView.frame = resolvedFrame

        effectView.apply(configuration: configuration, maxWidth: maxWidth, containerSize: resolvedFrame.size)
        StoryTextMotionEngine.apply(to: effectView, motion: motion, replayToken: replayToken)

        let caretColor: UIColor
        switch configuration.textBackgroundFill {
        case .none, .inverted:
            caretColor = UIColor(configuration.textColor)
        case .solid, .semiTransparent:
            caretColor = StoryTextAttributesBuilder.contrastUIColor(for: configuration.textColor)
        }
        textView.tintColor = caretColor
        textView.textAlignment = configuration.uiTextAlignment

        let stylingSignature = editorStylingSignature(configuration: configuration, motion: motion, maxWidth: maxWidth)
        let textDidChange = textView.text != configuration.displayText
        let styleDidChange = stylingSignature != appliedSignature

        if textDidChange || styleDidChange {
            appliedSignature = stylingSignature

            let selectedRange = textView.selectedRange
            textView.attributedText = Self.clearAttributedString(for: configuration)

            let safeLocation = min(selectedRange.location, textView.attributedText.length)
            let remaining = textView.attributedText.length - safeLocation
            textView.selectedRange = NSRange(location: safeLocation, length: min(selectedRange.length, remaining))

            textView.typingAttributes = Self.clearTypingAttributes(for: configuration)
        } else {
            textView.typingAttributes = Self.clearTypingAttributes(for: configuration)
        }

        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    private func editorStylingSignature(
        configuration: StoryTextRenderConfiguration,
        motion: StoryEditingView.TextMotion,
        maxWidth: CGFloat
    ) -> String {
        [
            configuration.style.rawValue,
            configuration.visualEffect.rawValue,
            configuration.textStroke.rawValue,
            "\(configuration.textColor)",
            "\(configuration.textAlignment)",
            "\(configuration.textBackgroundFill)",
            "\(configuration.fontSize)",
            "\(configuration.forcesAllCaps)",
            motion.rawValue,
            "\(maxWidth)"
        ].joined(separator: "|")
    }

    private static func clearTypingAttributes(for configuration: StoryTextRenderConfiguration) -> [NSAttributedString.Key: Any] {
        var typingConfig = configuration
        typingConfig.appliesDisplayTransform = false
        var attributes = StoryTextAttributesBuilder.typingAttributes(for: typingConfig)
        attributes[.foregroundColor] = UIColor.clear
        return attributes
    }

    private static func clearAttributedString(for configuration: StoryTextRenderConfiguration) -> NSAttributedString {
        var typingConfig = configuration
        typingConfig.appliesDisplayTransform = false
        let mutable = NSMutableAttributedString(
            attributedString: StoryTextAttributesBuilder.attributedString(for: typingConfig)
        )
        mutable.addAttribute(
            .foregroundColor,
            value: UIColor.clear,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    func textViewDidChange(_ textView: UITextView) {
        latestConfiguration.text = textView.text
        delegate?.editorInputDidChangeText(textView.text)

        let contentSize = StoryTextAttributesBuilder.measuredSize(for: latestConfiguration, maxWidth: latestMaxWidth)
        let resolvedHeight = max(140, min(280, contentSize.height + 24))
        let resolvedFrame = CGRect(
            origin: .zero,
            size: CGSize(width: max(80, contentSize.width), height: resolvedHeight)
        )
        effectView.frame = resolvedFrame
        textView.frame = resolvedFrame

        effectView.apply(configuration: latestConfiguration, maxWidth: latestMaxWidth, containerSize: resolvedFrame.size)
        StoryTextMotionEngine.apply(to: effectView, motion: latestMotion, replayToken: latestReplayToken)
        textView.typingAttributes = Self.clearTypingAttributes(for: latestConfiguration)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.editorInputDidFocusChange(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        delegate?.editorInputDidFocusChange(false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.typingAttributes = Self.clearTypingAttributes(for: latestConfiguration)
    }
}

struct StoryTextOverlayContainerRepresentable: UIViewRepresentable {
    let configuration: StoryTextRenderConfiguration
    let motion: StoryEditingView.TextMotion
    let maxWidth: CGFloat
    let replayToken: Int

    func makeUIView(context: Context) -> StoryTextOverlayContainerView {
        StoryTextOverlayContainerView()
    }

    func updateUIView(_ view: StoryTextOverlayContainerView, context: Context) {
        view.apply(configuration: configuration, maxWidth: maxWidth)
        StoryTextMotionEngine.apply(to: view, motion: motion, replayToken: replayToken)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StoryTextOverlayContainerView, context: Context) -> CGSize? {
        StoryTextAttributesBuilder.overlayContentSize(for: configuration, maxWidth: maxWidth)
    }
}

// MARK: - Overlay container (editor + viewer)

final class StoryTextOverlayContainerView: UIView {
    private let plateLayer = CALayer()
    private let sparkleLayer = CALayer()
    private let glowLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(plateLayer)
        layer.addSublayer(sparkleLayer)
        addSubview(glowLabel)
        addSubview(textLabel)
        sparkleLayer.isHidden = true
        glowLabel.numberOfLines = 0
        glowLabel.backgroundColor = .clear
        glowLabel.isUserInteractionEnabled = false
        textLabel.numberOfLines = 0
        textLabel.backgroundColor = .clear
        textLabel.isUserInteractionEnabled = false
        glowLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(configuration: StoryTextRenderConfiguration, maxWidth: CGFloat, containerSize: CGSize? = nil) {
        let treatment = configuration.visualTreatment
        let baseAttributes = StoryTextAttributesBuilder.coreAttributes(for: configuration)
        let attributed = NSAttributedString(
            string: configuration.displayText,
            attributes: baseAttributes
        )

        let size = StoryTextAttributesBuilder.measure(
            attributed: attributed,
            maxWidth: maxWidth
        )
        let alignment = configuration.uiTextAlignment

        let finalSize = containerSize ?? size
        let xOrigin: CGFloat
        switch alignment {
        case .left:
            xOrigin = 0
        case .right:
            xOrigin = max(0, finalSize.width - size.width)
        case .center:
            xOrigin = max(0, (finalSize.width - size.width) / 2)
        default:
            xOrigin = 0
        }

        let textFrame = CGRect(x: xOrigin, y: 0, width: size.width, height: size.height)

        textLabel.frame = textFrame
        glowLabel.frame = textFrame
        textLabel.preferredMaxLayoutWidth = maxWidth
        glowLabel.preferredMaxLayoutWidth = maxWidth

        plateLayer.isHidden = true
        sparkleLayer.isHidden = true
        glowLabel.isHidden = true
        resetLabelLayers()
        resetSparkles()

        switch treatment {
        case .sparklePulse:
            applySparkle(configuration: configuration, attributed: attributed, alignment: alignment)
        case .neonGlow:
            applyNeon(configuration: configuration, attributed: attributed, alignment: alignment)
        case .softGlow:
            applySoftGlow(configuration: configuration, attributed: attributed, alignment: alignment)
        case .markerHighlight:
            applyMarker(configuration: configuration, textFrame: textFrame)
            textLabel.attributedText = attributed
        case .chalkDust:
            applyChalk(configuration: configuration, attributed: attributed, alignment: alignment)
        case .pixelBitmap:
            applyPixel(configuration: configuration, attributed: attributed, alignment: alignment)
        case .boxedCaption:
            applyBoxedPlate(configuration: configuration, textFrame: textFrame)
            textLabel.attributedText = attributed
        case .memeStrong:
            applyMeme(configuration: configuration, attributed: attributed, alignment: alignment)
        case .plain:
            textLabel.attributedText = attributed
        }

        textLabel.textAlignment = alignment

        if containerSize == nil {
            bounds = textFrame
        } else {
            bounds = CGRect(origin: .zero, size: finalSize)
        }
    }

    private func resetLabelLayers() {
        [textLabel, glowLabel].forEach { label in
            label.layer.shadowOpacity = 0
            label.layer.shadowRadius = 0
            label.layer.shadowOffset = .zero
            label.layer.shadowColor = nil
            label.transform = .identity
            label.layer.shouldRasterize = false
        }
    }

    private func resetSparkles() {
        sparkleLayer.sublayers?.forEach { $0.removeAllAnimations() }
        sparkleLayer.sublayers = nil
    }

    private func applySparkle(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        let uiColor = UIColor(configuration.textColor)
        textLabel.attributedText = attributed
        textLabel.textAlignment = alignment
        textLabel.layer.shadowColor = uiColor.cgColor
        textLabel.layer.shadowRadius = 8
        textLabel.layer.shadowOpacity = 0.68
        textLabel.layer.shadowOffset = .zero
        textLabel.layer.shouldRasterize = true
        textLabel.layer.rasterizationScale = UIScreen.main.scale

        applySparkleAccents(
            around: textLabel.frame,
            tintColor: uiColor
        )
    }

    private func applySparkleAccents(around textFrame: CGRect, tintColor: UIColor) {
        let sparkleFrame = textFrame.insetBy(dx: -18, dy: -14)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sparkleLayer.isHidden = false
        sparkleLayer.frame = sparkleFrame
        sparkleLayer.opacity = 1
        CATransaction.commit()

        resetSparkles()

        let sparkleSpecs: [(CGPoint, CGFloat, CFTimeInterval, UIColor)] = [
            (CGPoint(x: 0.14, y: 0.22), 10, 0.00, UIColor.white.withAlphaComponent(0.95)),
            (CGPoint(x: 0.82, y: 0.16), 8, 0.22, UIColor.white.withAlphaComponent(0.92)),
            (CGPoint(x: 0.91, y: 0.60), 9, 0.44, tintColor.withAlphaComponent(0.88)),
            (CGPoint(x: 0.22, y: 0.84), 7, 0.16, UIColor.white.withAlphaComponent(0.84)),
            (CGPoint(x: 0.66, y: 0.90), 6, 0.36, tintColor.withAlphaComponent(0.72))
        ]

        for (normalizedPoint, size, delay, color) in sparkleSpecs {
            let sparkle = CAShapeLayer()
            sparkle.path = sparklePath(size: size).cgPath
            sparkle.fillColor = color.cgColor
            sparkle.shadowColor = UIColor.white.cgColor
            sparkle.shadowOpacity = 0.9
            sparkle.shadowRadius = 4
            sparkle.shadowOffset = .zero
            sparkle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            sparkle.position = CGPoint(
                x: sparkleFrame.width * normalizedPoint.x,
                y: sparkleFrame.height * normalizedPoint.y
            )
            sparkle.opacity = 0.25

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.18, 1.0, 0.32, 0.88, 0.2]
            opacity.keyTimes = [0.0, 0.25, 0.5, 0.72, 1.0]

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.72, 1.12, 0.86, 1.02, 0.76]
            scale.keyTimes = [0.0, 0.25, 0.5, 0.72, 1.0]

            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            group.duration = 1.9
            group.beginTime = CACurrentMediaTime() + delay
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false

            sparkle.add(group, forKey: "moments.sparkle.twinkle")
            sparkleLayer.addSublayer(sparkle)
        }
    }

    private func sparklePath(size: CGFloat) -> UIBezierPath {
        let center = CGPoint(x: size / 2, y: size / 2)
        let outerRadius = size / 2
        let innerRadius = outerRadius * 0.34
        let path = UIBezierPath()

        for index in 0..<8 {
            let angle = (CGFloat(index) * (.pi / 4)) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.close()
        return path
    }

    private func applySoftGlow(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        let uiColor = UIColor(configuration.textColor)
        textLabel.attributedText = attributed
        textLabel.textAlignment = alignment
        textLabel.layer.shadowColor = uiColor.cgColor
        textLabel.layer.shadowRadius = 18
        textLabel.layer.shadowOpacity = 0.92
        textLabel.layer.shadowOffset = .zero
    }

    private func applyNeon(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        let uiColor = UIColor(configuration.textColor)
        glowLabel.isHidden = false
        glowLabel.attributedText = attributed
        glowLabel.textAlignment = alignment
        glowLabel.textColor = uiColor.withAlphaComponent(0.55)
        glowLabel.layer.shadowColor = uiColor.cgColor
        glowLabel.layer.shadowRadius = 22
        glowLabel.layer.shadowOpacity = 1
        glowLabel.layer.shadowOffset = .zero

        textLabel.attributedText = attributed
        textLabel.textAlignment = alignment
        textLabel.textColor = .white
        textLabel.layer.shadowColor = uiColor.cgColor
        textLabel.layer.shadowRadius = 8
        textLabel.layer.shadowOpacity = 0.95
        textLabel.layer.shadowOffset = .zero
    }

    private func applyMarker(configuration: StoryTextRenderConfiguration, textFrame: CGRect) {
        let padH: CGFloat = 14
        let padV: CGFloat = 8
        plateLayer.isHidden = false
        plateLayer.backgroundColor = UIColor(configuration.textColor).withAlphaComponent(0.35).cgColor
        plateLayer.cornerRadius = 6
        plateLayer.frame = textFrame.insetBy(dx: -padH, dy: -padV)
        plateLayer.zPosition = -1
    }

    private func applyChalk(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 0
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        mutable.addAttribute(.shadow, value: shadow, range: NSRange(location: 0, length: mutable.length))

        textLabel.attributedText = mutable
        textLabel.textAlignment = alignment
        textLabel.layer.shadowColor = UIColor.white.withAlphaComponent(0.25).cgColor
        textLabel.layer.shadowRadius = 1
        textLabel.layer.shadowOffset = CGSize(width: -1, height: -1)
        textLabel.layer.shadowOpacity = 1
    }

    private func applyPixel(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        textLabel.attributedText = attributed
        textLabel.textAlignment = alignment
        textLabel.layer.magnificationFilter = .nearest
        textLabel.layer.minificationFilter = .nearest

        // Enlarge bounds to provide padding for low-res rasterization and prevent letter clipping
        let padX: CGFloat = 12
        let padY: CGFloat = 6
        textLabel.bounds = textLabel.bounds.insetBy(dx: -padX, dy: -padY)

        textLabel.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        textLabel.layer.shouldRasterize = true
        textLabel.layer.rasterizationScale = 0.35 * UIScreen.main.scale
    }

    private func applyBoxedPlate(configuration: StoryTextRenderConfiguration, textFrame: CGRect) {
        guard let fill = StoryTextAttributesBuilder.backgroundUIColor(
            fill: configuration.textBackgroundFill,
            selectedColor: configuration.textColor,
            effect: configuration.visualEffect,
            style: configuration.style
        ) else { return }

        plateLayer.isHidden = false
        plateLayer.backgroundColor = fill.cgColor
        plateLayer.cornerRadius = 8
        plateLayer.frame = textFrame.insetBy(dx: -12, dy: -8)
        plateLayer.zPosition = -1
    }

    private func applyMeme(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        var attrs = StoryTextAttributesBuilder.coreAttributes(for: configuration)
        attrs[.strokeColor] = UIColor.black
        attrs[.strokeWidth] = -5.0
        attrs[.foregroundColor] = UIColor.white
        let memeText = NSAttributedString(string: configuration.displayText, attributes: attrs)
        textLabel.attributedText = memeText
        textLabel.textAlignment = alignment
    }
}

struct StoryTextAnimationModifier: ViewModifier {
    let animation: StoryEditingView.TextMotion
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: offsetY)
            .rotationEffect(rotation)
            .opacity(opacity)
            .onAppear { restartAnimation() }
            .onChange(of: animation) { _, _ in restartAnimation() }
    }

    private func restartAnimation() {
        phase = false
        guard animation != .none else { return }
        withAnimation(animationCurve.repeatForever(autoreverses: true)) {
            phase = true
        }
    }

    private var animationCurve: Animation {
        switch animation {
        case .pop: return .spring(response: 0.42, dampingFraction: 0.52)
        case .bounce: return .easeInOut(duration: 0.52)
        case .wave: return .easeInOut(duration: 0.95)
        case .typewriter: return .easeInOut(duration: 0.75)
        case .reveal: return .easeInOut(duration: 1.0)
        case .none: return .default
        }
    }

    private var scale: CGFloat {
        switch animation {
        case .pop: return phase ? 1.06 : 0.94
        case .bounce: return phase ? 1.02 : 0.98
        case .typewriter: return phase ? 1.02 : 1.0
        default: return 1.0
        }
    }

    private var offsetY: CGFloat {
        switch animation {
        case .bounce: return phase ? -10 : 4
        case .wave: return phase ? -3 : 3
        default: return 0
        }
    }

    private var rotation: Angle {
        animation == .wave ? (phase ? .degrees(2.5) : .degrees(-2.5)) : .zero
    }

    private var opacity: Double {
        switch animation {
        case .typewriter: return phase ? 1.0 : 0.72
        case .reveal: return phase ? 1.0 : 0.35
        default: return 1.0
        }
    }
}
