import SwiftUI
import Firebase
import FirebaseVertexAI
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Colores modernos
struct ModernGeminiColors {
    static let primary = Color(hex: "00A896")
    static let secondary = Color(hex: "6B73FF")
    static let accent = Color(hex: "9B59B6")
    
    // Colores adaptativos
    static var background: Color {
        Color(UIColor.systemBackground)
    }
    
    static var secondaryBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }
    
    static var cardBackground: Color {
        Color(UIColor.systemBackground).opacity(0.8)
    }
    
    static var materialBackground: Color {
        Color(UIColor.systemBackground).opacity(0.95)
    }
    
    static var textPrimary: Color {
        Color(UIColor.label)
    }
    
    static var textSecondary: Color {
        Color(UIColor.secondaryLabel)
    }
    
    static var textTertiary: Color {
        Color(UIColor.tertiaryLabel)
    }
    
    static var borderColor: Color {
        Color(UIColor.separator)
    }
    
    static var shadowColor: Color {
        Color(UIColor.label).opacity(0.1)
    }
}

// MARK: - Vista Principal
struct GeminiView: View {
    @StateObject private var viewModel = GeminiViewModel()
    @State private var showSuggestedOptions = true
    @State private var scrollOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var showConversationHistory = false
    @State private var isKeyboardVisible = false
    @State private var showLanguageSheet = false
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack {
                // Fondo moderno con gradiente
                ModernGeminiBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    EnhancedGeminiHeader(
                        viewModel: viewModel,
                        showConversationHistory: $showConversationHistory,
                        showSuggestedOptions: $showSuggestedOptions
                    )
                    
                    ZStack {
                        if viewModel.userData != nil && !viewModel.isLoading && viewModel.conversationHistory.isEmpty && showSuggestedOptions {
                            ModernWelcomeSection(
                                viewModel: viewModel,
                                showSuggestedOptions: $showSuggestedOptions
                            )
                            .transition(.opacity.combined(with: .scale))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                ScrollViewReader { proxy in
                                    // ✅ FUNCIÓN HELPER PARA SCROLL SUAVE
                                    let scrollToBottom = {
                                        if let lastMessage = viewModel.conversationHistory.last {
                                            withAnimation(.easeInOut(duration: 0.4)) {
                                                proxy.scrollTo("\(lastMessage.id)_\(lastMessage.isHistorical ? "historical" : "new")", anchor: .bottom)
                                            }
                                        }
                                    }
                                    LazyVStack(spacing: 16, pinnedViews: []) {
                                        ForEach(viewModel.conversationHistory) { message in
                                            EnhancedChatBubble(
                                                message: message,
                                                username: viewModel.userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
                                            )
                                            .id("\(message.id)_\(message.isHistorical ? "historical" : "new")")
                                        }
                                        
                                        if viewModel.isLoading {
                                            ModernLoadingAnimation()
                                                .padding(.vertical, 20)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    // ⭐ PADDING DINÁMICO PARA INPUT BAR Y TECLADO
                                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 100 : 80)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .preference(key: GeminiScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                                        }
                                    )
                                    // ✅ CAMBIO 1: Scroll cuando CAMBIAN los mensajes - MEJORADO
                                    .onChange(of: viewModel.conversationHistory) { _ in
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            scrollToBottom()
                                        }
                                    }
                                    // ✅ CAMBIO 2: Scroll cuando aparece el teclado - MEJORADO
                                    .onChange(of: keyboardHeight) { height in
                                        if height > 0 {
                                            // ✅ DELAY MÁS LARGO PARA SINCRONIZAR CON EL TECLADO
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                scrollToBottom()
                                            }
                                        }
                                    }
                                    // ✅ NUEVO: Scroll cuando el teclado está visible y hay foco
                                    .onChange(of: isKeyboardVisible) { visible in
                                        if visible && !viewModel.conversationHistory.isEmpty {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                scrollToBottom()
                                            }
                                        }
                                    }
                                    // ✅ CAMBIO 3: Scroll inicial cuando se cargan mensajes históricos - MEJORADO
                                    .onAppear {
                                        if !viewModel.conversationHistory.isEmpty {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                scrollToBottom()
                                            }
                                        }
                                    }
                                }
                            }
                            .coordinateSpace(name: "scroll")
                            .onPreferenceChange(GeminiScrollOffsetPreferenceKey.self) { value in
                                scrollOffset = value
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // ⭐ INPUT BAR SIEMPRE VISIBLE
                    // ✅ OPTIMIZACIÓN: Solo animar el offset del teclado
                    EnhancedInputBar(
                        viewModel: viewModel,
                        showSuggestedOptions: $showSuggestedOptions,
                        onFocusChange: { focused in
                            // ✅ SCROLL CUANDO EL TEXTOFIELD OBTIENE FOCUS
                            if focused && !viewModel.conversationHistory.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    if let lastMessage = viewModel.conversationHistory.last {
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            // El scroll se maneja en el onChange del keyboardHeight
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .background(.ultraThinMaterial.opacity(0.98))
                    .clipShape(RoundedRectangle(cornerRadius: keyboardHeight > 0 ? 0 : 16))
                    .shadow(color: ModernGeminiColors.shadowColor, radius: keyboardHeight > 0 ? 0 : 10, x: 0, y: keyboardHeight > 0 ? 0 : -5)
                    // ⭐ POSICIONAMIENTO FIJO EN LA PARTE INFERIOR
                    .offset(y: -keyboardHeight + safeAreaBottom - 80) // Resta altura del TabBar (80px)
                    .animation(.easeInOut(duration: 0.3), value: keyboardHeight) // Solo este animation aquí
                }
                // ✅ Eliminado el animation global en VStack para no interferir con el teclado
                // .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
                
                // Overlay de historial de conversaciones
                if showConversationHistory {
                    ConversationHistoryOverlay(
                        viewModel: viewModel,
                        showConversationHistory: $showConversationHistory,
                        showSuggestedOptions: $showSuggestedOptions
                    )
                }
            }
            .onTapGesture {
                hideKeyboard()
                // ✅ No cambiar showSuggestedOptions aquí. La barra de input la gestiona ahora.
                // showSuggestedOptions = false
            }
            // ⭐ LISTENERS DE TECLADO MEJORADOS
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    // ✅ Ajustar keyboardHeight directamente, la animación se maneja en el .offset
                    keyboardHeight = keyboardFrame.height
                    isKeyboardVisible = true
                    
                    // ✅ SCROLL AUTOMÁTICO CUANDO APARECE EL TECLADO
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMessage = viewModel.conversationHistory.last {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                // Usar ScrollViewReader para hacer scroll
                                // Esto se maneja en el onChange del keyboardHeight
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                // ✅ Ajustar keyboardHeight directamente
                keyboardHeight = 0
                isKeyboardVisible = false
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.fetchUserData()
            if NovaLanguageService.getPreferredLanguage() == nil {
                showLanguageSheet = true
            }
        }
        // ✅ Mantener solo las animaciones de overlay aquí
        .animation(.easeInOut(duration: 0.3), value: showConversationHistory)
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSelectionSheet { selected in
                NovaLanguageService.setPreferredLanguage(selected)
                showLanguageSheet = false
            }
            .presentationDetents([.fraction(0.35)])
        }
    }
}


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
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text(message.text)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    ModernGeminiColors.primary,
                                    ModernGeminiColors.secondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: ModernGeminiColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Text("nova.you")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                        .padding(.trailing, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [ModernGeminiColors.accent, ModernGeminiColors.primary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "sparkles")
                                .foregroundColor(.white)
                                .font(.system(size: 12, weight: .bold))
                        }
                        
                        Text("nova.name")
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(ModernGeminiColors.accent)
                        
                        Spacer()
                        
                        // ✅ INDICADOR DE TYPING (solo para mensajes nuevos)
                        if isTyping && !message.isHistorical {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle()
                                        .fill(ModernGeminiColors.accent.opacity(0.6))
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
                                    NovaHapticFeedback.light()
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                        .foregroundColor(ModernGeminiColors.textSecondary)
                                }
                                
                                ShareLink(item: message.text) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 12))
                                        .foregroundColor(ModernGeminiColors.textSecondary)
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
                        .background(ModernGeminiColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            ModernGeminiColors.borderColor,
                                            ModernGeminiColors.accent.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: ModernGeminiColors.shadowColor, radius: 10, x: 0, y: 5)
                }
                
                Spacer(minLength: 50)
            }
        }
        .onAppear {
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

// ✅ HAPTIC FEEDBACK HELPER
struct NovaHapticFeedback {
    static func light() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    static func medium() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
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
            if trimmedLine.hasPrefix("##") {
                let content = trimmedLine.replacingOccurrences(of: "##", with: "").trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .header, content: content))
            }
            // Bullet points (• Texto)
            else if trimmedLine.hasPrefix("•") {
                let content = trimmedLine.replacingOccurrences(of: "•", with: "").trimmingCharacters(in: .whitespaces)
                sections.append(TextSection(type: .bulletPoint, content: content))
            }
            // Numbered lists (1. Texto)
            else if let match = trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let numberStr = String(trimmedLine[match]).replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
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
    
    private func parseLinksInLine(_ line: String) -> [TextSection] {
        var sections: [TextSection] = []
        var remainingText = line
        
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
        HStack {
            Text(text)
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(ModernGeminiColors.primary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct BulletPointView: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(ModernGeminiColors.primary)
                .frame(width: 6, height: 6)
                .padding(.top, 8)
            
            Text(text)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(ModernGeminiColors.textPrimary)
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
                .background(ModernGeminiColors.primary)
                .clipShape(Circle())
            
            Text(text)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(ModernGeminiColors.textPrimary)
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
            .foregroundColor(ModernGeminiColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ModernGeminiColors.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ModernGeminiColors.primary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct CodeBlockView: View {
    let text: String
    
    var body: some View {
        Text(text.replacingOccurrences(of: "```", with: ""))
            .font(.custom("SF Mono", size: 14))
            .foregroundColor(ModernGeminiColors.textPrimary)
            .padding()
            .background(ModernGeminiColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
            )
    }
}

struct QuoteView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(ModernGeminiColors.accent)
                .frame(width: 4)
            
            Text(text)
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(ModernGeminiColors.textSecondary)
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
            .foregroundColor(ModernGeminiColors.textPrimary)
            .lineSpacing(4)
    }
    
    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Bold text **texto**
        let boldPattern = #"\*\*([^*]+)\*\*"#
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = boldRegex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            
            // Procesar matches en orden inverso para evitar problemas de índices
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let boldText = String(text[range]).replacingOccurrences(of: "**", with: "")
                    
                    // Método más simple y compatible
                    let startIndex = attributedString.startIndex
                    let matchStart = attributedString.index(startIndex, offsetByCharacters: match.range.location)
                    let matchEnd = attributedString.index(startIndex, offsetByCharacters: match.range.location + match.range.length)
                    
                    if matchStart < attributedString.endIndex && matchEnd <= attributedString.endIndex {
                        let attributedRange = matchStart..<matchEnd
                        var boldAttributedText = AttributedString(boldText)
                        boldAttributedText.font = .custom("Poppins-Bold", size: 16)
                        
                        attributedString.replaceSubrange(attributedRange, with: boldAttributedText)
                    }
                }
            }
        }
        
        return attributedString
    }
}
// MARK: - Componentes UI Originales
struct ConversationHistoryOverlay: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showConversationHistory: Bool
    @Binding var showSuggestedOptions: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Fondo adaptativo
            Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showConversationHistory = false
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    // Header del historial
                    HStack {
                        Text("nova.recentConversations")
                            .font(.custom("Poppins-Bold", size: 20))
                            .foregroundColor(ModernGeminiColors.textPrimary)
                        
                        Spacer()
                        
                        Button(action: {
                            showConversationHistory = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(ModernGeminiColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(ModernGeminiColors.materialBackground)
                    
                    Divider()
                        .background(ModernGeminiColors.borderColor)
                    
                    // Lista de conversaciones
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.conversationTitles.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 48))
                                        .foregroundColor(ModernGeminiColors.textSecondary)
                                    
                                    Text("nova.noConversations")
                                        .font(.custom("Poppins-Medium", size: 16))
                                        .foregroundColor(ModernGeminiColors.textSecondary)
                                    
                                    Text("nova.startNewConversation")
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(ModernGeminiColors.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.vertical, 40)
                            } else {
                                // Botón para nueva conversación
                                Button(action: {
                                    viewModel.startNewConversation()
                                    showConversationHistory = false
                                    showSuggestedOptions = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(ModernGeminiColors.primary)
                                        
                                        Text("nova.newConversation")
                                            .font(.custom("Poppins-SemiBold", size: 16))
                                            .foregroundColor(ModernGeminiColors.textPrimary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(ModernGeminiColors.textSecondary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(ModernGeminiColors.cardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(ModernGeminiColors.primary.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                
                                // Conversaciones guardadas
                                ForEach(viewModel.conversationTitles.reversed()) { conversation in
                                    ConversationHistoryItem(
                                        conversation: conversation,
                                        viewModel: viewModel,
                                        onSelect: {
                                            Task {
                                                await viewModel.loadConversation(conversation.id)
                                                showConversationHistory = false
                                                showSuggestedOptions = false
                                            }
                                        },
                                        onDelete: {
                                            Task {
                                                await viewModel.deleteConversation(conversation.id)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                }
                .background(ModernGeminiColors.materialBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ConversationHistoryItem: View {
    let conversation: ConversationTitle
    @ObservedObject var viewModel: GeminiViewModel
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            
            Task {
                await viewModel.loadConversation(conversation.id)
                onSelect()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(ModernGeminiColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(conversation.lastUpdated.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                    
                    if conversation.messageCount > 0 {
                        Text("\(conversation.messageCount) \(NSLocalizedString("nova.messages", comment: "Messages count"))")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(ModernGeminiColors.textTertiary)
                    }
                }
                
                Spacer()
                
                Menu {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        Label(NSLocalizedString("nova.actions.delete", comment: "Delete action"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ModernGeminiColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
                    )
            )
        }
        .alert(NSLocalizedString("nova.actions.deleteConversation.title", comment: "Delete conversation alert title"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("nova.actions.cancel", comment: "Cancel action"), role: .cancel) { }
            Button(NSLocalizedString("nova.actions.delete", comment: "Delete action"), role: .destructive, action: onDelete)
        } message: {
                Text("nova.deleteConversation.confirm")
        }
    }
}

// MARK: - Header Mejorado con Memoria
// MARK: - Header Mejorado con Easter Egg CORREGIDO
struct EnhancedGeminiHeader: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showConversationHistory: Bool
    @Binding var showSuggestedOptions: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // ✨ ESTADOS PARA EASTER EGG
    @State private var logoTapCount = 0
    @State private var showDeveloperEasterEgg = false
    @State private var lastTapTime = Date()
    @State private var logoScale: CGFloat = 1.0
    @State private var sparkleAnimation = false
    
    // ✅ OFFSETS PREDEFINIDOS PARA EVITAR NaN
    private let sparkleOffsets: [CGPoint] = [
        CGPoint(x: -10, y: -8),
        CGPoint(x: 12, y: -5),
        CGPoint(x: -8, y: 10),
        CGPoint(x: 15, y: 8),
        CGPoint(x: -12, y: 0),
        CGPoint(x: 8, y: -12)
    ]
    
    var body: some View {
        HStack {
            // Logo/Icono de Nova con Easter Egg
            ZStack {
                // ✅ SPARKLES CORREGIDOS
                if logoTapCount >= 4 {
                    ForEach(0..<6, id: \.self) { index in
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundColor(ModernGeminiColors.accent)
                            .offset(
                                x: sparkleOffsets[safe: index]?.x ?? 0,
                                y: sparkleOffsets[safe: index]?.y ?? 0
                            )
                            .opacity(sparkleAnimation ? 1.0 : 0.0)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1),
                                value: sparkleAnimation
                            )
                    }
                }
                
                Circle()
                    .fill(ModernGeminiColors.materialBackground)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: logoTapCount >= 4 ? [
                                        ModernGeminiColors.primary,
                                        ModernGeminiColors.secondary,
                                        ModernGeminiColors.accent,
                                        ModernGeminiColors.primary
                                    ] : [
                                        ModernGeminiColors.primary,
                                        ModernGeminiColors.secondary
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: logoTapCount >= 4 ? 2.5 : 1.5
                            )
                    )
                    .scaleEffect(logoScale)
                
                Image(systemName: logoTapCount >= 6 ? "sparkles.rectangle.stack.fill" : "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: logoTapCount >= 4 ? [
                                ModernGeminiColors.primary,
                                ModernGeminiColors.secondary,
                                ModernGeminiColors.accent
                            ] : [
                                ModernGeminiColors.primary,
                                ModernGeminiColors.secondary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(logoScale)
            }
            .onTapGesture {
                handleLogoTap()
            }
            .alert("🎉 ¡Easter Egg Desbloqueado!", isPresented: $showDeveloperEasterEgg) {
                Button("🚀 ¡Increíble!") {
                    resetEasterEgg()
                }
                Button(NSLocalizedString("nova.easterEgg.thanksButton", comment: "Thank you Álvaro button")) {
                    resetEasterEgg()
                    triggerDeveloperAppreciation()
                }
            } message: {
                Text(NSLocalizedString("nova.easterEgg.message", comment: "Easter egg message about Álvaro"))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("nova.name")
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    ModernGeminiColors.primary,
                                    ModernGeminiColors.secondary
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("·")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(ModernGeminiColors.textTertiary)
                    Link(NSLocalizedString("nova.poweredBy", comment: "Powered by Google Gemini credit"), destination: URL(string: "https://ai.google.dev/")!)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(ModernGeminiColors.textTertiary)
                    
                    // Indicador sutil de progreso del easter egg
                    if logoTapCount > 0 && logoTapCount < 7 {
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { index in
                                Circle()
                                    .fill(index < logoTapCount ? ModernGeminiColors.accent : ModernGeminiColors.borderColor)
                                    .frame(width: 4, height: 4)
                                    .animation(.spring(response: 0.3), value: logoTapCount)
                            }
                        }
                        .opacity(0.6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Text("nova.personalAssistant")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(ModernGeminiColors.textSecondary)
            }
            
            Spacer()
            
            // Botones de acción
            HStack(spacing: 8) {
                if !viewModel.conversationHistory.isEmpty {
                    Button(action: {
                        viewModel.startNewConversation()
                        showSuggestedOptions = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(ModernGeminiColors.primary)
                            .frame(width: 36, height: 36)
                            .background(ModernGeminiColors.materialBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(ModernGeminiColors.primary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                
                Button(action: {
                    showConversationHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(ModernGeminiColors.materialBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(ModernGeminiColors.materialBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(ModernGeminiColors.borderColor),
            alignment: .bottom
        )
        .onAppear {
            if logoTapCount >= 4 {
                sparkleAnimation = true
            }
        }
    }
    
    // MARK: - 🎯 FUNCIONES DEL EASTER EGG CORREGIDAS
    
    private func handleLogoTap() {
        let now = Date()
        
        // Reset si han pasado más de 3 segundos
        if now.timeIntervalSince(lastTapTime) > 3.0 {
            logoTapCount = 1
        } else {
            logoTapCount += 1
        }
        
        lastTapTime = now
        
        // ✅ ANIMACIÓN VALIDADA
        let targetScale: CGFloat = logoTapCount >= 7 ? 1.0 : 1.2
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            logoScale = targetScale
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                logoScale = 1.0
            }
        }
        
        // ✅ EFECTOS CON LÍMITES VALIDADOS
        switch logoTapCount {
        case 3:
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
        case 4:
            withAnimation(.easeInOut(duration: 0.5)) {
                sparkleAnimation = true
            }
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
        case 6:
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            
        case 7:
            showDeveloperEasterEgg = true
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
            
        default:
            if logoTapCount < 7 {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }
    
    private func resetEasterEgg() {
        withAnimation(.easeOut(duration: 0.5)) {
            logoTapCount = 0
            sparkleAnimation = false
            logoScale = 1.0
        }
    }
    
    private func triggerDeveloperAppreciation() {
        viewModel.inputText = NSLocalizedString("nova.easterEgg.appreciationMessage", comment: "Thank you message for Álvaro")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !viewModel.inputText.isEmpty {
                viewModel.sendMessage()
            }
        }
    }
}

struct ModernGeminiBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Fondo base adaptativo
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "F8F9FA"),
                        Color(hex: "E3F2FD").opacity(0.9),
                        Color(hex: "F1F8E9").opacity(0.8),
                        Color(hex: "F8F9FA")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Efectos de partículas adaptativos
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                ModernGeminiColors.primary.opacity(colorScheme == .dark ? 0.3 : 0.2),
                                ModernGeminiColors.secondary.opacity(colorScheme == .dark ? 0.2 : 0.15),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                    .offset(
                        x: CGFloat.random(in: -200...200),
                        y: CGFloat.random(in: -300...300)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 3...6))
                        .repeatForever(autoreverses: true),
                        value: UUID()
                    )
            }

            // Overlay material adaptativo
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.1 : 0.05)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct ModernWelcomeSection: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool

    var body: some View {
        ZStack {
            ModernGeminiBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    VStack(spacing: 16) {
                        Text("\(NSLocalizedString("nova.hello", comment: "Hello message")) \(viewModel.userData?.username ?? NSLocalizedString("nova.user", comment: "User"))!")
                            .font(.custom("Poppins-Bold", size: 32))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        ModernGeminiColors.primary,
                                        ModernGeminiColors.secondary,
                                        ModernGeminiColors.accent
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .multilineTextAlignment(.center)

                        Text("nova.introduction")
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(ModernGeminiColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 20)

                    if let userData = viewModel.userData {
                        VStack(spacing: 20) {
                            ModernInfoCard(
                                title: NSLocalizedString("nova.welcome.interests.title", comment: "Your interests title"),
                                value: userData.interests.isEmpty ? NSLocalizedString("nova.welcome.interests.empty", comment: "No interests configured") : userData.interests.joined(separator: " • "),
                                icon: "heart.fill"
                            )

                            HStack(spacing: 12) {
                                ModernStatCard(
                                    title: NSLocalizedString("nova.welcome.mutuals.title", comment: "Your mutuals title"),
                                    value: "\(viewModel.mutualConnections.count)",
                                    icon: "person.2.fill"
                                )

                                ModernStatCard(
                                    title: NSLocalizedString("nova.welcome.profileVisits.title", comment: "Profile visits title"),
                                    value: "\(viewModel.profileVisits.count)",
                                    icon: "eye.fill"
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("nova.quickSuggestions")
                                .font(.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(ModernGeminiColors.textPrimary)

                            Spacer()

                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(ModernGeminiColors.accent)
                                .font(.system(size: 16))
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ModernSuggestionCard(
                                title: NSLocalizedString("nova.suggestions.writeHelp.title", comment: "Help me write title"),
                                icon: "pencil.circle.fill",
                                gradient: [ModernGeminiColors.primary, ModernGeminiColors.secondary]
                            ) {
                                viewModel.inputText = NSLocalizedString("nova.suggestions.writeHelp.prompt", comment: "Help me write prompt")
                                viewModel.sendMessage()
                                showSuggestedOptions = false
                            }

                            ModernSuggestionCard(
                                title: NSLocalizedString("nova.suggestions.studyTips.title", comment: "Study tips title"),
                                icon: "book.circle.fill",
                                gradient: [ModernGeminiColors.secondary, ModernGeminiColors.accent]
                            ) {
                                viewModel.inputText = NSLocalizedString("nova.suggestions.studyTips.prompt", comment: "Study tips prompt")
                                viewModel.sendMessage()
                                showSuggestedOptions = false
                            }

                            ModernSuggestionCard(
                                title: NSLocalizedString("nova.suggestions.interests.title", comment: "My interests title"),
                                icon: "heart.circle.fill",
                                gradient: [ModernGeminiColors.accent, ModernGeminiColors.primary]
                            ) {
                                viewModel.inputText = NSLocalizedString("nova.suggestions.interests.prompt", comment: "My interests prompt")
                                viewModel.sendMessage()
                                showSuggestedOptions = false
                            }

                            ModernSuggestionCard(
                                title: NSLocalizedString("nova.suggestions.advice.title", comment: "Give me advice title"),
                                icon: "lightbulb.circle.fill",
                                gradient: [ModernGeminiColors.primary, ModernGeminiColors.accent]
                            ) {
                                viewModel.inputText = NSLocalizedString("nova.suggestions.advice.prompt", comment: "Give me advice prompt")
                                viewModel.sendMessage()
                                showSuggestedOptions = false
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct ModernInfoCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(ModernGeminiColors.primary)
                    .font(.system(size: 20))
                
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                
                Spacer()
            }
            
            Text(value)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(ModernGeminiColors.textSecondary)
                .lineLimit(3)
        }
        .padding(20)
        .background(ModernGeminiColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            ModernGeminiColors.borderColor,
                            ModernGeminiColors.primary.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: ModernGeminiColors.shadowColor, radius: 10, x: 0, y: 5)
    }
}

struct ModernStatCard: View {
    let title: String
    let value: String
    let icon: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(ModernGeminiColors.secondary)
                .font(.system(size: 24))
            
            Text(value)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(ModernGeminiColors.textPrimary)
            
            Text(title)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(ModernGeminiColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(ModernGeminiColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            ModernGeminiColors.borderColor,
                            ModernGeminiColors.secondary.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: ModernGeminiColors.shadowColor, radius: 8, x: 0, y: 4)
    }
}

struct ModernSuggestionCard: View {
    let title: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(ModernGeminiColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.4) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: ModernGeminiColors.shadowColor, radius: 8, x: 0, y: 4)
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

struct ModernLoadingAnimation: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        ModernGeminiColors.primary,
                                        ModernGeminiColors.secondary,
                                        ModernGeminiColors.accent
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 12, height: 12)
                            .scaleEffect(isAnimating ? 1.2 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                                value: isAnimating
                            )
                    }
                }
                
                Text("nova.typing")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(ModernGeminiColors.textSecondary)
                    .opacity(isAnimating ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: isAnimating)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(ModernGeminiColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                ModernGeminiColors.borderColor,
                                ModernGeminiColors.accent.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: ModernGeminiColors.shadowColor, radius: 8, x: 0, y: 4)
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct EnhancedInputBar: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ CALLBACK PARA NOTIFICAR CUANDO EL TEXTOFIELD OBTIENE FOCUS
    var onFocusChange: ((Bool) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // ⭐ SUGERENCIAS MEJORADAS - NO SE OCULTAN CON FOCUS
            if showSuggestedOptions && viewModel.conversationHistory.isEmpty {
                SmartSuggestionChips(viewModel: viewModel, showSuggestedOptions: $showSuggestedOptions)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // ⭐ SEPARADOR CONDICIONAL
            if showSuggestedOptions && viewModel.conversationHistory.isEmpty {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(ModernGeminiColors.borderColor)
            }
            
            HStack(spacing: 12) {
                // ✅ TextField con cambios en el overlay para rendimiento
                TextField(NSLocalizedString("nova.input.placeholder", comment: "Ask Nova something placeholder"), text: $viewModel.inputText, axis: .vertical)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(ModernGeminiColors.cardBackground)
                    .clipShape(Capsule())
                    // ✅ Optimización: Mover la lógica del stroke y el gradiente a una vista separada o usar un enfoque más simple si es posible.
                    // Para este caso, lo dejamos tal cual, pero es un punto a considerar en profiling.
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ModernGeminiColors.borderColor.opacity(isTextFieldFocused ? 0.8 : 0.5),
                                        ModernGeminiColors.primary.opacity(isTextFieldFocused ? 0.5 : 0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isTextFieldFocused ? 1.5 : 1
                            )
                    )
                    .focused($isTextFieldFocused)
                    .onChange(of: isTextFieldFocused) { focused in
                        onFocusChange?(focused)
                    }
                    .onSubmit {
                        if !viewModel.inputText.isEmpty {
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                        }
                    }
                
                HStack(spacing: 8) {
                    // ✅ Ahora solo el botón de enviar, se muestra si hay texto.
                    if !viewModel.inputText.isEmpty { // Si hay texto, mostrar botón de enviar
                        Button(action: {
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                            isTextFieldFocused = false
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            ModernGeminiColors.primary,
                                            ModernGeminiColors.secondary
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: ModernGeminiColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // ⭐ PADDING ADICIONAL PARA SAFE AREA CUANDO HAY TECLADO
            .padding(.bottom, isTextFieldFocused ? 0 : 0)
        }
        // ✅ Animar solo la aparición/desaparición del botón enviar
        .animation(.easeInOut(duration: 0.25), value: viewModel.inputText.isEmpty)
    }
}

// MARK: - Sugerencias Inteligentes Mejoradas
struct SmartSuggestionChips: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    
            let suggestions: [SmartSuggestion] = [
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.viralContent", comment: "How to create viral content"), icon: "flame.fill"),
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.productiveDay", comment: "Organize my productive day"), icon: "clock.fill"),
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.socialProfile", comment: "Improve my social profile"), icon: "person.crop.circle.fill"),
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.wellbeing", comment: "Wellness advice"), icon: "heart.fill"),
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.connectPeople", comment: "Connect with like-minded people"), icon: "person.2.fill"),
            SmartSuggestion(text: NSLocalizedString("nova.smartSuggestions.momentIdeas", comment: "Ideas for my next moment"), icon: "lightbulb.fill")
        ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions, id: \.text) { suggestion in
                    SmartSuggestionChip(suggestion: suggestion) {
                        viewModel.inputText = suggestion.text
                        viewModel.sendMessage()
                        showSuggestedOptions = false
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct SmartSuggestion {
    let text: String
    let icon: String
}

struct SmartSuggestionChip: View {
    let suggestion: SmartSuggestion
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 14))
                    .foregroundColor(ModernGeminiColors.primary)
                
                Text(suggestion.text)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(ModernGeminiColors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(ModernGeminiColors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(ModernGeminiColors.primary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Utilities y Extensions
struct GeminiScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


// MARK: - Mantener el modelo ChatMessage igual
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
    let isHistorical: Bool // ✅ NUEVO: Flag para mensajes históricos

    init(text: String, isUser: Bool, isHistorical: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.timestamp = Date()
        self.isHistorical = isHistorical // ✅ Por defecto es nuevo mensaje
    }

    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.isUser == rhs.isUser &&
               lhs.isHistorical == rhs.isHistorical
    }
}

// MARK: - GeminiViewModel Mejorado
class GeminiViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var responseText = ""
    @Published var isLoading = false
    @Published var conversationHistory: [ChatMessage] = []
    @Published var conversationTitles: [ConversationTitle] = []

    private(set) var userData: AppUser?
    private(set) var recentMoments: [Moment] = []
    private(set) var mutualConnections: [AppUser] = []
    private(set) var usersWithSharedInterests: [AppUser] = []
    private(set) var suggestedUsers: [AppUser] = []
    private(set) var profileVisits: [AppUser] = []
    
    private var currentConversationId: String?
    private var conversationService: ConversationService?
    private let firestoreService = FirestoreService()
    private let vertexAI: VertexAI
    private let model: GenerativeModel
    
    private let memoryService = NovaMemoryService()
    @Published var userMemory: NovaMemory?
    @Published var hasMemoryLoaded = false
    // Detectar idioma del input del usuario (heurística ligera)
    private func detectInputLanguage(_ text: String) -> NovaLanguage? {
        let lower = text.lowercased()
        // Señales de catalán
        let caSignals = ["què", "gràcies", "adéu", "ben", "perquè", "noi", "noia"]
        if caSignals.contains(where: { lower.contains($0) }) || lower.contains("à") || lower.contains("è") || lower.contains("ò") {
            return .ca
        }
        // Señales de inglés
        let enSignals = ["the ", "and ", "what", "how ", "please", "thank you", "you're", "you are"]
        if enSignals.contains(where: { lower.contains($0) }) {
            return .en
        }
        // Señales de español
        let esSignals = ["qué", "como", "cómo", "gracias", "hola", "por favor", "adiós", "porque"]
        if esSignals.contains(where: { lower.contains($0) }) || lower.contains("ñ") || lower.contains("á") || lower.contains("é") || lower.contains("í") || lower.contains("ó") || lower.contains("ú") {
            return .es
        }
        return nil
    }
    
    // ✅ NUEVO: Variables para controlar logs y conexiones
    private var memoryProcessingTimer: Timer?
    private var lastMemoryProcessTime: Date?
    private let minimumMemoryInterval: TimeInterval = 5.0

    init() {
        self.vertexAI = VertexAI.vertexAI()
        
        // ✅ CONFIGURAR MODELO CON CONFIGURACIÓN OPTIMIZADA
        let config = GenerationConfig(
            temperature: 0.7,
            topP: 0.8,
            topK: 40,
            candidateCount: 1,
            maxOutputTokens: 2048,
            stopSequences: [],
            responseMIMEType: "text/plain"
        )
        
        // ✅ CONFIGURAR SAFETY SETTINGS PARA EVITAR BLOQUEOS
        let safetySettings = [
            SafetySetting(harmCategory: .harassment, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .hateSpeech, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .dangerousContent, threshold: .blockMediumAndAbove)
        ]
        
        self.model = vertexAI.generativeModel(
            modelName: "gemini-2.5-flash-lite",
            generationConfig: config,
            safetySettings: safetySettings
        )
        
        Task {
            await MainActor.run {
                self.conversationService = ConversationService()
            }
            await self.loadConversationTitles()
        }
    }

    // MARK: - Funciones originales sin cambios
    func fetchUserData() {
        guard let userId = Auth.auth().currentUser?.uid else {
            LogConfig.log("Error: No se encontró el ID del usuario autenticado", category: "Auth")
            return
        }

        isLoading = true
        firestoreService.fetchUserDataForGemini(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    self?.userData = user
                    LogConfig.log("Datos del usuario obtenidos para Gemini: \(user.username)", category: "Data")
                    self?.fetchRecentMoments(userId: userId)
                    self?.fetchMutualConnections(userId: userId)
                    self?.fetchUsersWithSharedInterests(userId: userId)
                    self?.fetchProfileVisits(userId: userId)
                    self?.fetchSuggestedUsers()
                    // Cargar memoria silenciosamente
                    self?.loadMemoryContextSilently(userId: userId)
                case .failure(let error):
                    LogConfig.log("Error al obtener datos del usuario: \(error.localizedDescription)", category: "Error")
                    self?.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Memoria de Nova
    private func loadMemoryContextSilently(userId: String) {
        memoryService.loadMemory(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let memory):
                    self?.userMemory = memory
                    // 🎯 Log del nombre preferido si existe
                    if let preferredName = memory.preferredName {
                        LogConfig.log("🎭 Nombre preferido detectado: \(preferredName)", category: "Personalization")
                    }
                    LogConfig.log("🧠 Memoria personalizada cargada: \(memory.facts.count) hechos", category: "Memory")
                    // ✅ NUEVO: Marcar que la memoria está lista
                    self?.hasMemoryLoaded = true
                case .failure(_):
                    self?.userMemory = NovaMemory(userId: userId)
                    self?.hasMemoryLoaded = true
                }
            }
        }
    }

    func fetchRecentMoments(userId: String) {
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let moments):
                    self?.recentMoments = Array(moments.prefix(3))
                    LogConfig.log("Momentos recientes obtenidos: \(self?.recentMoments.count ?? 0)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener momentos: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }

    func fetchMutualConnections(userId: String) {
        
        // Obtener following directamente de Firestore
        firestoreService.db.collection("users").document(userId).collection("following")
            .getDocuments { [weak self] followingSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    return
                }
                
                let followingIds = followingSnapshot?.documents.compactMap { doc in
                    doc.data()["userId"] as? String
                } ?? []
                
                
                // Obtener followers
                self.firestoreService.db.collection("users").document(userId).collection("followers")
                    .getDocuments { [weak self] followersSnapshot, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            return
                        }
                        
                        let followerIds = followersSnapshot?.documents.compactMap { doc in
                            doc.data()["userId"] as? String
                        } ?? []
                        
                        
                        // Calcular conexiones mutuas
                        let followingSet = Set(followingIds)
                        let followersSet = Set(followerIds)
                        let mutualIds = Array(followingSet.intersection(followersSet))
                        
                        
                        if mutualIds.isEmpty {
                            DispatchQueue.main.async {
                                self.mutualConnections = []
                                self.objectWillChange.send() // ✅ Forzar actualización de UI
                            }
                            return
                        }
                        
                        // Obtener usuarios mutuos
                        self.firestoreService.fetchUsers(userIds: mutualIds) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let users):
                                    self.mutualConnections = users
                                    self.objectWillChange.send() // ✅ Forzar actualización de UI
                                    LogConfig.log("Conexiones mutuas obtenidas: \(users.count)", category: "Data")
                                case .failure(let error):
                                    LogConfig.log("Error al obtener usuarios mutuos: \(error.localizedDescription)", category: "Error")
                                }
                            }
                        }
                    }
            }
    }

    func fetchUsersWithSharedInterests(userId: String) {
        guard let userData = userData else {
            LogConfig.log("Error: Datos del usuario no disponibles.", category: "Error")
            return
        }

        let interests = userData.interests
        guard !interests.isEmpty else {
            LogConfig.log("No hay intereses para buscar usuarios compartidos", category: "Data")
            return
        }

        firestoreService.fetchUsersWithSharedInterests(interests: interests, excludingUserId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.usersWithSharedInterests = Array(users.prefix(3))
                    LogConfig.log("Usuarios con intereses compartidos obtenidos: \(self?.usersWithSharedInterests.count ?? 0)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener usuarios con intereses compartidos: \(error.localizedDescription)", category: "Error")
                }
                self?.isLoading = false
            }
        }
    }

    func fetchProfileVisits(userId: String) {
        firestoreService.fetchVisits(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let visits):
                    let visitorIds = visits.map { $0.visitorId }
                    
                    if visitorIds.isEmpty {
                        self?.profileVisits = []
                        self?.objectWillChange.send()
                        return
                    }
                    
                    // Obtener usuarios visitantes usando fetchUsersInBatches como ProfileView
                    self?.fetchUsersInBatches(userIds: visitorIds) { users in
                        DispatchQueue.main.async {
                            self?.profileVisits = users
                            self?.objectWillChange.send()
                            LogConfig.log("Visitas al perfil obtenidas: \(users.count)", category: "Data")
                        }
                    }
                case .failure(let error):
                    LogConfig.log("Error al obtener visitas: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }
    
    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            firestoreService.fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                switch result {
                case .success(let users):
                    allUsers.append(contentsOf: users)
                case .failure(_):
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
    }
    
    func fetchSuggestedUsers() {
        firestoreService.fetchSuggestedUsers { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.suggestedUsers = users
                    LogConfig.log("Usuarios sugeridos obtenidos: \(users.count)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener usuarios sugeridos: \(error.localizedDescription)", category: "Error")
                }
            }
        }
    }
    
    // MARK: - Gestión de conversaciones (sin cambios)
    func loadConversationTitles() async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }
        
        let titles = await conversationService.loadConversationTitles(for: userId)
        await MainActor.run {
            self.conversationTitles = titles
        }
    }
    
    func startNewConversation() {
        currentConversationId = nil
        conversationHistory.removeAll()
        memoryProcessingTimer?.invalidate()
        
        if let userId = Auth.auth().currentUser?.uid {
            loadMemoryContextSilently(userId: userId)
            
            // 🎯 AÑADIR ESTE DELAY PEQUEÑO
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Forzar actualización de la UI para reflejar la memoria cargada
                self.objectWillChange.send()
            }
        }
    }
    
    func loadConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }
        
        LogConfig.log("🔄 Cargando conversación: \(conversationId)", category: "Conversation")
        await MainActor.run {
            isLoading = true
        }
        
        let messages = await conversationService.loadConversation(conversationId, for: userId)
        await MainActor.run {
            self.conversationHistory = messages
            self.currentConversationId = conversationId
            self.isLoading = false
            self.objectWillChange.send()
            
            // Recargar contexto silenciosamente
            if let userId = Auth.auth().currentUser?.uid {
                self.loadMemoryContextSilently(userId: userId)
            }
        }
    }
    
    func deleteConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }
        
        let success = await conversationService.deleteConversation(conversationId, for: userId)
        if success {
            await MainActor.run {
                self.conversationTitles.removeAll { $0.id == conversationId }
                if self.currentConversationId == conversationId {
                    self.startNewConversation()
                }
            }
        }
    }
    
    private func saveCurrentConversation() async {
        guard let userId = Auth.auth().currentUser?.uid,
              !conversationHistory.isEmpty,
              let conversationService = conversationService else { return }
        
        if let conversationId = currentConversationId {
            // Actualizar conversación existente
            let success = await conversationService.updateConversation(
                conversationId,
                for: userId,
                messages: conversationHistory
            )
            if success {
                await loadConversationTitles()
            }
        } else {
            // Crear nueva conversación
            let conversationId = await conversationService.saveConversation(
                for: userId,
                messages: conversationHistory
            )
            if let id = conversationId {
                await MainActor.run {
                    self.currentConversationId = id
                }
                await loadConversationTitles()
            }
        }
    }

    // MARK: - ✅ sendMessage() MEJORADO CON MANEJO DE ERRORES
    func sendMessage() {
        // ✅ VALIDACIONES BÁSICAS
        guard !inputText.isEmpty else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Por favor, escribe un mensaje."
            case .en: responseText = "Please, write a message."
            case .ca: responseText = "Si us plau, escriu un missatge."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        guard let userId = Auth.auth().currentUser?.uid, let userData = userData else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Error: No se pudieron cargar los datos del usuario. Por favor, intenta de nuevo."
            case .en: responseText = "Error: Could not load user data. Please try again."
            case .ca: responseText = "Error: No s'han pogut carregar les dades de l'usuari. Si us plau, torna-ho a provar."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }
        
        // ✅ NUEVO: Asegurar que la memoria esté cargada antes de enviar
        guard hasMemoryLoaded else {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            switch lang {
            case .es: responseText = "Cargando tu memoria personalizada... Por favor, espera un momento."
            case .en: responseText = "Loading your personalized memory... Please wait a moment."
            case .ca: responseText = "Carregant la teva memòria personalitzada... Si us plau, espera un moment."
            }
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }

        // 🎯 DETECTAR COMANDOS DE PERSONALIZACIÓN ANTES DE ENVIAR
        if let personalizationCommand = NovaPersona.detectPersonalizationCommand(inputText) {
            handlePersonalizationCommand(personalizationCommand, userId: userId)
            return
        }

        // ✅ PREPARAR MENSAJE DEL USUARIO
        let userMessage = ChatMessage(text: inputText, isUser: true)
        conversationHistory.append(userMessage)
        
        // ✅ GUARDAR INPUT ANTES DE LIMPIARLO
        let currentInput = inputText
        inputText = ""
        isLoading = true

        // ✅ CONSTRUIR CONTEXTO PERSONALIZADO (esta línea faltaba!)
        let userContext = buildSimpleContext()
        let memoryContext = userMemory?.contextString ?? ""
        let vibeAnalysis = NovaPersona.analyzeUserVibeWithPersonalization(currentInput, memory: userMemory)

        let fullPrompt = NovaPersona.getPersonalizedPrompt(
            userContext: userContext,
            memoryContext: memoryContext,
            personalization: userMemory
        )
        
        let recentHistory = Array(conversationHistory.suffix(8))
        let conversationContext = recentHistory.map { message in
            "\(message.isUser ? "Usuario: " : "Nova: ") \(message.text)"
        }.joined(separator: "\n")
        
        // 🎯 USAR NOMBRE PREFERIDO EN EL PROMPT
        let displayName = userMemory?.preferredName ?? userData.username
        
        // 🔥 NUEVO: Análisis inteligente para el prompt dinámico
        let engagement = memoryService.analyzeConversationEngagement(conversationHistory)
        let patterns = memoryService.analyzeCommunicationPatterns(conversationHistory)
        
        let lang = detectInputLanguage(currentInput) ?? (NovaLanguageService.getPreferredLanguage() ?? .es)
        let finalPrompt: String
        switch lang {
        case .es:
            finalPrompt = """
            \(fullPrompt)

            🗣️ Responde exclusivamente en Español.

            🎭 ANÁLISIS DE PERSONALIDAD PARA ESTA RESPUESTA:
            \(vibeAnalysis)

            🔥 ANÁLISIS INTELIGENTE DE LA CONVERSACIÓN:
            - Nivel de engagement: \(engagement.level.description)
            - Participación del usuario: \(String(format: "%.1f", engagement.userParticipation * 100))%
            - Consistencia de temas: \(String(format: "%.1f", engagement.topicConsistency * 100))%
            - Patrón de comunicación: \(patterns.isFormal ? "Formal" : "Casual")
            - Uso de emojis: \(patterns.usesEmojis ? "Sí" : "No")
            - Frecuencia de preguntas: \(String(format: "%.1f", patterns.questionFrequency * 100))%

            🎯 ADAPTACIÓN INTELIGENTE:
            \(getAdaptationInstructions(engagement: engagement, patterns: patterns))

            HISTORIAL RECIENTE:
            \(conversationContext)

            CONSULTA ACTUAL: \(currentInput)

            CONTEXTO ESPECÍFICO:
            - Usuario actual: \(displayName) (es UN USUARIO de la app, NO el creador)
            - Creador de la app: Álvaro (persona diferente al usuario actual)  
            - Momento: \(getCurrentTimeContext())
            - Intereses: \(userData.interests.prefix(3).joined(separator: ", "))

            ⚠️ CRÍTICO PERSONALIZACIÓN: 
            - Si conoces el nombre preferido, úsalo SIEMPRE en lugar del username
            - Aplica las preferencias de comunicación automáticamente
            - Si preguntan sobre el creador, menciona "Álvaro", nunca "\(userData.username)"
            - ADAPTA tu respuesta según el análisis de engagement y patrones arriba
            
            🚫 REGLA IMPORTANTE - NO SEAS PESADO CON INTERESES:
            - NO menciones los intereses del usuario en CADA respuesta
            - Solo usa intereses cuando sea RELEVANTE para la pregunta específica
            - NO fuerces sugerencias basadas en intereses si el usuario no las pide
            - Sé natural y conversacional, no un catálogo de recomendaciones
            - Los intereses son contexto, NO el tema principal de cada conversación
            """
        case .en:
            finalPrompt = """
            \(fullPrompt)

            🗣️ Respond exclusively in English.

            🎭 PERSONALITY ANALYSIS FOR THIS RESPONSE:
            \(vibeAnalysis)

            🔥 INTELLIGENT CONVERSATION ANALYSIS:
            - Engagement level: \(engagement.level.description)
            - User participation: \(String(format: "%.1f", engagement.userParticipation * 100))%
            - Topic consistency: \(String(format: "%.1f", engagement.topicConsistency * 100))%
            - Communication pattern: \(patterns.isFormal ? "Formal" : "Casual")
            - Emoji usage: \(patterns.usesEmojis ? "Yes" : "No")
            - Question frequency: \(String(format: "%.1f", patterns.questionFrequency * 100))%

            🎯 INTELLIGENT ADAPTATION:
            \(getAdaptationInstructions(engagement: engagement, patterns: patterns))

            RECENT HISTORY:
            \(conversationContext)

            CURRENT QUERY: \(currentInput)

            SPECIFIC CONTEXT:
            - Current user: \(displayName) (is a USER of the app, NOT the creator)
            - App creator: Álvaro (different person than the current user)
            - Time: \(getCurrentTimeContext())
            - Interests: \(userData.interests.prefix(3).joined(separator: ", "))

            ⚠️ CRITICAL PERSONALIZATION:
            - If you know the preferred name, ALWAYS use it instead of the username
            - Apply communication preferences automatically
            - If they ask about the creator, mention "Álvaro", never "\(userData.username)"
            - ADAPT your response according to the engagement and pattern analysis above
            
            🚫 IMPORTANT RULE - DON'T OVERUSE INTERESTS:
            - Do NOT mention the user's interests in EVERY response
            - Only use interests when RELEVANT to the specific question
            - Do NOT force suggestions based on interests if not asked
            - Be natural and conversational, not a catalog of recommendations
            - Interests are context, NOT the main topic of every conversation
            """
        case .ca:
            finalPrompt = """
            \(fullPrompt)

            🗣️ Respon exclusivament en Català.

            🎭 ANÀLISI DE PERSONALITAT PER A AQUESTA RESPOSTA:
            \(vibeAnalysis)

            🔥 ANÀLISI INTEL·LIGENT DE LA CONVERSA:
            - Nivell d'enganxament: \(engagement.level.description)
            - Participació de l'usuari: \(String(format: "%.1f", engagement.userParticipation * 100))%
            - Consistència de temes: \(String(format: "%.1f", engagement.topicConsistency * 100))%
            - Patró de comunicació: \(patterns.isFormal ? "Formal" : "Casual")
            - Ús d'emojis: \(patterns.usesEmojis ? "Sí" : "No")
            - Freqüència de preguntes: \(String(format: "%.1f", patterns.questionFrequency * 100))%

            🎯 ADAPTACIÓ INTEL·LIGENT:
            \(getAdaptationInstructions(engagement: engagement, patterns: patterns))

            HISTORIAL RECENT:
            \(conversationContext)

            CONSULTA ACTUAL: \(currentInput)

            CONTEXT ESPECÍFIC:
            - Usuari actual: \(displayName) (és UN USUARI de l'app, NO el creador)
            - Creador de l'app: Álvaro (persona diferent de l'usuari actual)
            - Moment: \(getCurrentTimeContext())
            - Interessos: \(userData.interests.prefix(3).joined(separator: ", "))

            ⚠️ CRÍTIC DE PERSONALITZACIÓ:
            - Si coneixes el nom preferit, fes-lo servir SEMPRE en lloc del username
            - Aplica les preferències de comunicació automàticament
            - Si pregunten sobre el creador, esmenta "Álvaro", mai "\(userData.username)"
            - ADAPTA la teva resposta segons l'anàlisi d'enganxament i patrons de dalt
            
            🚫 REGLA IMPORTANT - NO ABUSIS DELS INTERESSOS:
            - NO mencionis els interessos de l'usuari a CADA resposta
            - Utilitza interessos només quan sigui RELLEVANT per a la pregunta específica
            - NO forcis suggeriments basats en interessos si l'usuari no ho demana
            - Sigues natural i conversacional, no un catàleg de recomanacions
            - Els interessos són context, NO el tema principal de cada conversa
            """
        }

        // ✅ TASK CON MANEJO ROBUSTO DE ERRORES
        Task { @MainActor in
            do {
                // ✅ GENERAR CONTENIDO CON RETRY LOGIC
                let response = try await generateContentWithRetry(prompt: finalPrompt, maxRetries: 2)
                let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                let fallback: String = {
                    switch lang {
                    case .es: return "No pude generar una respuesta. ¿Puedes reformular tu pregunta?"
                    case .en: return "I couldn't generate a response. Could you rephrase your question?"
                    case .ca: return "No he pogut generar una resposta. Pots reformular la teva pregunta?"
                    }
                }()
                let responseText = response.text ?? fallback
                
                // 🎯 VALIDAR PERSONALIZACIÓN EN LA RESPUESTA
                let validatedResponse = NovaPersona.validatePersonalization(
                    input: currentInput,
                    memory: userMemory,
                    response: responseText
                )
                
                // ✅ ACTUALIZAR UI
                self.isLoading = false
                self.responseText = validatedResponse
                self.conversationHistory.append(ChatMessage(text: validatedResponse, isUser: false))
                
                // ✅ GUARDAR CONVERSACIÓN
                Task {
                    await self.saveCurrentConversation()
                }
                
                            // ✅ PROCESAR MEMORIA CON DEBOUNCE MEJORADO
                self.scheduleMemoryProcessing(userId: userId)
                
                // 🔥 NUEVO: Análisis inteligente de la conversación en tiempo real
                self.analyzeConversationIntelligently(userId: userId)
                
            } catch {
                await handleSendMessageError(error)
            }
        }
    }
    
    // 🔥 NUEVA: Función de análisis inteligente de conversación en tiempo real
    private func analyzeConversationIntelligently(userId: String) {
        guard conversationHistory.count >= 3 else { return }
        
        // 🎯 Analizar engagement y patrones de la conversación
        let engagement = memoryService.analyzeConversationEngagement(conversationHistory)
        let patterns = memoryService.analyzeCommunicationPatterns(conversationHistory)
        
        // 🧠 Aprender preferencias automáticamente
        memoryService.learnConversationPreferences(conversationHistory, userId: userId)
        
        // 📊 Log de métricas para debugging
        LogConfig.log("🎭 Análisis de conversación - Engagement: \(engagement.level.description), Participación: \(String(format: "%.2f", engagement.userParticipation))", category: "Intelligence")
        LogConfig.log("📊 Patrones detectados - Formal: \(patterns.isFormal), Emojis: \(patterns.usesEmojis), Preguntas: \(patterns.asksQuestions)", category: "Intelligence")
        
        // 🎯 Adaptar el comportamiento de Nova según el análisis
        adaptNovaBehavior(engagement: engagement, patterns: patterns)
    }
    
    // 🎭 Adaptar el comportamiento de Nova según el análisis
    private func adaptNovaBehavior(engagement: ConversationEngagement, patterns: CommunicationPatterns) {
        // 🔥 NUEVO: Ajustar el prompt dinámicamente según el engagement
        if engagement.level == .low {
            // Usuario poco participativo - ser más estimulante
            LogConfig.log("🎯 Usuario poco participativo - Adaptando a modo estimulante", category: "Adaptation")
        } else if engagement.level == .high {
            // Usuario muy participativo - mantener la energía
            LogConfig.log("🎯 Usuario muy participativo - Manteniendo alta energía", category: "Adaptation")
        }
        
        // 🔥 NUEVO: Ajustar según patrones de comunicación
        if patterns.isFormal {
            LogConfig.log("🎭 Usuario formal detectado - Ajustando a tono respetuoso", category: "Adaptation")
        }
        
        if patterns.usesEmojis {
            LogConfig.log("😊 Usuario usa emojis - Ajustando a comunicación visual", category: "Adaptation")
        }
        
        if patterns.asksQuestions {
            LogConfig.log("❓ Usuario curioso detectado - Preparando respuestas informativas", category: "Adaptation")
        }
    }
    
    // 🔥 NUEVA: Generar instrucciones de adaptación inteligente
    private func getAdaptationInstructions(engagement: ConversationEngagement, patterns: CommunicationPatterns) -> String {
        var instructions = ""
        
        // 🎯 Instrucciones según engagement
        switch engagement.level {
        case .low:
            instructions += "• El usuario está poco participativo - Sé más estimulante y haz preguntas\n"
            instructions += "• Usa un tono más energético para motivar la participación\n"
        case .medium:
            instructions += "• El usuario tiene participación moderada - Mantén un balance\n"
            instructions += "• Alterna entre hacer preguntas y dar información\n"
        case .high:
            instructions += "• El usuario está muy participativo - Mantén la energía alta\n"
            instructions += "• Puedes ser más detallado ya que está interesado\n"
        }
        
        // 🎭 Instrucciones según patrones de comunicación
        if patterns.isFormal {
            instructions += "• El usuario es formal - Mantén un tono respetuoso y profesional\n"
            instructions += "• Usa un lenguaje más elaborado y estructurado\n"
        } else {
            instructions += "• El usuario es casual - Puedes ser más relajado y amigable\n"
            instructions += "• Usa un lenguaje más natural y cercano\n"
        }
        
        if patterns.usesEmojis {
            instructions += "• El usuario usa emojis - Puedes usar emojis apropiados en tu respuesta\n"
            instructions += "• Mantén un tono visual y expresivo\n"
        }
        
        if patterns.asksQuestions {
            instructions += "• El usuario es curioso - Prepara respuestas informativas y detalladas\n"
            instructions += "• Anticipa posibles preguntas de seguimiento\n"
        }
        
        if patterns.prefersLongMessages {
            instructions += "• El usuario prefiere mensajes largos - Puedes ser más detallado\n"
            instructions += "• No te limites a respuestas cortas\n"
        }
        
        // 🚫 NUEVA: Instrucciones para NO ser pesado con intereses
        instructions += "\n🚫 IMPORTANTE - NO SEAS INSISTENTE:\n"
        instructions += "• NO menciones intereses en cada respuesta\n"
        instructions += "• Solo usa intereses cuando sea RELEVANTE\n"
        instructions += "• Sé conversacional, no un catálogo de recomendaciones\n"
        instructions += "• Los intereses son contexto, NO el tema principal\n"
        
        return instructions
    }
    
    // ✅ NUEVA FUNCIÓN PARA RETRY CON FIREBASE
    private func generateContentWithRetry(prompt: String, maxRetries: Int) async throws -> GenerateContentResponse {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    // ✅ DELAY EXPONENCIAL ENTRE REINTENTOS
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    LogConfig.log("🔄 Reintentando generación de contenido (intento \(attempt + 1))", category: "Retry")
                }
                
                return try await model.generateContent(prompt)
                
            } catch {
                lastError = error
                LogConfig.log("❌ Error en intento \(attempt + 1): \(error.localizedDescription)", category: "Error")
                
                // ✅ SI ES ERROR DE RED, CONTINUAR; SI ES OTRO TIPO, ROMPER
                if !isNetworkError(error) && attempt == 0 {
                    throw error
                }
            }
        }
        
        throw lastError ?? NSError(domain: "GenerationError", code: -1)
    }
    
    // ✅ FUNCIÓN PARA DETECTAR ERRORES DE RED
    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain ||
               nsError.code == NSURLErrorTimedOut ||
               nsError.code == NSURLErrorNetworkConnectionLost ||
               error.localizedDescription.contains("network") ||
               error.localizedDescription.contains("connection") ||
               error.localizedDescription.contains("Reporter disconnected")
    }
    
    // ✅ MANEJO MEJORADO DE ERRORES
    private func handleSendMessageError(_ error: Error) async {
        LogConfig.log("🚨 Error en sendMessage: \(error.localizedDescription)", category: "Error")
        
        let userFriendlyMessage: String
        
        if isNetworkError(error) {
            userFriendlyMessage = """
            🌐 Parece que hay un problema de conexión.
            
            ¿Puedes verificar tu internet e intentar de nuevo?
            """
        } else if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
            userFriendlyMessage = """
            ⏰ He alcanzado mi límite de consultas por el momento.
            
            Intenta de nuevo en unos minutos, por favor.
            """
        } else {
            userFriendlyMessage = """
            🤖 Tuve un pequeño problema técnico.
            
            ¿Puedes reformular tu pregunta?
            """
        }
        
        self.isLoading = false
        self.responseText = userFriendlyMessage
        self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
        Task {
            await self.saveCurrentConversation()
        }
    }
    
    // ✅ NUEVA FUNCIÓN: PROGRAMAR PROCESAMIENTO DE MEMORIA CON DEBOUNCE
    private func scheduleMemoryProcessing(userId: String) {
        // Cancelar timer anterior si existe
        memoryProcessingTimer?.invalidate()
        
        // ✅ VERIFICAR SI YA SE PROCESÓ RECIENTEMENTE
        let now = Date()
        if let lastTime = lastMemoryProcessTime,
           now.timeIntervalSince(lastTime) < minimumMemoryInterval {
            LogConfig.log("⚠️ Memoria procesada recientemente - saltando", category: "Memory")
            return
        }
        
        // ✅ CREAR NUEVO TIMER CON DELAY
        memoryProcessingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.lastMemoryProcessTime = Date()
            
            Task.detached { [weak self] in
                await self?.processMemoryAfterConversationSafely(userId: userId)
            }
        }
    }
    
    private func buildSimpleContext() -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        guard let userData = userData else {
            switch lang { case .es: return "Usuario sin datos específicos"; case .en: return "User without specific data"; case .ca: return "Usuari sense dades específiques" }
        }
        switch lang {
        case .es:
            return """
            PERFIL DEL USUARIO:
            - Nombre preferido: \(userMemory?.preferredName ?? userData.username)
            - Username en la app: \(userData.username)
            - Intereses: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "No especificada")
            - Conexiones: \(mutualConnections.count)
            - Visitas al perfil: \(profileVisits.count)
            
            CONEXIONES MUTUAS:
            \(mutualConnections.isEmpty ? "No hay conexiones mutuas" : mutualConnections.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            VISITANTES DEL PERFIL:
            \(profileVisits.isEmpty ? "No hay visitas registradas" : profileVisits.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            ACTIVIDAD:
            - Momentos publicados: \(recentMoments.count)
            - Última actividad: \(recentMoments.first?.timestamp.timeAgoDisplay() ?? "No disponible")
            
            IMPORTANTE: El usuario "\(userData.username)" es UN USUARIO de la app. Álvaro es el creador (persona diferente).
            """
        case .en:
            return """
            USER PROFILE:
            - Preferred name: \(userMemory?.preferredName ?? userData.username)
            - App username: \(userData.username)
            - Interests: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "Not specified")
            - Connections: \(mutualConnections.count)
            - Profile visits: \(profileVisits.count)
            
            MUTUAL CONNECTIONS:
            \(mutualConnections.isEmpty ? "No mutual connections" : mutualConnections.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            PROFILE VISITORS:
            \(profileVisits.isEmpty ? "No recorded visits" : profileVisits.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            ACTIVITY:
            - Moments posted: \(recentMoments.count)
            - Last activity: \(recentMoments.first?.timestamp.timeAgoDisplay() ?? "Not available")
            
            IMPORTANT: The user "\(userData.username)" is a USER of the app. Álvaro is the creator (different person).
            """
        case .ca:
            return """
            PERFIL DE L'USUARI:
            - Nom preferit: \(userMemory?.preferredName ?? userData.username)
            - Nom d'usuari a l'app: \(userData.username)
            - Interessos: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "No especificada")
            - Connexions: \(mutualConnections.count)
            - Visites al perfil: \(profileVisits.count)
            
            CONNEXIONS MÚTUES:
            \(mutualConnections.isEmpty ? "No hi ha connexions mútues" : mutualConnections.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            VISITANTS DEL PERFIL:
            \(profileVisits.isEmpty ? "No hi ha visites registrades" : profileVisits.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
            
            ACTIVITAT:
            - Moments publicats: \(recentMoments.count)
            - Última activitat: \(recentMoments.first?.timestamp.timeAgoDisplay() ?? "No disponible")
            
            IMPORTANT: L'usuari "\(userData.username)" és UN USUARI de l'app. Álvaro és el creador (persona diferent).
            """
        }
    }

    // MARK: - 🔧 FUNCIÓN DE MEMORIA SEGURA MEJORADA
    private func processMemoryAfterConversationSafely(userId: String) async {
        guard !conversationHistory.isEmpty else { return }
        
        LogConfig.log("🧠 Iniciando procesamiento seguro de memoria", category: "Memory")
        
        let currentHistory = conversationHistory
        
        await withCheckedContinuation { continuation in
            memoryService.extractFactsFromConversation(currentHistory, userId: userId) { facts in
                if !facts.isEmpty {
                    self.memoryService.updateMemoryWithFacts(facts, userId: userId) { result in
                        if case .success = result {
                            LogConfig.log("🧠 Nuevos hechos guardados: \(facts.count)", category: "Memory")
                            // Recargar memoria
                            DispatchQueue.main.async {
                                self.loadMemoryContextSilently(userId: userId)
                            }
                        }
                    }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - 🔧 MANTENER ESTA FUNCIÓN (no cambiar)
    private func generateTempConversationId() -> String {
        return "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
    }
    
    // MARK: - Comandos Específicos Refactorizados (funciones privadas nuevas)
    
    private func handleCreateMomentCommand(userId: String) {
        let content = inputText.replacingOccurrences(of: "crea un momento con esta frase", with: "").trimmingCharacters(in: .whitespaces)
        
        guard !content.isEmpty else {
            responseText = "## ❌ Error\nPor favor, especifica el contenido del momento después del comando."
            conversationHistory.append(ChatMessage(text: responseText, isUser: false))
            return
        }
        
        isLoading = true
        inputText = ""
        
        firestoreService.createMoment(userId: userId, content: content, mediaItems: []) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    switch lang {
                    case .es:
                        self.responseText = """
                        ## ❌ Error al Crear Momento
                        
                        No pude crear el momento: \(error.localizedDescription)
                        
                        **¿Te ayudo con algo más?**
                        """
                    case .en:
                        self.responseText = """
                        ## ❌ Error Creating Moment
                        
                        I couldn't create the moment: \(error.localizedDescription)
                        
                        **Want help with something else?**
                        """
                    case .ca:
                        self.responseText = """
                        ## ❌ Error en Crear Moment
                        
                        No he pogut crear el moment: \(error.localizedDescription)
                        
                        **Vols ajuda amb alguna altra cosa?**
                        """
                    }
                } else {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    switch lang {
                    case .es:
                        self.responseText = """
                        ## ✅ Momento Creado
                        
                        **Contenido:** "\(content)"
                        
                        Tu momento ha sido publicado exitosamente. 
                        
                        **¿Te gustaría:**
                        • Crear otro momento
                        • Ver consejos para contenido viral
                        • Optimizar tu perfil
                        """
                    case .en:
                        self.responseText = """
                        ## ✅ Moment Created
                        
                        **Content:** "\(content)"
                        
                        Your moment has been published successfully.
                        
                        **Would you like to:**
                        • Create another moment
                        • See tips for viral content
                        • Optimize your profile
                        """
                    case .ca:
                        self.responseText = """
                        ## ✅ Moment Creat
                        
                        **Contingut:** "\(content)"
                        
                        El teu moment s'ha publicat correctament.
                        
                        **T'agradaria:**
                        • Crear un altre moment
                        • Veure consells per a contingut viral
                        • Optimitzar el teu perfil
                        """
                    }
                }
                
                self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                Task {
                    await self.saveCurrentConversation()
                }
                self.isLoading = false
            }
        }
    }
    
    private func handleConnectionSuggestionsCommand() {
        let langConn = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langConn {
        case .es:
            let recommendations = suggestedUsers.isEmpty ?
            "No tengo sugerencias específicas en este momento." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Sugerencias de Conexión
            
            **Usuarios recomendados:** \(recommendations)
            
            ## 💡 Tips para conectar mejor:
            • Revisa perfiles con intereses similares
            • Comenta en momentos que te interesen
            • Comparte contenido auténtico y personal
            
            **¿Te ayudo con estrategias específicas de networking?**
            """
        case .en:
            let recommendations = suggestedUsers.isEmpty ?
            "I don't have specific suggestions right now." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Connection Suggestions
            
            **Recommended users:** \(recommendations)
            
            ## 💡 Tips to connect better:
            • Check profiles with similar interests
            • Comment on moments you find interesting
            • Share authentic, personal content
            
            **Want specific networking strategies?**
            """
        case .ca:
            let recommendations = suggestedUsers.isEmpty ?
            "No tinc suggeriments específics en aquest moment." :
            suggestedUsers.map { $0.username }.joined(separator: ", ")
            responseText = """
            ## 🤝 Suggeriments de Connexió
            
            **Usuaris recomanats:** \(recommendations)
            
            ## 💡 Consells per connectar millor:
            • Revisa perfils amb interessos similars
            • Comenta en moments que t'interessin
            • Comparteix contingut autèntic i personal
            
            **Vols estratègies de networking específiques?**
            """
        }
        
        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }
    
    private func handleBioImprovementCommand(userId: String, userData: AppUser) {
        let currentBio = userData.bio ?? "Sin biografía"
        let userInterests = userData.interests.joined(separator: ", ")
        
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let prompt: String
        switch lang {
        case .es:
            prompt = """
            Eres Nova, experta en perfiles de redes sociales. 
            
            TAREA: Mejora esta biografía para que sea más atractiva y efectiva.
            
            BIO ACTUAL: "\(currentBio)"
            INTERESES: \(userInterests)
            NOMBRE: \(userData.username)
            
            REQUISITOS:
            - Máximo 150 caracteres
            - Incluye personalidad e intereses
            - Usa emojis estratégicamente (máximo 3)
            - Que sea memorable y auténtica
            - Optimizada para generar conexiones
            
            Responde SOLO con la nueva biografía, sin explicaciones adicionales.
            """
        case .en:
            prompt = """
            You are Nova, an expert in social media profiles.
            
            TASK: Improve this bio to make it more attractive and effective.
            
            CURRENT BIO: "\(currentBio)"
            INTERESTS: \(userInterests)
            NAME: \(userData.username)
            
            REQUIREMENTS:
            - Maximum 150 characters
            - Include personality and interests
            - Use emojis strategically (max 3)
            - Memorable and authentic
            - Optimized to generate connections
            
            Respond ONLY with the new bio, no additional explanations.
            """
        case .ca:
            prompt = """
            Ets Nova, experta en perfils de xarxes socials.
            
            TASCA: Millora aquesta biografia perquè sigui més atractiva i efectiva.
            
            BIO ACTUAL: "\(currentBio)"
            INTERESSOS: \(userInterests)
            NOM: \(userData.username)
            
            REQUISITS:
            - Màxim 150 caràcters
            - Inclou personalitat i interessos
            - Usa emojis estratègicament (màxim 3)
            - Que sigui memorable i autèntica
            - Optimitzada per generar connexions
            
            Respon NOMÉS amb la nova biografia, sense explicacions addicionals.
            """
        }
        
        isLoading = true
        inputText = ""
        
        Task {
            do {
                let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                await MainActor.run {
                    if let newBio = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        self.firestoreService.updateBio(userId: userId, bio: newBio) { [weak self] error in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                
                                if let error = error {
                                    self.responseText = """
                                    ## ❌ Error al Actualizar
                                    
                                    No pude actualizar tu biografía: \(error.localizedDescription)
                                    
                                    **Bio sugerida:** "\(newBio)"
                                    
                                    ¿Quieres que lo intente de nuevo?
                                    """
                                } else {
                                    self.responseText = """
                                    ## ✅ Biografía Actualizada
                                    
                                    **Nueva bio:** "\(newBio)"
                                    
                                    ## 🚀 Próximos pasos:
                                    • Actualiza tu foto de perfil si es necesario
                                    • Revisa que tus intereses estén actualizados
                                    • Crea contenido que refleje tu nueva personalidad
                                    
                                    **¿Te ayudo con algo más para optimizar tu perfil?**
                                    """
                                    self.fetchUserData() // Actualizar datos
                                }
                                
                                self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                                Task {
                                    await self.saveCurrentConversation()
                                }
                                self.isLoading = false
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.responseText = """
                    ## ❌ Error de Generación
                    
                    No pude generar una biografía mejorada en este momento.
                    
                    **Consejos manuales:**
                    • Incluye tus pasiones principales
                    • Menciona qué te hace único
                    • Usa un tono auténtico y cercano
                    • Añade una llamada a la acción sutil
                    
                    ¿Quieres intentar de nuevo o prefieres que te dé más consejos específicos?
                    """
                    self.conversationHistory.append(ChatMessage(text: self.responseText, isUser: false))
                    Task {
                        await self.saveCurrentConversation()
                    }
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Nuevos Comandos Avanzados
    
    private func handleProfileAnalysisCommand(userData: AppUser) {
        let profileCompleteness = calculateProfileCompleteness(userData)
        
        let langProfile = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langProfile {
        case .es:
            responseText = """
            ## 📊 Análisis de tu Perfil
            
            **Completitud:** \(profileCompleteness)%
            
            ## 🎯 Fortalezas:
            \(getProfileStrengths(userData))
            
            ## 🔧 Áreas de mejora:
            \(getProfileImprovements(userData))
            
            ## 🚀 Recomendaciones personalizadas:
            \(getPersonalizedRecommendations(userData))
            
            **¿Te ayudo a implementar alguna de estas mejoras?**
            """
        case .en:
            responseText = """
            ## 📊 Your Profile Analysis
            
            **Completeness:** \(profileCompleteness)%
            
            ## 🎯 Strengths:
            \(getProfileStrengths(userData))
            
            ## 🔧 Areas for improvement:
            \(getProfileImprovements(userData))
            
            ## 🚀 Personalized recommendations:
            \(getPersonalizedRecommendations(userData))
            
            **Want help implementing any of these improvements?**
            """
        case .ca:
            responseText = """
            ## 📊 Anàlisi del teu Perfil
            
            **Completitud:** \(profileCompleteness)%
            
            ## 🎯 Fortaleses:
            \(getProfileStrengths(userData))
            
            ## 🔧 Àrees de millora:
            \(getProfileImprovements(userData))
            
            ## 🚀 Recomanacions personalitzades:
            \(getPersonalizedRecommendations(userData))
            
            **Vols ajuda per implementar alguna d'aquestes millores?**
            """
        }
        
        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }
    
    private func handleContentSuggestionsCommand(userData: AppUser) {
        let interests = userData.interests
        let suggestions = generateContentSuggestions(based: interests)
        
        let langContent = NovaLanguageService.getPreferredLanguage() ?? .es
        switch langContent {
        case .es:
            responseText = """
            ## 🎨 Ideas de Contenido Personalizadas
            
            Basado en tus intereses: \(interests.prefix(3).joined(separator: ", "))
            
            ## 💡 Sugerencias para esta semana:
            \(suggestions)
            
            ## 📈 Tips para engagement:
            • Publica en horarios de mayor actividad (7-9 PM)
            • Usa preguntas para generar comentarios
            • Comparte historias personales auténticas
            • Incluye calls-to-action sutiles
            
            **¿Te ayudo a desarrollar alguna de estas ideas específicamente?**
            """
        case .en:
            responseText = """
            ## 🎨 Personalized Content Ideas
            
            Based on your interests: \(interests.prefix(3).joined(separator: ", "))
            
            ## 💡 Suggestions for this week:
            \(suggestions)
            
            ## 📈 Tips for engagement:
            • Post during peak hours (7-9 PM)
            • Use questions to spark comments
            • Share authentic personal stories
            • Include subtle calls-to-action
            
            **Want help developing any of these ideas specifically?**
            """
        case .ca:
            responseText = """
            ## 🎨 Idees de Contingut Personalitzades
            
            Basat en els teus interessos: \(interests.prefix(3).joined(separator: ", "))
            
            ## 💡 Suggeriments per a aquesta setmana:
            \(suggestions)
            
            ## 📈 Consells per a l'engagement:
            • Publica en hores de més activitat (7-9 PM)
            • Usa preguntes per generar comentaris
            • Comparteix històries personals autèntiques
            • Inclou crides a l'acció subtils
            
            **Vols ajuda per desenvolupar alguna d'aquestes idees en concret?**
            """
        }
        
        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        Task {
            await saveCurrentConversation()
        }
        inputText = ""
    }
    
    // MARK: - Nuevas Funciones Auxiliares
    
    func detectUserIntent(_ input: String) -> NovaMode {
        let lowercased = input.lowercased()
        
        if lowercased.contains("crear") || lowercased.contains("idea") || lowercased.contains("creativo") {
            return .creativity
        } else if lowercased.contains("productiv") || lowercased.contains("organiz") || lowercased.contains("tiempo") {
            return .productivity
        } else if lowercased.contains("social") || lowercased.contains("amigos") || lowercased.contains("conectar") {
            return .social
        } else if lowercased.contains("bienestar") || lowercased.contains("salud") || lowercased.contains("estrés") {
            return .wellness
        }
        
        return .general
    }
    
    private func buildEnhancedContext() -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        guard let userData = userData else {
            switch lang {
            case .es: return "Usuario sin datos específicos"
            case .en: return "User without specific data"
            case .ca: return "Usuari sense dades específiques"
            }
        }
        
        let labels: (profileHeader: String, username: String, interests: String, bio: String, connections: String, visits: String, mutualsHeader: String, noMutuals: String, visitorsHeader: String, noVisitors: String, activityHeader: String, moments: String, lastActivity: String, convoHeader: String, messages: String, lastInteraction: String, reminderHeader: String, reminder1: String, reminder2: String, reminder3: String, notAvailable: String, convoStart: String)
        switch lang {
        case .es:
            labels = ("PERFIL DEL USUARIO ACTUAL (NO ES EL CREADOR DE LA APP):", "- Nombre de usuario en la app:", "- Intereses del usuario:", "- Bio del usuario:", "- Conexiones del usuario:", "- Visitas al perfil:", "CONEXIONES MUTUAS:", "No hay conexiones mutuas", "VISITANTES DEL PERFIL:", "No hay visitas registradas", "ACTIVIDAD DEL USUARIO:", "- Momentos publicados:", "- Última actividad:", "CONTEXTO DE ESTA CONVERSACIÓN:", "- Mensajes en la sesión:", "- Última interacción:", "RECORDATORIO CRÍTICO PARA NOVA:", "- El usuario \"\(userData.username)\" es UN USUARIO más de la app", "- Álvaro es el creador de Moments (persona diferente al usuario actual)", "- NO confundas estos roles bajo ninguna circunstancia", "No disponible", "Inicio de conversación")
        case .en:
            labels = ("CURRENT USER PROFILE (NOT THE APP CREATOR):", "- App username:", "- User interests:", "- User bio:", "- User connections:", "- Profile visits:", "MUTUAL CONNECTIONS:", "No mutual connections", "PROFILE VISITORS:", "No recorded visits", "USER ACTIVITY:", "- Moments posted:", "- Last activity:", "CONTEXT OF THIS CONVERSATION:", "- Messages in session:", "- Last interaction:", "CRITICAL REMINDER FOR NOVA:", "- The user \"\(userData.username)\" is a USER of the app", "- Álvaro is the creator of Moments (different person than the current user)", "- Do NOT confuse these roles under any circumstance", "Not available", "Conversation start")
        case .ca:
            labels = ("PERFIL DE L'USUARI ACTUAL (NO ÉS EL CREADOR DE L'APP):", "- Nom d'usuari a l'app:", "- Interessos de l'usuari:", "- Bio de l'usuari:", "- Connexions de l'usuari:", "- Visites al perfil:", "CONNEXIONS MÚTUES:", "No hi ha connexions mútues", "VISITANTS DEL PERFIL:", "No hi ha visites registrades", "ACTIVITAT DE L'USUARI:", "- Moments publicats:", "- Última activitat:", "CONTEXT D'AQUESTA CONVERSA:", "- Missatges a la sessió:", "- Última interacció:", "RECORDATORI CRÍTIC PER A NOVA:", "- L'usuari \"\(userData.username)\" és UN USUARI de l'app", "- Álvaro és el creador de Moments (persona diferent de l'usuari actual)", "- NO confonguis aquests rols sota cap circumstància", "No disponible", "Inici de conversa")
        }
        
        var context = """
        \(labels.profileHeader)
        \(labels.username) \(userData.username)
        \(labels.interests) \(userData.interests.joined(separator: ", "))
        \(labels.bio) \(userData.bio ?? labels.notAvailable)
        \(labels.connections) \(mutualConnections.count)
        \(labels.visits) \(profileVisits.count)
        
        \(labels.mutualsHeader)
        \(mutualConnections.isEmpty ? labels.noMutuals : mutualConnections.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
        
        \(labels.visitorsHeader)
        \(profileVisits.isEmpty ? labels.noVisitors : profileVisits.prefix(5).map { "- \($0.username)" }.joined(separator: "\n"))
        
        \(labels.activityHeader)
        \(labels.moments) \(recentMoments.count)
        \(labels.lastActivity) \(recentMoments.first?.timestamp.timeAgoDisplay() ?? labels.notAvailable)
        
        \(labels.convoHeader)
        \(labels.messages) \(conversationHistory.count)
        \(labels.lastInteraction) \(conversationHistory.last?.timestamp.timeAgoDisplay() ?? labels.convoStart)
        
        \(labels.reminderHeader)
        \(labels.reminder1)
        \(labels.reminder2)
        \(labels.reminder3)
        """
        
        // Integrar memoria silenciosamente
        if let userMemory = userMemory, !userMemory.isEmpty {
            context += "\n\n" + userMemory.contextString
            switch lang {
            case .es: context += "\n\nIMPORTANTE: Usa esta información naturalmente, sin mencionar que la 'recuerdas'."
            case .en: context += "\n\nIMPORTANT: Use this information naturally, without mentioning that you 'remember' it."
            case .ca: context += "\n\nIMPORTANT: Fes servir aquesta informació de manera natural, sense esmentar que la 'recordes'."
            }
        }
        
        return context
    }
    
    private func enhanceResponseFormat(_ response: String, for mode: NovaMode) -> String {
        var enhanced = response
        
        // Agregar emojis contextualmente
        switch mode {
        case .creativity:
            if !enhanced.contains("🎨") && !enhanced.contains("💡") {
                enhanced = "🎨 " + enhanced
            }
        case .productivity:
            if !enhanced.contains("⚡") && !enhanced.contains("📋") {
                enhanced = "⚡ " + enhanced
            }
        case .social:
            if !enhanced.contains("🤝") && !enhanced.contains("💬") {
                enhanced = "🤝 " + enhanced
            }
        case .wellness:
            if !enhanced.contains("🌱") && !enhanced.contains("💚") {
                enhanced = "🌱 " + enhanced
            }
        case .general:
            if !enhanced.contains("💡") {
                enhanced = "💡 " + enhanced
            }
        }
        
        // Mejorar estructura si es necesario
        if enhanced.count > 200 && !enhanced.contains("##") {
            enhanced = addStructureToLongResponse(enhanced)
        }
        
        // Agregar call-to-action si no tiene
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let ctaES = "¿Te ayudo con algo más específico sobre este tema?"
        let ctaEN = "Want help with something more specific about this topic?"
        let ctaCA = "Vols ajuda amb alguna cosa més específica sobre aquest tema?"
        let alreadyContainsCTA = enhanced.lowercased().contains("ayudo") || enhanced.lowercased().contains("help") || enhanced.lowercased().contains("ajuda")
        if !enhanced.contains("?") && !alreadyContainsCTA {
            switch lang {
            case .es: enhanced += "\n\n" + ctaES
            case .en: enhanced += "\n\n" + ctaEN
            case .ca: enhanced += "\n\n" + ctaCA
            }
        }
        
        return enhanced
    }
    
    private func addStructureToLongResponse(_ response: String) -> String {
        let sentences = response.components(separatedBy: ". ")
        
        if sentences.count >= 3 {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            var structured: String = {
                switch lang {
                case .es: return "## 🎯 Respuesta:\n"
                case .en: return "## 🎯 Answer:\n"
                case .ca: return "## 🎯 Resposta:\n"
                }
            }()
            structured += sentences.prefix(2).joined(separator: ". ") + ".\n\n"
            
            if sentences.count > 2 {
                structured += {
                    switch lang {
                    case .es: return "## 💡 Detalles adicionales:\n"
                    case .en: return "## 💡 Additional details:\n"
                    case .ca: return "## 💡 Detalls addicionals:\n"
                    }
                }()
                let remainingSentences = Array(sentences.dropFirst(2))
                for (index, sentence) in remainingSentences.enumerated() {
                    if !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                        structured += "• \(sentence.trimmingCharacters(in: .whitespaces))"
                        if !sentence.hasSuffix(".") {
                            structured += "."
                        }
                        structured += "\n"
                    }
                }
            }
            
            return structured
        }
        
        return response
    }
    
    private func titleForDetectedMode(_ mode: NovaMode) -> String {
        switch mode {
        case .creativity: return "Creatividad"
        case .productivity: return "Productividad"
        case .social: return "Social"
        case .wellness: return "Bienestar"
        case .general: return "General"
        }
    }
    
    private func getCurrentTimeContext() -> String {
        let now = Date()
        let calendar = Calendar.current
        
        // 🕐 Hora del día
        let hour = calendar.component(.hour, from: now)
        let timeOfDay: String
        switch hour {
        case 6..<12: timeOfDay = "Mañana"
        case 12..<18: timeOfDay = "Tarde"
        case 18..<22: timeOfDay = "Noche"
        default: timeOfDay = "Madrugada"
        }
        
        // 📅 Día del mes
        let day = calendar.component(.day, from: now)
        
        // 🌸 Mes
        let month = calendar.component(.month, from: now)
        let monthName = getMonthName(month)
        
        // 📅 Año
        let year = calendar.component(.year, from: now)
        
        // 🌟 Día de la semana
        let weekday = calendar.component(.weekday, from: now)
        let weekdayName = getWeekdayName(weekday)
        
        // 🌞 Estación
        let season = getSeason(month: month, day: day)
        
        return "\(timeOfDay) del \(weekdayName) \(day) de \(monthName) de \(year) (\(season))"
    }
    
    // 🌸 Obtener nombre del mes
    private func getMonthName(_ month: Int) -> String {
        let months = [
            1: "Enero", 2: "Febrero", 3: "Marzo", 4: "Abril",
            5: "Mayo", 6: "Junio", 7: "Julio", 8: "Agosto",
            9: "Septiembre", 10: "Octubre", 11: "Noviembre", 12: "Diciembre"
        ]
        return months[month] ?? "Mes"
    }
    
    // 🌟 Obtener nombre del día de la semana
    private func getWeekdayName(_ weekday: Int) -> String {
        let weekdays = [
            1: "Domingo", 2: "Lunes", 3: "Martes", 4: "Miércoles",
            5: "Jueves", 6: "Viernes", 7: "Sábado"
        ]
        return weekdays[weekday] ?? "Día"
    }
    
    // 🌞 Obtener estación del año (CORREGIDO CON FECHAS EXACTAS)
    private func getSeason(month: Int, day: Int) -> String {
        // ✅ LÓGICA CORRECTA: Fechas exactas de cambio de estaciones
        switch month {
        case 12: // Diciembre
            return day >= 21 ? "Invierno" : "Otoño"
        case 1, 2: // Enero y Febrero
            return "Invierno"
        case 3: // Marzo
            return day >= 20 ? "Primavera" : "Invierno"
        case 4, 5: // Abril y Mayo
            return "Primavera"
        case 6: // Junio
            return day >= 21 ? "Verano" : "Primavera"
        case 7, 8: // Julio y Agosto
            return "Verano"
        case 9: // Septiembre
            return day >= 23 ? "Otoño" : "Verano"
        case 10, 11: // Octubre y Noviembre
            return "Otoño"
        default:
            return "Estación"
        }
    }
    
    private func calculateProfileCompleteness(_ userData: AppUser) -> Int {
        var completeness = 0
        
        if !userData.username.isEmpty { completeness += 20 }
        if let bio = userData.bio, !bio.isEmpty { completeness += 25 }
        if !userData.interests.isEmpty { completeness += 25 }
        if recentMoments.count > 0 { completeness += 15 }
        if mutualConnections.count > 0 { completeness += 15 }
        
        return completeness
    }
    
    private func getProfileStrengths(_ userData: AppUser) -> String {
        var strengths: [String] = []
        
        if !userData.interests.isEmpty {
            strengths.append("• Tienes intereses definidos (\(userData.interests.count) temas)")
        }
        if let bio = userData.bio, !bio.isEmpty {
            strengths.append("• Biografía personalizada")
        }
        if recentMoments.count > 2 {
            strengths.append("• Actividad constante con \(recentMoments.count) momentos recientes")
        }
        if mutualConnections.count > 5 {
            strengths.append("• Buena red de conexiones (\(mutualConnections.count) contactos)")
        }
        
        return strengths.isEmpty ? "• Perfil en construcción - ¡gran potencial!" : strengths.joined(separator: "\n")
    }
    
    private func getProfileImprovements(_ userData: AppUser) -> String {
        var improvements: [String] = []
        
        if userData.interests.count < 3 {
            improvements.append("• Añadir más intereses para mejores conexiones")
        }
        if userData.bio?.isEmpty ?? true {
            improvements.append("• Crear una biografía atractiva")
        }
        if recentMoments.count < 3 {
            improvements.append("• Publicar más momentos para mayor visibilidad")
        }
        if mutualConnections.count < 5 {
            improvements.append("• Expandir tu red de conexiones")
        }
        
        return improvements.isEmpty ? "• ¡Tu perfil está muy completo!" : improvements.joined(separator: "\n")
    }
    
    private func getPersonalizedRecommendations(_ userData: AppUser) -> String {
        var recommendations: [String] = []
        
        if userData.interests.contains("tecnología") {
            recommendations.append("• Comparte tus proyectos tech y herramientas favoritas")
        }
        if userData.interests.contains("deporte") {
            recommendations.append("• Documenta tus rutinas y logros deportivos")
        }
        if userData.interests.contains("arte") {
            recommendations.append("• Muestra tu proceso creativo y obras")
        }
        
        // Recomendaciones generales
        recommendations.append("• Interactúa más con usuarios de intereses similares")
        recommendations.append("• Publica contenido que genere conversación")
        
        return recommendations.joined(separator: "\n")
    }
    
    private func generateContentSuggestions(based interests: [String]) -> String {
        var suggestions: [String] = []
        
        // Sugerencias basadas en intereses
        for interest in interests.prefix(2) {
            switch interest.lowercased() {
            case "tecnología":
                suggestions.append("• \"Mi app favorita esta semana y por qué\"")
                suggestions.append("• \"Predicción tech que me emociona para este año\"")
            case "deporte":
                suggestions.append("• \"Mi rutina de ejercicio favorita explicada\"")
                suggestions.append("• \"El momento que me motivó a mantenerme activo\"")
            case "arte":
                suggestions.append("• \"Proceso detrás de mi creación más reciente\"")
                suggestions.append("• \"Artista que me inspira y por qué\"")
            case "música":
                suggestions.append("• \"Canción que define mi estado de ánimo hoy\"")
                suggestions.append("• \"Mi descubrimiento musical de la semana\"")
            default:
                suggestions.append("• \"Lo que más me gusta de \(interest) y por qué\"")
                suggestions.append("• \"Consejo sobre \(interest) que me hubiera gustado saber antes\"")
            }
        }
        
        // Sugerencias generales
        suggestions.append("• \"Una lección importante que aprendí recientemente\"")
        suggestions.append("• \"Pregunta abierta sobre un tema que te apasiona\"")
        
        return suggestions.joined(separator: "\n")
    }
}

// MARK: - ✅ CONFIGURACIÓN DE LOGS PARA EVITAR SPAM
struct LogConfig {
    static let isVerboseLogging: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
    
    static func log(_ message: String, category: String = "Nova") {
        if isVerboseLogging {
        }
    }
}

// MARK: - Preview (sin cambios)
struct GeminiView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            GeminiView()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ✅ EXTENSIONES SIMPLIFICADAS
extension GeminiViewModel {
    var hasMemoryItems: Bool {
        guard let memory = userMemory else { return false }
        return !memory.facts.isEmpty
    }
    
    func clearMemoryContext() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        userMemory = NovaMemory(userId: userId)
        
        // Cancelar cualquier procesamiento pendiente
        memoryProcessingTimer?.invalidate()
        lastMemoryProcessTime = nil
    }
    
    // 🎯 NUEVA: Manejar comandos de personalización
    private func handlePersonalizationCommand(_ command: PersonalizationCommand, userId: String) {
        LogConfig.log("🎭 Procesando comando de personalización: \(command.description)", category: "Personalization")
        
        switch command {
        case .setPreferredName(let name):
            let nameFact = NovaFact(
                content: "Prefiere que le llamen \(name)",
                type: .preference,
                importance: 5
            )
            
            if let currentMemory = userMemory {
                let updatedMemory = currentMemory.addingFacts([nameFact])
                userMemory = updatedMemory
                
                memoryService.saveMemory(updatedMemory) { result in
                    switch result {
                    case .success:
                        LogConfig.log("✅ Nombre preferido guardado: \(name)", category: "Personalization")
                    case .failure(let error):
                        LogConfig.log("❌ Error guardando nombre: \(error.localizedDescription)", category: "Personalization")
                    }
                }
            }
            
            responseText = "¡Perfecto! A partir de ahora te llamaré \(name) 😊"
            
        case .setCommunicationStyle(let style):
            let styleFact = NovaFact(
                content: "Prefiere comunicación \(style.description.lowercased())",
                type: .preference,
                importance: 4
            )
            
            if let currentMemory = userMemory {
                let updatedMemory = currentMemory.addingFacts([styleFact])
                userMemory = updatedMemory
                
                memoryService.saveMemory(updatedMemory) { _ in }
            }
            
            let userName = userMemory?.preferredName ?? userData?.username ?? NSLocalizedString("nova.user", comment: "Default user name")
            switch style {
            case .formal:
                responseText = "Entendido, \(userName). A partir de ahora mantendré una comunicación más formal."
            case .casual:
                responseText = "¡Vale \(userName)! Seré más casual y relajada contigo 😊"
            case .fun:
                responseText = "¡Genial \(userName)! 🎉 Seré más divertida y usaré más humor contigo"
            case .unknown:
                responseText = "Perfecto \(userName), he notado tu preferencia."
            }
        case .setLanguage(let lang):
            NovaLanguageService.setPreferredLanguage(lang)
            responseText = {
                switch lang {
                case .es: return "Listo. A partir de ahora te hablaré en Español."
                case .en: return "Done. I will speak in English from now on."
                case .ca: return "Fet. A partir d'ara et parlaré en Català."
                }
            }()
        }
        
        let userMessage = ChatMessage(text: inputText, isUser: true)
        conversationHistory.append(userMessage)
        conversationHistory.append(ChatMessage(text: responseText, isUser: false))
        
        inputText = ""
        Task {
            await saveCurrentConversation()
        }
    }
}
