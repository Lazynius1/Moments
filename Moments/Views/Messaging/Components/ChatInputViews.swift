import AVFoundation
import Lottie
import SwiftUI
import UIKit

private struct ChatRichComposerTextView: UIViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    let onFocusChange: (Bool) -> Void
    let fontSize: CGFloat
    let primaryColor: UIColor
    let secondaryColor: UIColor
    let accentColor: UIColor
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerTextView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: fontSize)
        textView.textColor = primaryColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.tintColor = accentColor
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.syncText(from: text, into: textView)
        return textView
    }

    func updateUIView(_ textView: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        textView.tintColor = accentColor

        if textView.text != text, textView.markedTextRange == nil {
            context.coordinator.syncText(from: text, into: textView)
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ComposerTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = UIFont.systemFont(ofSize: fontSize).lineHeight
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let height = min(max(lineHeight, measured), lineHeight * 6)
        uiView.isScrollEnabled = measured > lineHeight * 6
        return CGSize(width: width, height: ceil(height))
    }

    final class ComposerTextView: UITextView {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatRichComposerTextView
        var isApplyingMarkup = false
        var lastFocusRequest = 0

        init(parent: ChatRichComposerTextView) {
            self.parent = parent
        }

        func syncText(from rawText: String, into textView: UITextView) {
            let selection = textView.selectedRange
            isApplyingMarkup = true
            textView.text = rawText
            if textView.markedTextRange == nil {
                applyMarkup(to: textView, rawText: rawText)
            }
            restoreSelection(selection, in: textView, textLength: (rawText as NSString).length)
            isApplyingMarkup = false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingMarkup else { return }
            let raw = textView.text ?? ""
            if parent.text != raw {
                parent.text = raw
                parent.onTextChange(raw)
            }
            guard textView.markedTextRange == nil else { return }
            isApplyingMarkup = true
            applyMarkup(to: textView, rawText: raw)
            isApplyingMarkup = false
            textView.invalidateIntrinsicContentSize()
        }

        private func restoreSelection(_ selection: NSRange, in textView: UITextView, textLength: Int) {
            let location = min(max(0, selection.location), textLength)
            let length = min(max(0, selection.length), textLength - location)
            textView.selectedRange = NSRange(location: location, length: length)
        }

        func applyMarkup(to textView: UITextView, rawText: String) {
            let fullRange = NSRange(location: 0, length: (rawText as NSString).length)
            let baseFont = UIFont.systemFont(ofSize: parent.fontSize)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: parent.primaryColor
            ]
            let selection = textView.selectedRange
            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)

            let delimiterAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: parent.secondaryColor.withAlphaComponent(0.48)
            ]

            func applyDelimited(
                pattern: String,
                prefixLength: Int,
                suffixLength: Int? = nil,
                contentAttributes: [NSAttributedString.Key: Any]
            ) {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                regex.enumerateMatches(in: rawText, range: fullRange) { match, _, _ in
                    guard let match else { return }
                    let suffix = suffixLength ?? prefixLength
                    let contentRange = NSRange(
                        location: match.range.location + prefixLength,
                        length: match.range.length - prefixLength - suffix
                    )
                    guard contentRange.length > 0 else { return }
                    storage.addAttributes(contentAttributes, range: contentRange)
                    storage.addAttributes(
                        delimiterAttributes,
                        range: NSRange(location: match.range.location, length: prefixLength)
                    )
                    storage.addAttributes(
                        delimiterAttributes,
                        range: NSRange(location: NSMaxRange(contentRange), length: suffix)
                    )
                }
            }

            applyDelimited(
                pattern: #"\*\*([^*]+)\*\*"#,
                prefixLength: 2,
                contentAttributes: [.font: UIFont.boldSystemFont(ofSize: parent.fontSize)]
            )
            applyDelimited(
                pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#,
                prefixLength: 1,
                contentAttributes: [.font: UIFont.italicSystemFont(ofSize: parent.fontSize)]
            )
            applyDelimited(
                pattern: #"~~([^~]+)~~"#,
                prefixLength: 2,
                contentAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
            )
            applyDelimited(
                pattern: #"`([^`]+)`"#,
                prefixLength: 1,
                contentAttributes: [.font: UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)]
            )
            applyDelimited(
                pattern: #"\|\|([^|]+)\|\|"#,
                prefixLength: 2,
                contentAttributes: [
                    .backgroundColor: parent.accentColor.withAlphaComponent(0.16),
                    .font: UIFont.systemFont(ofSize: parent.fontSize, weight: .medium)
                ]
            )

            if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s]+"#, options: [.caseInsensitive]) {
                urlRegex.enumerateMatches(in: rawText, range: fullRange) { match, _, _ in
                    guard let range = match?.range else { return }
                    storage.addAttributes([
                        .foregroundColor: parent.accentColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], range: range)
                }
            }
            if let mentionRegex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])@[\p{L}\p{N}._]+"#) {
                mentionRegex.enumerateMatches(in: rawText, range: fullRange) { match, _, _ in
                    guard let range = match?.range else { return }
                    storage.addAttributes([
                        .foregroundColor: parent.accentColor,
                        .font: UIFont.systemFont(ofSize: parent.fontSize, weight: .semibold)
                    ], range: range)
                }
            }
            if let quoteRegex = try? NSRegularExpression(pattern: #"^> ?.*$"#, options: [.anchorsMatchLines]) {
                quoteRegex.enumerateMatches(in: rawText, range: fullRange) { match, _, _ in
                    guard let range = match?.range, range.length > 0 else { return }
                    storage.addAttributes([
                        .foregroundColor: parent.secondaryColor,
                        .font: UIFont.italicSystemFont(ofSize: parent.fontSize)
                    ], range: range)
                    let raw = rawText as NSString
                    let markerLength = raw.substring(with: range).hasPrefix("> ") ? 2 : 1
                    storage.addAttributes([
                        .foregroundColor: parent.accentColor,
                        .font: UIFont.boldSystemFont(ofSize: parent.fontSize)
                    ], range: NSRange(location: range.location, length: markerLength))
                }
            }

            storage.endEditing()
            textView.typingAttributes = baseAttributes
            restoreSelection(selection, in: textView, textLength: fullRange.length)
        }
    }
}

struct GlassmorphicInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    @Binding var isRecordingVoice: Bool
    @Binding var isVoiceRecordingLocked: Bool
    @Binding var activeAttachmentSheet: ChatAttachmentSheetKind?
    var isVanishModeActive: Bool = false
    var allowsAttachments: Bool = true
    var allowsVoiceRecording: Bool = true
    let recordingTime: TimeInterval
    let recordingInteractionId: UUID?
    let voiceRecordingDraft: VoiceRecordingDraft?
    let isPreparingVoiceRecordingPreview: Bool
    let replyingTo: EnhancedMessage?
    let editingMessage: EnhancedMessage?
    let otherParticipantName: String
    @ObservedObject var voiceGestureState: VoiceRecordingGestureState
    var isKeyboardVisible: Bool = false
    var isTextFieldFocused: FocusState<Bool>.Binding
    @State private var composerFocusRequest = 0
    let onCancelReply: () -> Void
    let onCancelEdit: () -> Void
    let onSend: () -> Void
    let onStartVoiceRecording: (UUID, Bool) -> Void
    let onFinishVoiceRecording: (UUID, VoiceRecordingFinishAction) -> Void
    let onVoiceRecordingTrimChanged: (Range<TimeInterval>) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isMenuOpen: Bool {
        activeAttachmentSheet == .menu
    }

    private var inputPlaceholder: LocalizedStringKey {
        isVanishModeActive ? "chat.input.vanish.placeholder" : "chat.input.placeholder"
    }

    private var inputFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var unifiedComposerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    private var usesUnifiedComposerSurface: Bool {
        guard !isVanishModeActive else { return false }
        return isKeyboardVisible
            || !text.isEmpty
            || isRecordingVoice
            || voiceRecordingDraft != nil
            || isPreparingVoiceRecordingPreview
            || voiceGestureState.preserveKeyboardElevation
            || (separatesCancelTrashCircle && returnsToUnifiedComposerAfterTrash)
    }

    /// Destino real del compositor cuando termina la secuencia de borrado.
    /// Con el teclado abajo vuelve al + standalone; con teclado/foco conserva la cápsula fusionada.
    private var returnsToUnifiedComposerAfterTrash: Bool {
        isKeyboardVisible
            || !text.isEmpty
            || voiceGestureState.preserveKeyboardElevation
    }

    /// Desplazamiento del centro del círculo de papelera al centro del botón +.
    private var trashToPlusMorphOffset: CGFloat {
        guard separatesCancelTrashCircle, returnsToUnifiedComposerAfterTrash else { return 0 }
        // La cápsula recupera el hueco del control separado; el centro final del +
        // solo queda desplazado por su padding interior.
        return 4
    }

    private var showsLeadingPlusButton: Bool {
        !isRecordingVoice
            && editingMessage == nil
            && allowsAttachments
            && !voiceGestureState.playDeleteAnimation
            && !voiceGestureState.isTrashMorphingToPlus
    }

    private var showsComposerTextInput: Bool {
        voiceRecordingDraft == nil && !isPreparingVoiceRecordingPreview
    }

    private var hasComposerContext: Bool {
        replyingTo != nil || editingMessage != nil
    }

    private var vanishStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.22)
    }

    var body: some View {
        // Mantener GlassEffectContainer estable durante el DragGesture del mic.
        if #available(iOS 26.0, *) {
            if separatesCancelTrashCircle {
                // Lottie contiene una UIView. Dentro de GlassEffectContainer, el compositor
                // nativo puede colocarla detrás de las superficies glass coordinadas.
                inputRow
            } else {
                GlassEffectContainer(spacing: usesUnifiedComposerSurface ? 0 : (shouldCoordinateComposerGlass ? 10 : 0)) {
                    inputRow
                }
            }
        } else {
            inputRow
        }
    }

    private var shouldCoordinateComposerGlass: Bool {
        replyingTo == nil
            && editingMessage == nil
            && !isRecordingVoice
            && voiceRecordingDraft == nil
            && !isPreparingVoiceRecordingPreview
    }

    private var separatesCancelTrashCircle: Bool {
        voiceGestureState.playDeleteAnimation || voiceGestureState.isTrashMorphingToPlus
    }

    /// La papelera del borrador pausado también vive fuera de la cápsula central.
    private var separatesLeadingControl: Bool {
        voiceRecordingDraft != nil
            || isPreparingVoiceRecordingPreview
            || separatesCancelTrashCircle
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: separatesLeadingControl ? 10 : (usesUnifiedComposerSurface ? 0 : 10)) {
            if separatesLeadingControl {
                leadingControl(usesStandaloneGlass: true)
                    .zIndex(2)
            }

            VStack(spacing: 0) {
                if usesUnifiedComposerSurface && hasComposerContext {
                    ChatComposerContextPanel(
                        replyingTo: replyingTo,
                        editingMessage: editingMessage,
                        otherParticipantName: otherParticipantName,
                        onCancelReply: onCancelReply,
                        onCancelEdit: onCancelEdit
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))

                    composerContextDivider
                }

                HStack(alignment: .bottom, spacing: usesUnifiedComposerSurface ? 0 : 10) {
                    if !separatesLeadingControl {
                        leadingControl(usesStandaloneGlass: !usesUnifiedComposerSurface)
                            .zIndex(2)
                    }
                    composerSurface(
                        usesStandaloneGlass: !usesUnifiedComposerSurface,
                        showsContextPanel: !usesUnifiedComposerSurface
                    )
                    .zIndex(1)
                    trailingControl(usesStandaloneGlass: !usesUnifiedComposerSurface)
                        .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity)
            // Reserva la geometría de la cápsula expandida también en reposo. Así el primer
            // toque no obliga al compositor y al teclado a resolver dos alturas distintas.
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .momentsChromeGlass(
                in: unifiedComposerShape,
                interactive: false,
                isEnabled: usesUnifiedComposerSurface,
                style: .native
            )
            .overlay {
                if usesUnifiedComposerSurface {
                    unifiedComposerShape
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVanishModeActive), value: isVanishModeActive)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isRecordingVoice), value: isRecordingVoice)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isVoiceRecordingLocked), value: isVoiceRecordingLocked)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: usesUnifiedComposerSurface), value: usesUnifiedComposerSurface)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: voiceGestureState.playDeleteAnimation), value: voiceGestureState.playDeleteAnimation)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: voiceGestureState.isTrashMorphingToPlus), value: voiceGestureState.isTrashMorphingToPlus)
    }

    private func composerSurface(
        usesStandaloneGlass: Bool,
        showsContextPanel: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if showsContextPanel && hasComposerContext {
                ChatComposerContextPanel(
                    replyingTo: replyingTo,
                    editingMessage: editingMessage,
                    otherParticipantName: otherParticipantName,
                    onCancelReply: onCancelReply,
                    onCancelEdit: onCancelEdit
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))

                composerContextDivider
            }

            composerContent
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .momentsChromeGlass(
            in: inputFieldShape,
            interactive: !isVanishModeActive && replyingTo == nil && editingMessage == nil,
            isEnabled: usesStandaloneGlass,
            style: .native
        )
        .background {
            if isVanishModeActive {
                inputFieldShape
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
            }
        }
        .compositingGroup()
        .clipShape(inputFieldShape)
        .overlay {
            inputFieldShape
                .stroke(
                    isVanishModeActive
                        ? vanishStrokeColor
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)),
                    style: isVanishModeActive
                        ? StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                        : StrokeStyle(lineWidth: 0.8)
                )
                .opacity(usesUnifiedComposerSurface ? 0 : 1)
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: replyingTo?.id), value: replyingTo?.id)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: editingMessage?.id), value: editingMessage?.id)
        .animation(.easeInOut(duration: 0.2), value: isRecordingVoice)
        .animation(.easeInOut(duration: 0.2), value: isPreparingVoiceRecordingPreview)
        .animation(.easeInOut(duration: 0.2), value: voiceRecordingDraft != nil)
    }

    private var composerContextDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
            .frame(height: 0.5)
    }

    private var composerContent: some View {
        ZStack(alignment: .leading) {
            // Mantener el TextField montado durante la grabación (alpha 0) para no perder
            // first responder ni bajar el teclado — mismo patrón que el panel nativo de referencia.
            if showsComposerTextInput {
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(inputPlaceholder)
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundStyle(adaptiveColors.secondary.opacity(0.65))
                            .allowsHitTesting(false)
                    }

                    ChatRichComposerTextView(
                        text: $text,
                        focusRequest: composerFocusRequest,
                        onFocusChange: { focused in
                            isTextFieldFocused.wrappedValue = focused
                        },
                        fontSize: legacyPoppinsSize(15),
                        primaryColor: UIColor(adaptiveColors.primary),
                        secondaryColor: UIColor(adaptiveColors.secondary),
                        accentColor: UIColor(adaptiveColors.userAccentColor),
                        onTextChange: { isTyping = !$0.isEmpty }
                    )
                    .frame(maxWidth: .infinity, minHeight: legacyPoppinsSize(15) * 1.25)
                }
                    .opacity(isRecordingVoice ? 0 : 1)
                    .allowsHitTesting(!isRecordingVoice)
                    .accessibilityHidden(isRecordingVoice)
                    .onChange(of: text) { _, newValue in
                        isTyping = !newValue.isEmpty
                    }
            }

            if isRecordingVoice {
                VoiceRecordingHeldStatus(
                    isLocked: isVoiceRecordingLocked,
                    recordingTime: recordingTime,
                    cancelDragOffset: voiceGestureState.cancelDragOffset,
                    cancelProgress: voiceGestureState.cancelProgress,
                    adaptiveColors: adaptiveColors,
                    onCancel: cancelVoiceRecording
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
                VoiceRecordingDraftPreview(
                    draft: voiceRecordingDraft,
                    fallbackDuration: recordingTime,
                    isPreparing: isPreparingVoiceRecordingPreview,
                    adaptiveColors: adaptiveColors,
                    onTrimChanged: onVoiceRecordingTrimChanged
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .onChange(of: voiceGestureState.preserveKeyboardElevation) { _, preserve in
            if preserve {
                composerFocusRequest += 1
            }
        }
        .onChange(of: isRecordingVoice) { _, recording in
            if recording, voiceGestureState.preserveKeyboardElevation {
                composerFocusRequest += 1
            } else if !recording {
                voiceGestureState.preserveKeyboardElevation = false
            }
        }
        .onChange(of: editingMessage?.id) { _, messageID in
            if messageID != nil {
                composerFocusRequest += 1
            }
        }
    }

    @ViewBuilder
    private func leadingControl(usesStandaloneGlass: Bool) -> some View {
        if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            circularGlassButton(systemName: "trash.fill", tint: .red, action: cancelVoiceRecording)
                .accessibilityLabel(Text("common.cancel"))
                .transition(.opacity.combined(with: .scale(scale: 0.78)))
        } else if voiceGestureState.playDeleteAnimation || voiceGestureState.isTrashMorphingToPlus {
            VoiceRecordingTrashIndicator(
                morphProgress: voiceGestureState.trashMorphProgress,
                morphOffsetX: trashToPlusMorphOffset,
                onLottieFinished: {
                    voiceGestureState.startTrashMorphToPlus {
                        voiceGestureState.trashAnimationCompletionHandler?()
                        voiceGestureState.trashAnimationCompletionHandler = nil
                    }
                }
            )
            .fixedSize()
            .id("voice-recording-trash-indicator")
            .transition(.opacity.combined(with: .scale(scale: 0.78)))
        } else if showsLeadingPlusButton {
            ChatAttachmentPlusButton(
                isMenuOpen: isMenuOpen,
                usesStandaloneGlass: usesStandaloneGlass,
                action: toggleAttachmentMenu
            )
                .transition(.scale(scale: 0.001).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func trailingControl(usesStandaloneGlass: Bool) -> some View {
        if isVoiceRecordingLocked {
            VoiceRecordingLockedSendButton(action: sendCurrentContent)
        } else if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            circularSendButton
                .disabled(isPreparingVoiceRecordingPreview)
                .opacity(isPreparingVoiceRecordingPreview ? 0.45 : 1)
        } else if editingMessage != nil {
            circularApplyButton
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        } else if !text.isEmpty {
            circularSendButton
        } else if allowsAttachments && allowsVoiceRecording {
            VoiceRecordingGestureButton(
                tint: adaptiveColors.mediaIconColor,
                isRecording: isRecordingVoice,
                activeInteractionId: recordingInteractionId,
                isLocked: $isVoiceRecordingLocked,
                gestureState: voiceGestureState,
                glassInteractive: !isVanishModeActive,
                usesStandaloneGlass: usesStandaloneGlass,
                onStart: onStartVoiceRecording,
                onFinish: onFinishVoiceRecording,
                onPressBegan: handleVoiceRecordingPressBegan
            )
            .frame(width: 44, height: 44)
        }
    }

    private var circularSendButton: some View {
        Button(action: sendCurrentContent) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(adaptiveColors.userAccentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("notification.action.send"))
    }

    private var circularApplyButton: some View {
        Button(action: sendCurrentContent) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(adaptiveColors.userAccentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("chat.editing.title"))
    }

    private func circularGlassButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
                .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
        }
        .buttonStyle(.plain)
        .frame(width: 52, height: 52)
        .contentShape(Circle())
    }

    private func toggleAttachmentMenu() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            activeAttachmentSheet = isMenuOpen ? nil : .menu
        }
    }

    private func sendCurrentContent() {
        if let recordingInteractionId, voiceRecordingDraft != nil || isRecordingVoice {
            onFinishVoiceRecording(recordingInteractionId, .send)
        } else {
            onSend()
        }
    }

    private func focusTextInputIfNeeded() {
        guard !isRecordingVoice,
              voiceRecordingDraft == nil,
              !isPreparingVoiceRecordingPreview else { return }
        composerFocusRequest += 1
    }

    private func cancelVoiceRecording() {
        guard let recordingInteractionId else { return }
        if voiceRecordingDraft != nil || isPreparingVoiceRecordingPreview {
            voiceGestureState.trashAnimationCompletionHandler = nil
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.press) {
                voiceGestureState.playDeleteAnimation = true
            }
            // Dejar que GlassEffectContainer procese primero la sustitución del botón.
            // Vaciar el borrador en el mismo frame provoca actualizaciones glass duplicadas.
            DispatchQueue.main.async {
                onFinishVoiceRecording(recordingInteractionId, .cancel)
            }
            return
        }
        onFinishVoiceRecording(recordingInteractionId, .cancel)
    }

    private func handleVoiceRecordingPressBegan() {
        guard isTextFieldFocused.wrappedValue || isKeyboardVisible else { return }
        voiceGestureState.preserveKeyboardElevation = true
        composerFocusRequest += 1
    }
}

enum VoiceRecordingFloatingControlMode: Equatable {
    case locking(progress: CGFloat)
    case pause
    case preparing
    case resume
}

struct VoiceRecordingFloatingControlHost: View {
    let isRecording: Bool
    let isLocked: Bool
    let isPreparing: Bool
    let hasDraft: Bool
    let hasActiveInteraction: Bool
    @ObservedObject var gestureState: VoiceRecordingGestureState
    let primaryTint: Color
    let accentTint: Color
    let onPause: () -> Void
    let onResume: () -> Void

    private var mode: VoiceRecordingFloatingControlMode? {
        if isLocked {
            return .pause
        }
        if isRecording {
            return .locking(progress: gestureState.lockProgress)
        }
        if isPreparing, hasActiveInteraction {
            return .preparing
        }
        if hasDraft, hasActiveInteraction {
            return .resume
        }
        return nil
    }

    /// Mientras arrastras hacia el lock, el candado viaja con el mismo desplazamiento
    /// que el blob: siempre va por delante y el blob nunca lo adelanta.
    private var rideAlongOffsetY: CGFloat {
        if case .locking = mode {
            return gestureState.followOffset.height
        }
        return 0
    }

    var body: some View {
        Group {
            if let mode {
                VoiceRecordingFloatingControl(
                    mode: mode,
                    primaryTint: primaryTint,
                    accentTint: accentTint,
                    onPause: onPause,
                    onResume: onResume
                )
                .offset(y: rideAlongOffsetY)
                .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .bottom)))
                .frame(width: 44, height: 72, alignment: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode != nil)
    }
}

/// Un único control conserva posición, superficie glass y región táctil durante
/// toda la secuencia de grabación: candado → pausa → micrófono → pausa.
struct VoiceRecordingFloatingControl: View {
    let mode: VoiceRecordingFloatingControlMode
    let primaryTint: Color
    let accentTint: Color
    let onPause: () -> Void
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lockProgress: CGFloat {
        if case let .locking(progress) = mode {
            return min(1, max(0, progress))
        }
        return 1
    }

    private var controlHeight: CGFloat {
        if case .locking = mode {
            return 72 - lockProgress * 28
        }
        return 44
    }

    private var isInteractive: Bool {
        mode == .pause || mode == .resume
    }

    var body: some View {
        Button(action: performAction) {
            ZStack {
                switch mode {
                case .locking:
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(max(0, 0.9 - lockProgress))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .pause:
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .preparing:
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                case .resume:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                }
            }
            .foregroundStyle(mode == .resume ? accentTint : primaryTint)
            .frame(width: 44, height: controlHeight)
            .contentShape(Capsule())
            .momentsChromeGlass(in: Capsule(), interactive: isInteractive, style: .native)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel(accessibilityLabel)
        .animation(
            reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.86),
            value: mode
        )
    }

    private var accessibilityLabel: Text {
        switch mode {
        case .locking:
            return Text("chat.voice.record.locked")
        case .pause:
            return Text("chat.voice.record.pause")
        case .preparing:
            return Text("common.loading")
        case .resume:
            return Text("chat.voice.record.resume")
        }
    }

    private func performAction() {
        switch mode {
        case .pause:
            onPause()
        case .resume:
            onResume()
        case .locking, .preparing:
            break
        }
    }
}

struct VoiceRecordingAuroraCircleSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                surfaceContent
                    .glassEffect(.clear.interactive(), in: Circle())
            } else {
                surfaceContent
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var surfaceContent: some View {
        ZStack {
            AuroraMeshLayer()
                .blur(radius: 10)
                .opacity(innerAuroraOpacity)

            content
        }
        .frame(width: VoiceRecordingBlobMetrics.surface, height: VoiceRecordingBlobMetrics.surface)
    }

    private var innerAuroraOpacity: Double {
        if #available(iOS 26.0, *) {
            return colorScheme == .dark ? 0.5 : 0.42
        }
        return 0.92
    }
}

private struct VoiceRecordingLockedSendButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VoiceRecordingReactiveAura()

                VoiceRecordingAuroraCircleSurface {
                    Image(systemName: "arrow.up")
                        .font(.system(size: VoiceRecordingBlobMetrics.icon + 1, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: VoiceRecordingBlobMetrics.aura, height: VoiceRecordingBlobMetrics.aura)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("notification.action.send"))
    }
}

/// Punto rojo pulsante dentro del input mientras grabas.
private struct VoiceRecordingRecordDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseLow = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .opacity(reduceMotion ? 1 : (pulseLow ? 0.35 : 1))
            .accessibilityHidden(true)
            .onAppear(perform: restartPulse)
            .onChange(of: reduceMotion) { _, _ in restartPulse() }
    }

    private func restartPulse() {
        pulseLow = false
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulseLow = true
        }
    }
}

/// Círculo de vidrio separado (fuera del input): solo papelera al cancelar.
private struct VoiceRecordingTrashIndicator: View {
    var morphProgress: CGFloat = 0
    var morphOffsetX: CGFloat = 0
    var onLottieFinished: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let restingCircleSize: CGFloat = 52
    private let expandedCircleSize: CGFloat = 62
    private let animationCanvasSize: CGFloat = 78
    private let animationContentScale: CGFloat = 1.55
    private let animation: LottieAnimation?
    @State private var didFinishLottie = false
    @State private var isExpanded = false

    init(
        morphProgress: CGFloat = 0,
        morphOffsetX: CGFloat = 0,
        onLottieFinished: (() -> Void)? = nil
    ) {
        self.morphProgress = morphProgress
        self.morphOffsetX = morphOffsetX
        self.onLottieFinished = onLottieFinished
        self.animation = Self.loadBundledAnimation()
    }

    var body: some View {
        Color.clear
            .frame(
                width: isExpanded ? expandedCircleSize : restingCircleSize,
                height: isExpanded ? expandedCircleSize : restingCircleSize
            )
            .momentsChromeGlass(in: Circle(), interactive: false, style: .native)
            // El overlay se compone después del glass nativo para que nunca tape el icono.
            .overlay {
                trashContent
                    .frame(width: animationCanvasSize, height: animationCanvasSize)
                    .scaleEffect(animationContentScale)
                    .allowsHitTesting(false)
            }
            // La geometría del HStack permanece en 44 pt: el crecimiento es puramente visual.
            .frame(width: restingCircleSize, height: restingCircleSize)
            .offset(x: morphOffsetX * morphProgress)
            .scaleEffect(max(0.001, 1 - morphProgress * 0.999))
            .opacity(1 - Double(morphProgress))
            .accessibilityHidden(true)
            .onAppear {
                if reduceMotion {
                    guard !didFinishLottie else { return }
                    didFinishLottie = true
                    onLottieFinished?()
                } else {
                    MotionPolicy.withOptionalAnimation(.spring(response: 0.24, dampingFraction: 0.76)) {
                        isExpanded = true
                    }
                }
            }
    }

    @ViewBuilder
    private var trashContent: some View {
        if reduceMotion {
            Image(systemName: "trash.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.red)
        } else if let animation {
            LottieView(animation: animation)
                .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
                .animationDidFinish { completed in
                    guard completed, !didFinishLottie else { return }
                    didFinishLottie = true
                    onLottieFinished?()
                }
                .configure { animationView in
                    animationView.contentMode = .scaleAspectFit
                    animationView.animationSpeed = 2
                    animationView.backgroundBehavior = .pauseAndRestore
                    animationView.isOpaque = false
                    animationView.backgroundColor = .clear
                }
        } else {
            Image(systemName: "trash.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.red)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard !didFinishLottie else { return }
                        didFinishLottie = true
                        onLottieFinished?()
                    }
                }
        }
    }

    private static func loadBundledAnimation() -> LottieAnimation? {
        VoiceRecordingTrashAnimationLoader.load()
    }
}

private struct VoiceRecordingSlideToCancelHint: View {
    let cancelDragOffset: CGFloat
    let cancelProgress: CGFloat
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bounceOffset: CGFloat = 0

    private var slideOpacity: Double {
        max(0, 1 - Double(cancelProgress) * 1.15)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
            Text("chat.voice.record.slideToCancel")
                .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .offset(x: cancelDragOffset * 0.55 + bounceOffset)
        .opacity(slideOpacity)
        .onAppear(perform: syncBounce)
        .onChange(of: cancelProgress) { _, _ in syncBounce() }
        .onChange(of: reduceMotion) { _, _ in syncBounce() }
    }

    private func syncBounce() {
        if reduceMotion || cancelProgress > 0.2 || slideOpacity < 0.5 {
            bounceOffset = 0
            return
        }
        bounceOffset = 6
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            bounceOffset = -6
        }
    }
}

private struct VoiceRecordingHeldStatus: View {
    let isLocked: Bool
    let recordingTime: TimeInterval
    var cancelDragOffset: CGFloat = 0
    var cancelProgress: CGFloat = 0
    let adaptiveColors: AdaptiveColors
    let onCancel: () -> Void

    private var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 6) {
            if !isLocked {
                VoiceRecordingRecordDot()
            }

            Text(formattedTime)
                .font(.system(size: legacyPoppinsSize(13), weight: .medium, design: .monospaced))
                .foregroundStyle(adaptiveColors.primary)

            Spacer(minLength: 6)

            if isLocked {
                Button("common.cancel", action: onCancel)
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(adaptiveColors.accent)
                    .buttonStyle(.plain)
            } else {
                VoiceRecordingSlideToCancelHint(
                    cancelDragOffset: cancelDragOffset,
                    cancelProgress: cancelProgress,
                    color: adaptiveColors.timestampColor
                )
            }
        }
        .padding(.trailing, 46)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.header, value: isLocked), value: isLocked)
    }
}

private struct VoiceRecordingDraftPreview: View {
    let draft: VoiceRecordingDraft?
    let fallbackDuration: TimeInterval
    let isPreparing: Bool
    let adaptiveColors: AdaptiveColors
    let onTrimChanged: (Range<TimeInterval>) -> Void

    @StateObject private var player = VoiceRecordingDraftPlayer()
    @State private var workingTrimRange: Range<TimeInterval>?
    @State private var trimGestureOrigin: Range<TimeInterval>?

    private var sourceWaveform: [Float] {
        let samples = draft?.waveform ?? []
        return samples.isEmpty ? Array(repeating: 0.22, count: 16) : samples
    }

    private var duration: TimeInterval {
        draft?.duration ?? fallbackDuration
    }

    private var fullDuration: TimeInterval {
        draft?.fullDuration ?? fallbackDuration
    }

    private var trimRange: Range<TimeInterval> {
        workingTrimRange
            ?? draft?.normalizedTrimRange
            ?? 0..<max(fullDuration, 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            playbackControl

            GeometryReader { proxy in
                let sampleCount = max(18, min(64, Int(proxy.size.width / 4.5)))
                let width = max(proxy.size.width, 1)
                let lowerX = width * trimFraction(trimRange.lowerBound)
                let upperX = width * trimFraction(trimRange.upperBound)

                ZStack(alignment: .leading) {
                    VisualWaveformView(
                        levels: ChatVoiceWaveformSamples.resampled(sourceWaveform, count: sampleCount),
                        color: adaptiveColors.timestampColor.opacity(0.45),
                        activeColor: adaptiveColors.primary.opacity(0.82),
                        progress: player.progress,
                        height: 23,
                        barWidth: 2.5,
                        spacing: 2
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                player.seek(to: value.location.x / width)
                            }
                    )

                    adaptiveColors.background.opacity(0.58)
                        .frame(width: lowerX)
                        .allowsHitTesting(false)

                    adaptiveColors.background.opacity(0.58)
                        .frame(width: max(0, width - upperX))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(adaptiveColors.primary.opacity(0.58), lineWidth: 1)
                        .frame(width: max(1, upperX - lowerX), height: 26)
                        .offset(x: lowerX)
                        .allowsHitTesting(false)

                    trimHandle(isLeading: true, x: lowerX, width: width)
                    trimHandle(isLeading: false, x: upperX, width: width)
                }
                .coordinateSpace(.named("voiceTrimWaveform"))
            }
            .frame(height: 26)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .onAppear {
            workingTrimRange = draft?.normalizedTrimRange
            player.load(draft?.recording?.data, trimRange: trimRange)
        }
        .onChange(of: draft?.recording?.data.count) { _, _ in
            workingTrimRange = draft?.normalizedTrimRange
            player.load(draft?.recording?.data, trimRange: trimRange)
        }
        .onChange(of: draft?.normalizedTrimRange) { _, newValue in
            workingTrimRange = newValue
            player.setTrimRange(newValue ?? 0..<max(fullDuration, 0))
        }
        .onDisappear { player.stop() }
    }

    private func trimFraction(_ time: TimeInterval) -> CGFloat {
        guard fullDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, time / fullDuration)))
    }

    private func trimHandle(isLeading: Bool, x: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(adaptiveColors.primary.opacity(0.88))
            .frame(width: 3, height: 26)
            .overlay {
                Color.clear
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
                    .gesture(trimGesture(isLeading: isLeading, width: width))
            }
            .position(x: x, y: 13)
            .accessibilityHidden(true)
    }

    private func trimGesture(isLeading: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("voiceTrimWaveform"))
            .onChanged { value in
                guard fullDuration > 0 else { return }
                if trimGestureOrigin == nil {
                    trimGestureOrigin = trimRange
                    player.pauseForEditing()
                }
                guard let origin = trimGestureOrigin else { return }
                let proposedTime = min(
                    fullDuration,
                    max(0, Double(value.location.x / width) * fullDuration)
                )
                let minimumDuration = min(2, fullDuration)
                let updatedRange: Range<TimeInterval>
                if isLeading {
                    let lowerBound = min(
                        origin.upperBound - minimumDuration,
                        proposedTime
                    )
                    updatedRange = lowerBound..<origin.upperBound
                } else {
                    let upperBound = max(
                        origin.lowerBound + minimumDuration,
                        proposedTime
                    )
                    updatedRange = origin.lowerBound..<upperBound
                }
                workingTrimRange = updatedRange
            }
            .onEnded { _ in
                if let finalRange = workingTrimRange {
                    player.setTrimRange(finalRange)
                    onTrimChanged(finalRange)
                }
                trimGestureOrigin = nil
                HapticManager.shared.selection()
            }
    }

    private var playbackControl: some View {
        Button(action: player.togglePlayback) {
            HStack(spacing: 4) {
                ZStack {
                    if isPreparing || draft?.recording == nil {
                        ProgressView()
                            .controlSize(.mini)
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                }
                .frame(width: 16, height: 18)

                Text(player.displayTime(fallback: duration))
                    .font(.system(size: legacyPoppinsSize(10), weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            .foregroundStyle(adaptiveColors.primary.opacity(0.82))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(adaptiveColors.timestampColor.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreparing || draft?.recording == nil)
        .accessibilityLabel(player.isPlaying ? Text("chat.voice.pause") : Text("chat.voice.play"))
        .animation(.easeInOut(duration: 0.18), value: isPreparing)
        .animation(.easeInOut(duration: 0.18), value: player.isPlaying)
    }
}

private final class VoiceRecordingDraftPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var trimRange: Range<TimeInterval> = 0..<0

    func load(_ data: Data?, trimRange: Range<TimeInterval>) {
        stop()
        self.trimRange = trimRange
        guard let data else { return }
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        normalizeTrimRange()
        resetToTrimStart()
    }

    func setTrimRange(_ range: Range<TimeInterval>) {
        trimRange = range
        normalizeTrimRange()
        guard let audioPlayer else { return }
        if audioPlayer.currentTime < trimRange.lowerBound || audioPlayer.currentTime > trimRange.upperBound {
            resetToTrimStart()
        } else {
            updateProgress()
        }
    }

    func togglePlayback() {
        guard let audioPlayer else { return }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            if audioPlayer.currentTime < trimRange.lowerBound || audioPlayer.currentTime >= trimRange.upperBound {
                resetToTrimStart()
            }
            guard audioPlayer.play() else { return }
            isPlaying = true
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let audioPlayer else { return }
        let clamped = min(1, max(0, fraction))
        let requestedTime = audioPlayer.duration * clamped
        audioPlayer.currentTime = min(trimRange.upperBound, max(trimRange.lowerBound, requestedTime))
        updateProgress()
    }

    func displayTime(fallback: TimeInterval) -> String {
        let currentTime = audioPlayer?.currentTime ?? trimRange.lowerBound
        let elapsed = max(0, currentTime - trimRange.lowerBound)
        let value = elapsed > 0 || isPlaying ? elapsed : fallback
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }

    func pauseForEditing() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        let playerToStop = audioPlayer
        audioPlayer = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        progress = 0
        if let playerToStop {
            DispatchQueue.global(qos: .utility).async {
                playerToStop.stop()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let audioPlayer = self.audioPlayer else { return }
            if audioPlayer.currentTime >= self.trimRange.upperBound {
                audioPlayer.pause()
                self.isPlaying = false
                self.timer?.invalidate()
                self.resetToTrimStart()
                return
            }
            self.updateProgress()
            if !audioPlayer.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        timer?.invalidate()
        resetToTrimStart()
    }

    private func normalizeTrimRange() {
        guard let audioPlayer else { return }
        let lowerBound = min(audioPlayer.duration, max(0, trimRange.lowerBound))
        let upperBound = min(audioPlayer.duration, max(lowerBound, trimRange.upperBound))
        trimRange = lowerBound..<upperBound
    }

    private func resetToTrimStart() {
        audioPlayer?.currentTime = trimRange.lowerBound
        updateProgress()
    }

    private func updateProgress() {
        guard let audioPlayer, audioPlayer.duration > 0 else {
            progress = 0
            return
        }
        progress = audioPlayer.currentTime / audioPlayer.duration
    }
}
