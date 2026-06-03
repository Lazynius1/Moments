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
        let content = StoryTextAttributesBuilder.overlayContentSize(for: configuration, maxWidth: maxWidth)
        return CGSize(width: content.width, height: max(140, min(280, content.height + 24)))
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
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
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

        let signature = editorSignature(configuration: configuration, motion: motion, maxWidth: maxWidth)
        effectView.apply(configuration: configuration, maxWidth: maxWidth)
        StoryTextMotionEngine.apply(to: effectView, motion: motion, replayToken: replayToken)

        let contentSize = StoryTextAttributesBuilder.overlayContentSize(for: configuration, maxWidth: maxWidth)
        let resolvedHeight = max(140, min(280, contentSize.height + 24))
        let resolvedFrame = CGRect(origin: .zero, size: CGSize(width: contentSize.width, height: resolvedHeight))
        effectView.frame = resolvedFrame
        textView.frame = resolvedFrame

        textView.tintColor = UIColor(configuration.textColor)
        textView.textAlignment = configuration.uiTextAlignment

        if signature != appliedSignature {
            appliedSignature = signature
            let clearAttributes = Self.clearTypingAttributes(for: configuration)
            textView.typingAttributes = clearAttributes
            if textView.text != configuration.text {
                textView.attributedText = Self.clearAttributedString(for: configuration)
            }
        } else {
            textView.typingAttributes = Self.clearTypingAttributes(for: configuration)
        }

        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    private func editorSignature(
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
            configuration.text,
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
        effectView.apply(configuration: latestConfiguration, maxWidth: latestMaxWidth)
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
        // typingAttributes refreshed on next apply from SwiftUI
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
    private let glowLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(plateLayer)
        addSubview(glowLabel)
        addSubview(textLabel)
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

    func apply(configuration: StoryTextRenderConfiguration, maxWidth: CGFloat) {
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
        let textFrame = CGRect(origin: .zero, size: size)

        textLabel.frame = textFrame
        glowLabel.frame = textFrame
        textLabel.preferredMaxLayoutWidth = maxWidth
        glowLabel.preferredMaxLayoutWidth = maxWidth

        plateLayer.isHidden = true
        glowLabel.isHidden = true
        resetLabelLayers()

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
        bounds = textFrame
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

    private func applySparkle(
        configuration: StoryTextRenderConfiguration,
        attributed: NSAttributedString,
        alignment: NSTextAlignment
    ) {
        let uiColor = UIColor(configuration.textColor)
        textLabel.attributedText = attributed
        textLabel.textAlignment = alignment
        textLabel.layer.shadowColor = uiColor.cgColor
        textLabel.layer.shadowRadius = 10
        textLabel.layer.shadowOpacity = 0.9
        textLabel.layer.shadowOffset = .zero

        glowLabel.isHidden = false
        glowLabel.attributedText = attributed
        glowLabel.textAlignment = alignment
        glowLabel.textColor = uiColor.withAlphaComponent(0.35)
        glowLabel.layer.shadowColor = UIColor.white.cgColor
        glowLabel.layer.shadowRadius = 16
        glowLabel.layer.shadowOpacity = 0.75
        glowLabel.layer.shadowOffset = .zero
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
        textLabel.layer.shadowRadius = 14
        textLabel.layer.shadowOpacity = 0.85
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
        plateLayer.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.88).cgColor
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
        textLabel.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        textLabel.layer.shouldRasterize = true
        textLabel.layer.rasterizationScale = 0.25 * UIScreen.main.scale
    }

    private func applyBoxedPlate(configuration: StoryTextRenderConfiguration, textFrame: CGRect) {
        guard let fill = StoryTextAttributesBuilder.backgroundUIColor(
            fill: configuration.textBackgroundFill,
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
