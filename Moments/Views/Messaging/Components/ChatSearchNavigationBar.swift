import SwiftUI

/// Barra de búsqueda a ancho completo (equivalente a `ChatSearchNavigationContentNode` en Telegram-iOS).
struct ChatSearchNavigationBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let adaptiveColors: AdaptiveColors
    var onClear: () -> Void
    var onClose: () -> Void
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            ChatInThreadSearchField(
                text: $text,
                focused: focused,
                adaptiveColors: adaptiveColors,
                onClear: onClear,
                onSubmit: onSubmit
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey("common.close")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(adaptiveColors.chatBackground[0])
    }
}
