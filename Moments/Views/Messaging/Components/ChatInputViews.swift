import SwiftUI

struct GlassmorphicInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    @Binding var isRecordingVoice: Bool
    let recordingTime: TimeInterval
    let onSend: () -> Void
    let onCamera: () -> Void
    let onMedia: () -> Void
    let onStartVoiceRecording: () -> Void
    let onStopVoiceRecording: (Bool) -> Void
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if !isRecordingVoice {
                HStack(alignment: .center, spacing: 8) {
                    // Cámara — alineada al centro
                    Button(action: {
                        onCamera()
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(
                                        colorScheme == .dark ?
                                        Color.white.opacity(0.12) :
                                        Color.black.opacity(0.06)
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // TextField crece hacia arriba, alineado al centro
                    TextField(LocalizedStringKey("chat.input.placeholder"), text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(adaptiveColors.primary)
                        .accentColor(adaptiveColors.primary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.leading, 2)
                        .padding(.vertical, 10)
                        .onChange(of: text) { _, newValue in
                            isTyping = !newValue.isEmpty
                        }

                    if text.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: {
                                onMedia()
                            }) {
                                Image(systemName: "photo")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }

                            Button(action: {
                                onStartVoiceRecording()
                            }) {
                                Image(systemName: "mic")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
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

            // Botón enviar — alineado al centro
            if !text.isEmpty && !isRecordingVoice {
                Button(action: {
                    onSend()
                }) {
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
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.recordingIndicator)

                LiveWaveformView(color: adaptiveColors.primary)
                    .frame(width: 100, height: 25)

                Spacer()

                Text(formattedTime)
                    .font(.custom("Poppins-Medium", size: 14))
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
