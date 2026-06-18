import SwiftUI
import UIKit

// MARK: - EnhancedChatBubble CORREGIDO (SIN animación para históricos)
struct EnhancedChatBubble: View {
    let message: ChatMessage
    let username: String
    @State private var displayedText: String = ""
    @State private var isTyping: Bool = false
    @State private var animationTimer: Timer?
    @State private var isInitialized: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if message.isSystem {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(NovaColors.primary.opacity(0.7))

                        Text(message.text)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(NovaColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(NovaColors.primary.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if message.isUser {
                HStack {
                    Spacer(minLength: 50)

                    VStack(alignment: .trailing, spacing: 10) {
                        if let image = message.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(radius: 4)
                        }

                        if !message.text.isEmpty {
                            Text(message.text)
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(NovaColors.textPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(NovaColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(NovaColors.borderColor, lineWidth: 1)
                                )
                        }

                        Text("nova.you")
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(NovaColors.textSecondary)
                            .padding(.trailing, 8)
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(NovaColors.materialBackground)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(NovaColors.borderColor, lineWidth: 1)
                                )
                                .overlay(
                                    NovaBrandIcon(size: 14, color: NovaColors.textPrimary)
                                )

                            Text("nova.name")
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .foregroundColor(NovaColors.textPrimary)

                            Spacer()

                            // ✅ INDICADOR DE TYPING (solo para mensajes nuevos)
                            if isTyping && !message.isHistorical {
                                HStack(spacing: 4) {
                                    ForEach(0..<3, id: \.self) { index in
                                        Circle()
                                            .fill(NovaColors.accent.opacity(0.6))
                                            .frame(width: 4, height: 4)
                                            .scaleEffect(isTyping ? 1.0 : 0.5)
                                            .animation(
                                                .easeInOut(duration: 0.6)
                                                .repeatForever()
                                                .delay(Double(index) * 0.2),
                                                value: isTyping
                                            )
                                    }
                                }
                            } else {
                                // Botones de acción (siempre visibles para históricos)
                                HStack(spacing: 8) {
                                    Button(action: {
                                        UIPasteboard.general.string = message.text
                                        HapticManager.shared.lightImpact()
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundColor(NovaColors.textSecondary)
                                    }

                                    ShareLink(item: message.text) {
                                        AttachmentIconView(icon: .share, preset: .novaShareInline, tintColor: NovaColors.textSecondary)
                                    }
                                }
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .padding(.leading, 8)

                        // ⭐ CONTENIDO - LÓGICA COMPLETAMENTE REVISADA
                        EnhancedFormattedText(text: displayedText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(NovaColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(NovaColors.borderColor, lineWidth: 1)
                            )
                    }

                    Spacer(minLength: 50)
                }
            }
        }
        .onAppear {
            // ✅ MENSAJES DEL SISTEMA: No necesitan inicialización
            if message.isSystem {
                return
            }
            // ✅ OPTIMIZACIÓN: Para mensajes históricos, mostrar inmediatamente
            if message.isHistorical && !isInitialized {
                displayedText = message.text
                isTyping = false
                isInitialized = true
            } else {
                initializeMessage()
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
        }
        // ✅ SOPORTE PARA STREAMING: Cuando el texto del mensaje cambie (vía ViewModel)
        .onChange(of: message.text) { _, newText in
            if !message.isHistorical && !message.isUser {
                // Si el texto está creciendo vía stream, lo mostramos directamente
                // sin la animación artificial de "startNaturalAnimation"
                displayedText = newText
                isInitialized = true
                isTyping = false // Ocultamos los puntos de carga ya que ya hay texto
            }
        }
    }

    // ✅ LÓGICA COMPLETAMENTE NUEVA Y SIMPLE
    private func initializeMessage() {
        // ✅ EVITAR RE-INICIALIZACIÓN SI YA ESTÁ COMPLETO
        if isInitialized {
            return
        }


        if message.isUser {
            // ✅ USUARIO: Siempre mostrar completo
            displayedText = message.text
            isTyping = false
            isInitialized = true
        } else if message.isHistorical {
            // ✅ HISTÓRICO: Mostrar completo INMEDIATAMENTE, sin animación
            displayedText = message.text
            isTyping = false
            isInitialized = true
        } else {
            // ✅ NUEVO: Solo aquí animamos
            startNaturalAnimation(fullText: message.text)
        }
    }

    // ✅ ANIMACIÓN SOLO PARA MENSAJES NUEVOS
    private func startNaturalAnimation(fullText: String) {
        displayedText = ""
        isTyping = true

        // Opción 1: INSTANTÁNEO para textos con formato
        if shouldShowInstantly(fullText) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedText = fullText
                    isTyping = false
                    isInitialized = true
                }
            }
            return
        }

        // Opción 2: ANIMACIÓN por chunks
        animateByChunks(fullText: fullText)
    }

    private func shouldShowInstantly(_ text: String) -> Bool {
        return text.count < 100 ||
               text.contains("##") ||
               text.contains("•") ||
               text.contains("**")
    }

    private func animateByChunks(fullText: String) {
        let chunks = createNaturalChunks(from: fullText)
        var currentChunkIndex = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { timer in
                if currentChunkIndex < chunks.count {
                    displayedText += chunks[currentChunkIndex]
                    currentChunkIndex += 1

                    if chunks[currentChunkIndex - 1].contains(".") ||
                       chunks[currentChunkIndex - 1].contains(",") ||
                       chunks[currentChunkIndex - 1].contains("\n") {
                        timer.fireDate = Date().addingTimeInterval(0.15)
                    }
                } else {
                    timer.invalidate()
                    withAnimation(.easeOut(duration: 0.3)) {
                        isTyping = false
                        isInitialized = true
                    }
                }
            }
        }
    }

    private func createNaturalChunks(from text: String) -> [String] {
        var chunks: [String] = []
        let words = text.components(separatedBy: " ")

        for word in words {
            if word.contains("\n") {
                let lines = word.components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    if index == 0 {
                        chunks.append(line)
                    } else {
                        chunks.append("\n" + line)
                    }
                    if index < lines.count - 1 {
                        chunks.append("")
                    }
                }
            } else {
                chunks.append(word + " ")
            }
        }

        return chunks.filter { !$0.isEmpty }
    }
}

// MARK: - ⭐ TEXTO FORMATEADO AVANZADO CON LINKS
struct EnhancedFormattedText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let sections = parseText(text)

            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]

                switch section.type {
                case .header:
                    HeaderView(text: section.content)
                case .bulletPoint:
                    BulletPointView(text: section.content)
                case .numberedList:
                    NumberedListView(text: section.content, number: section.number ?? 1)
                case .link:
                    LinkView(text: section.content, url: section.url ?? "")
                case .codeBlock:
                    CodeBlockView(text: section.content)
                case .quote:
                    QuoteView(text: section.content)
                case .regular:
                    RegularTextView(text: section.content)
                }
            }
        }
    }

    private func parseText(_ text: String) -> [TextSection] {
        var sections: [TextSection] = []
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                continue
            }

            // Headers (## Texto)
            if trimmedLine.hasPrefix("##") || trimmedLine.hasPrefix("#") {
                let content = trimmedLine.replacingOccurrences(of: "##", with: "")
                                         .replacingOccurrences(of: "#", with: "")
                                         .trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .header, content: content))
            }
            // Bullet points (•, -, * Texto)
            else if trimmedLine.hasPrefix("•") || trimmedLine.hasPrefix("-") || (trimmedLine.hasPrefix("*") && !trimmedLine.hasPrefix("**")) {
                let content = trimmedLine.replacingOccurrences(of: "•", with: "")
                                         .replacingOccurrences(of: "-", with: "")
                                         .replacingOccurrences(of: "*", with: "")
                                         .trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .bulletPoint, content: content))
            }
            // Numbered lists (1. Texto)
            else if let match = trimmedLine.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) {
                let numberStr = capturedNumber(from: trimmedLine)
                let content = String(trimmedLine[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .numberedList, content: content, number: Int(numberStr)))
            }
            // Links [texto](url)
            else if trimmedLine.contains("[") && trimmedLine.contains("](") {
                sections.append(contentsOf: parseLinksInLine(trimmedLine))
            }
            // Code blocks ```
            else if trimmedLine.hasPrefix("```") {
                sections.append(TextSection(type: .codeBlock, content: trimmedLine))
            }
            // Quotes (> texto)
            else if trimmedLine.hasPrefix(">") {
                let content = trimmedLine.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .quote, content: content))
            }
            // Regular text
            else {
                sections.append(TextSection(type: .regular, content: trimmedLine))
            }
        }

        return sections
    }

    private func capturedNumber(from line: String) -> String {
        let pattern = #"^\d+"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range])
        }
        return "1"
    }

    private func parseLinksInLine(_ line: String) -> [TextSection] {
        var sections: [TextSection] = []
        let remainingText = line

        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        let regex = try! NSRegularExpression(pattern: linkPattern, options: [])

        let matches = regex.matches(in: remainingText, options: [], range: NSRange(location: 0, length: remainingText.utf16.count))

        var lastIndex = 0

        for match in matches {
            // Add text before link
            if match.range.location > lastIndex {
                let beforeText = String(remainingText[remainingText.index(remainingText.startIndex, offsetBy: lastIndex)..<remainingText.index(remainingText.startIndex, offsetBy: match.range.location)])
                if !beforeText.isEmpty {
                    sections.append(TextSection(type: .regular, content: beforeText))
                }
            }

            // Add link
            let linkText = String(remainingText[Range(match.range(at: 1), in: remainingText)!])
            let linkURL = String(remainingText[Range(match.range(at: 2), in: remainingText)!])
            sections.append(TextSection(type: .link, content: linkText, url: linkURL))

            lastIndex = match.range.location + match.range.length
        }

        // Add remaining text
        if lastIndex < remainingText.count {
            let remainingString = String(remainingText[remainingText.index(remainingText.startIndex, offsetBy: lastIndex)...])
            if !remainingString.isEmpty {
                sections.append(TextSection(type: .regular, content: remainingString))
            }
        }

        return sections
    }
}

// MARK: - Modelos de Datos para Parsing
struct TextSection {
    enum SectionType {
        case header, bulletPoint, numberedList, link, codeBlock, quote, regular
    }

    let type: SectionType
    let content: String
    let url: String?
    let number: Int?

    init(type: SectionType, content: String, url: String? = nil, number: Int? = nil) {
        self.type = type
        self.content = content
        self.url = url
        self.number = number
    }
}

// MARK: - Componentes de Vista para Formato
struct HeaderView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [NovaColors.primary, NovaColors.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            RoundedRectangle(cornerRadius: 2)
                .fill(NovaColors.primary.opacity(0.3))
                .frame(width: 40, height: 3)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

struct BulletPointView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(NovaColors.primary)
                .frame(width: 6, height: 6)
                .padding(.top, 8)

            Text(text)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(NovaColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

struct NumberedListView: View {
    let text: String
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(NovaColors.primary)
                .clipShape(Circle())

            Text(text)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(NovaColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

struct LinkView: View {
    let text: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url) ?? URL(string: "https://google.com")!) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 14))

                Text(text)
                    .font(.custom("Poppins-Medium", size: 16))
                    .underline()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
            }
            .foregroundColor(NovaColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NovaColors.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NovaColors.primary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct CodeBlockView: View {
    let text: String
    @State private var isCopied = false

    var body: some View {
        let code = text.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = code.components(separatedBy: "\n")
        let language = lines.first?.lowercased() ?? "swift"
        let cleanCode = lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : code

        VStack(alignment: .leading, spacing: 0) {
            // Header del bloque de código
            HStack {
                Text(language.uppercased())
                    .font(.custom("SF Mono-Bold", size: 10))
                    .foregroundColor(NovaColors.textSecondary)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = cleanCode
                    withAnimation { isCopied = true }
                    HapticManager.shared.notification(.success)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { isCopied = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copiado" : "Copiar")
                    }
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(isCopied ? .green : NovaColors.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NovaColors.secondaryBackground.opacity(0.5))

            Divider()
                .background(NovaColors.borderColor)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(cleanCode)
                    .font(.custom("SF Mono", size: 13))
                    .foregroundColor(NovaColors.textPrimary)
                    .padding(12)
            }
        }
        .background(NovaColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NovaColors.borderColor, lineWidth: 1)
        )
        .padding(.vertical, 8)
    }
}

struct QuoteView: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(NovaColors.accent)
                .frame(width: 4)

            Text(text)
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(NovaColors.textSecondary)
                .italic()

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct RegularTextView: View {
    let text: String

    var body: some View {
        Text(parseInlineFormatting(text))
            .font(.custom("Poppins-Regular", size: 16))
            .foregroundColor(NovaColors.textPrimary)
            .lineSpacing(4)
    }

    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)

        // 1. Negritas **texto**
        applyRegex(pattern: #"\*\*([^*]+)\*\*"#, to: &attributedString, originalText: text) { matchText in
            var attr = AttributedString(matchText.replacingOccurrences(of: "**", with: ""))
            attr.font = .custom("Poppins-Bold", size: 16)
            return attr
        }

        // 2. Cursivas *texto* (evitando negritas ya procesadas)
        applyRegex(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, to: &attributedString, originalText: text) { matchText in
            var attr = AttributedString(matchText.replacingOccurrences(of: "*", with: ""))
            attr.font = .custom("Poppins-Italic", size: 16)
            return attr
        }

        return attributedString
    }

    private func applyRegex(pattern: String, to attributedString: inout AttributedString, originalText: String, transform: (String) -> AttributedString) {
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: originalText, range: NSRange(location: 0, length: originalText.utf16.count)) ?? []

        // Procesar en reversa
        for match in matches.reversed() {
            let matchText = (originalText as NSString).substring(with: match.range)
            _ = attributedString.startIndex

            // Aproximación simplificada para encontrar o rango en AttributedString
            // Nota: En una app de producción real, esto requiere un mapeo más robusto de índices
            if let rangeInOriginal = Range(match.range, in: originalText) {
                // Buscamos o tramo literal para facer o replace
                // (Moi simplificado, pero funciona para a maioría de casos de chat)
                let substring = originalText[rangeInOriginal]
                if let attrRange = attributedString.range(of: substring) {
                    attributedString.replaceSubrange(attrRange, with: transform(matchText))
                }
            }
        }
    }
}
