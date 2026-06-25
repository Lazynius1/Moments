import SwiftUI

struct GlassmorphicInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    @Binding var isRecordingVoice: Bool
    @Binding var activeAttachmentSheet: ChatAttachmentSheetKind?
    let recordingTime: TimeInterval
    let onSend: () -> Void
    let onStartVoiceRecording: () -> Void
    let onStopVoiceRecording: (Bool) -> Void
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isMenuOpen: Bool {
        activeAttachmentSheet == .menu
    }

    private func toggleAttachmentMenu() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            activeAttachmentSheet = isMenuOpen ? nil : .menu
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if !isRecordingVoice {
                ChatAttachmentPlusButton(isMenuOpen: isMenuOpen, action: toggleAttachmentMenu)

                HStack(alignment: .center, spacing: 8) {
                    TextField(LocalizedStringKey("chat.input.placeholder"), text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundColor(adaptiveColors.primary)
                        .accentColor(adaptiveColors.primary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.leading, 14)
                        .padding(.trailing, text.isEmpty ? 4 : 12)
                        .padding(.vertical, 10)
                        .onChange(of: text) { _, newValue in
                            isTyping = !newValue.isEmpty
                        }

                    if text.isEmpty {
                        Button(action: onStartVoiceRecording) {
                            AttachmentIconView(icon: .voice, preset: .chatVoiceInput, tintColor: adaptiveColors.mediaIconColor)
                        }
                        .padding(.trailing, 12)
                        .accessibilityLabel(Text("chat.input.voice.accessibility"))
                    }
                }
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            colorScheme == .dark ?
                            Color.white.opacity(0.08) :
                            Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                )
            } else {
                VoiceRecordingBar(
                    recordingTime: recordingTime,
                    adaptiveColors: adaptiveColors,
                    onCancel: {
                        onStopVoiceRecording(false)
                    },
                    onSend: {
                        onStopVoiceRecording(true)
                    }
                )
            }

            if !text.isEmpty && !isRecordingVoice {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(adaptiveColors.userAccentColor)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct VoiceRecordingBar: View {
    let recordingTime: TimeInterval
    let adaptiveColors: AdaptiveColors
    let onCancel: () -> Void
    let onSend: () -> Void

    private var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: recordingTime
                    )

                Text("chat.recording")
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(adaptiveColors.recordingIndicator)

                LiveWaveformView(color: adaptiveColors.primary)
                    .frame(width: 100, height: 25)

                Spacer()

                Text(formattedTime)
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassmorphicChat()
            .clipShape(Capsule())

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(adaptiveColors.accent)
                    .clipShape(Circle())
            }
        }
    }
}
