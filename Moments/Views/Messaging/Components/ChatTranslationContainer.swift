import SwiftUI

/// The stored message stays original; only this bubble's presentation is translated.
/// The button sits beside the chrome; it is not part of the extracted bubble.
struct ChatTranslationContainer<Content: View>: View {
    let text: String
    let isOutgoing: Bool
    @ViewBuilder let content: (String) -> Content
    @State private var eligible = false
    @State private var translation: String?
    @State private var showTranslation = false
    @State private var requested = false
    @State private var failed = false

    private var target: String { Bundle.main.preferredLocalizations.first ?? "en" }
    private var displayedText: String {
        showTranslation ? (translation ?? text) : text
    }
    private var label: LocalizedStringKey {
        if requested { return "caption.translating" }
        if failed { return "caption.translationRetry" }
        return showTranslation ? "caption.showOriginal" : "chat.translateMessage"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            content(displayedText)
            if eligible && !isOutgoing {
                translateButton
            }
        }
        .task(id: "\(target)\u{0}\(text)") {
            eligible = !isOutgoing && ChatTranslationService.needsTranslation(text, target: target)
        }
        .task(id: requested) {
            guard requested else { return }
            failed = false
            defer { requested = false }
            do {
                let result = try await ChatTranslationService.shared.translate(text, target: target)
                try Task.checkCancellation()
                translation = result
                showTranslation = true
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private var translateButton: some View {
        Button {
            if translation != nil {
                showTranslation.toggle()
            } else {
                requested = true
            }
        } label: {
            Group {
                if requested {
                    ProgressView().controlSize(.mini)
                } else {
                    Image("ChatTranslateIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(failed ? Color.red : (showTranslation ? Color.accentColor : Color.secondary))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(Text(label))
        .disabled(requested)
        .fixedSize()
    }
}
