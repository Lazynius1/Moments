import SwiftUI
import Firebase
import FirebaseVertexAI
import FirebaseFirestore
import FirebaseAuth
import UIKit
import PhotosUI
import Photos

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
    @State private var scrollOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var showConversationHistory = false
    @State private var isKeyboardVisible = false
    @State private var showLanguageSheet = false
    @State private var isShowingMemory = false
    
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
                        showSuggestedOptions: $viewModel.showSuggestedOptions,
                        isShowingMemory: $isShowingMemory
                    )
                    
                    ZStack {
                        if viewModel.userData != nil && !viewModel.isLoading && viewModel.conversationHistory.isEmpty && viewModel.showSuggestedOptions {
                            ModernWelcomeSection(
                                viewModel: viewModel,
                                showSuggestedOptions: $viewModel.showSuggestedOptions
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
                    
                    // ✅ BADGE DE DATOS ENCRIPTADOS
                    NovaEncryptionBadge()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .offset(y: keyboardHeight > 0 ? -keyboardHeight + safeAreaBottom - 100 : -80 + safeAreaBottom)
                        .opacity(keyboardHeight > 0 ? 0.7 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardHeight)
                    
                    // ⭐ INPUT BAR SIEMPRE VISIBLE
                    // ✅ OPTIMIZACIÓN: Solo animar el offset del teclado
                    EnhancedInputBar(
                        viewModel: viewModel,
                        showSuggestedOptions: $viewModel.showSuggestedOptions,
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
                    // ⭐ ESQUINAS REDONDEADAS SIEMPRE: Más pronunciadas cuando hay teclado (estilo cápsula)
                    .clipShape(RoundedRectangle(cornerRadius: keyboardHeight > 0 ? 30 : 16, style: .continuous))
                    .shadow(color: ModernGeminiColors.shadowColor, radius: 10, x: 0, y: keyboardHeight > 0 ? 5 : -5)
                    // ⭐ DISEÑO CAPSULAR: Añadimos un poco de margen lateral cuando el teclado está activo
                    .padding(.horizontal, keyboardHeight > 0 ? 12 : 0)
                    // ⭐ POSICIONAMIENTO DINÁMICO: 
                    // Cuando hay teclado, dejamos un pequeño margen de 8px para que "flote" sobre las esquinas redondeadas
                    .offset(y: keyboardHeight > 0 ? -keyboardHeight + safeAreaBottom - 8 : -80 + safeAreaBottom)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardHeight)
                }
                // ✅ Eliminado el animation global en VStack para no interferir con el teclado
                // .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
                
                // Overlay de historial de conversaciones
                if showConversationHistory {
                    ConversationHistoryOverlay(
                        viewModel: viewModel,
                        showConversationHistory: $showConversationHistory,
                        showSuggestedOptions: $viewModel.showSuggestedOptions
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
                }
                
                // 🎉 CONFETI OVERLAY
                if viewModel.showCelebration {
                    ConfettiView()
                        .zIndex(3)
                        .transition(.opacity)
                        .onAppear {
                            // Auto-ocultar después de 4 segundos
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation {
                                    viewModel.showCelebration = false
                                }
                            }
                        }
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
            .sheet(isPresented: $isShowingMemory) {
                NovaMemoryManagementView()
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
        Group {
            // ✅ MENSAJE DEL SISTEMA (estilo WhatsApp)
            if message.isSystem {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ModernGeminiColors.primary.opacity(0.7))
                        
                        Text(message.text)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(ModernGeminiColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(ModernGeminiColors.primary.opacity(0.15), lineWidth: 0.5)
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
                        }
                        
                        Text("nova.you")
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(ModernGeminiColors.textSecondary)
                            .padding(.trailing, 8)
                    }
                }
            } else {
                HStack {
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
        .onChange(of: message.text) { newText in
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
    
    static func success() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [ModernGeminiColors.primary, ModernGeminiColors.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            RoundedRectangle(cornerRadius: 2)
                .fill(ModernGeminiColors.primary.opacity(0.3))
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
                    .foregroundColor(ModernGeminiColors.textSecondary)
                
                Spacer()
                
                Button(action: {
                    UIPasteboard.general.string = cleanCode
                    withAnimation { isCopied = true }
                    NovaHapticFeedback.success()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { isCopied = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copiado" : "Copiar")
                    }
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(isCopied ? .green : ModernGeminiColors.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ModernGeminiColors.secondaryBackground.opacity(0.5))
            
            Divider()
                .background(ModernGeminiColors.borderColor)
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(cleanCode)
                    .font(.custom("SF Mono", size: 13))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .padding(12)
            }
        }
        .background(ModernGeminiColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ModernGeminiColors.borderColor, lineWidth: 1)
        )
        .padding(.vertical, 8)
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
            let startIndex = attributedString.startIndex
            
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
    @Binding var isShowingMemory: Bool
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
                // Botón de memoria
                Button(action: { isShowingMemory = true }) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20))
                        .foregroundColor(ModernGeminiColors.accent)
                        .frame(width: 36, height: 36)
                        .background(ModernGeminiColors.materialBackground)
                        .clipShape(Circle())
                        .shadow(color: ModernGeminiColors.shadowColor, radius: 4)
                }
                
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

                    DynamicWelcomeSuggestions(
                        viewModel: viewModel,
                        showSuggestedOptions: $showSuggestedOptions
                    )
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

// MARK: - ✨ SISTEMA DE PARTÍCULAS PREMIUM (Canvas)
struct PremiumSparkleParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var size: Double
    var opacity: Double
    var speedX: Double
    var speedY: Double
    var creationDate = Date()
}

// ✅ CLASE LIGERA SIN @Published PARA EVITAR BUCLES INFINITOS EN CANVAS
class PremiumSparkleSystem {
    var particles: [PremiumSparkleParticle] = []
    private let maxParticles = 15
    private var lastUpdate: TimeInterval = 0
    
    func update(date: Date) {
        let now = date.timeIntervalSince1970
        
        // Limitar updates a ~60fps si es necesario, pero Canvas ya lo maneja bien
        if now - lastUpdate < 0.016 { return }
        lastUpdate = now
        
        // Eliminar partículas viejas
        particles.removeAll { date.timeIntervalSince($0.creationDate) > 1.5 }
        
        // Mover partículas
        for i in 0..<particles.indices.count {
            particles[i].x += particles[i].speedX
            particles[i].y += particles[i].speedY
            particles[i].opacity -= 0.01
        }
        
        // Crear nuevas si es necesario
        if particles.count < maxParticles {
            addParticle()
        }
    }
    
    private func addParticle() {
        let p = PremiumSparkleParticle(
            x: Double.random(in: -40...40),
            y: Double.random(in: -40...40),
            size: Double.random(in: 2...6),
            opacity: Double.random(in: 0.4...1.0),
            speedX: Double.random(in: -0.2...0.2),
            speedY: Double.random(in: -0.5...(-0.1))
        )
        particles.append(p)
    }
}

struct PremiumSparkleEmitter: View {
    // ✅ USAR STATE EN LUGAR DE STATEOBJECT
    @State private var system = PremiumSparkleSystem()
    let color: Color
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // ✅ Update síncrono seguro dentro del draw loop (no dispara re-render externo)
                system.update(date: timeline.date)
                
                for particle in system.particles {
                    let rect = CGRect(
                        x: size.width/2 + particle.x,
                        y: size.height/2 + particle.y,
                        width: particle.size,
                        height: particle.size
                    )
                    
                    var resolvedContext = context
                    resolvedContext.opacity = particle.opacity
                    
                    // Dibujar estrella/sparkle
                    if let sparkle = context.resolveSymbol(id: "sparkle") {
                        resolvedContext.draw(sparkle, in: rect)
                    } else {
                        resolvedContext.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            } symbols: {
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color)
                    .tag("sparkle")
            }
        }
    }
}

// MARK: - 🎉 SISTEMA DE CONFETI (Celebración)
struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var color: Color
    var size: Double
    var rotation: Double
    var speedX: Double
    var speedY: Double
    var rotationSpeed: Double
    var opacity: Double = 1.0
}

class ConfettiSystem {
    var particles: [ConfettiParticle] = []
    private let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
    private var lastUpdate: TimeInterval = 0
    
    init() {
        // Lanzar explosión inicial
        for _ in 0..<50 {
            addParticle(burst: true)
        }
    }
    
    func update(date: Date, size: CGSize) {
        let now = date.timeIntervalSince1970
        if now - lastUpdate < 0.016 { return }
        lastUpdate = now
        
        // Mover partículas
        for i in 0..<particles.indices.count {
            particles[i].x += particles[i].speedX
            particles[i].y += particles[i].speedY
            particles[i].rotation += particles[i].rotationSpeed
            particles[i].speedY += 0.1 // Gravedad
            
            // Fade out al final
            if particles[i].y > size.height {
                particles[i].opacity -= 0.02
            }
        }
        
        // Eliminar las que caen fuera o son invisibles
        particles.removeAll { $0.y > size.height + 100 || $0.opacity <= 0 }
        
        // Añadir nuevas continuamente (fuente)
        if particles.count < 100 {
            addParticle(burst: false)
        }
    }
    
    private func addParticle(burst: Bool) {
        let p = ConfettiParticle(
            x: burst ? Double.random(in: -50...50) : Double.random(in: -300...300), // Centro o ancho
            y: burst ? Double.random(in: -50...50) : -50, // Centro o arriba
            color: colors.randomElement()!,
            size: Double.random(in: 6...12),
            rotation: Double.random(in: 0...360),
            speedX: Double.random(in: -2...2),
            speedY: burst ? Double.random(in: -10...(-2)) : Double.random(in: 2...8), // Explosión vs Caída
            rotationSpeed: Double.random(in: -5...5)
        )
        particles.append(p)
    }
}

struct ConfettiView: View {
    @State private var system = ConfettiSystem()
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                system.update(date: timeline.date, size: size)
                
                for particle in system.particles {
                    var particleContext = context
                    let rect = CGRect(
                        x: size.width/2 + particle.x, // Centrado
                        y: burstMode(particle) ? size.height/2 + particle.y : particle.y, // Ajuste coord
                        width: particle.size,
                        height: particle.size * 0.6
                    )
                    
                    particleContext.opacity = particle.opacity
                    particleContext.rotate(by: .degrees(particle.rotation))
                    
                    // Dibujar rectángulo de confeti
                    particleContext.fill(Path(getRect(rect)), with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false) // Permitir toques a través
    }
    
    // Helpers simples para lógica de posición
    private func burstMode(_ p: ConfettiParticle) -> Bool {
        return p.speedY < 0 // Si sube, es explosión inicial
    }
    
    private func getRect(_ rect: CGRect) -> CGRect {
        return rect
    }
}

struct ModernLoadingAnimation: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 20) {
                ZStack {
                    // ✨ Sparkles de fondo
                    PremiumSparkleEmitter(color: ModernGeminiColors.accent)
                        .frame(width: 100, height: 100)
                    
                    HStack(spacing: 12) {
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
                                .frame(width: 14, height: 14)
                                .scaleEffect(isAnimating ? 1.3 : 0.7)
                                .shadow(color: ModernGeminiColors.primary.opacity(0.4), radius: isAnimating ? 8 : 2)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: isAnimating
                                )
                        }
                    }
                }
                .frame(height: 60)
                
                Text("nova.typing")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ModernGeminiColors.textPrimary, ModernGeminiColors.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(isAnimating ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 1.2).repeatForever(), value: isAnimating)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(
                ZStack {
                    ModernGeminiColors.cardBackground
                    
                    // Efecto de brillo interior
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    ModernGeminiColors.accent.opacity(0.5),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .shadow(color: ModernGeminiColors.primary.opacity(0.15), radius: 15, x: 0, y: 8)
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Badge de Encriptación
struct NovaEncryptionBadge: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(ModernGeminiColors.primary.opacity(0.8))
            
            Text("nova.encryptedData")
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(ModernGeminiColors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(ModernGeminiColors.primary.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - EnhancedInputBar
struct EnhancedInputBar: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedItem: PhotosPickerItem? = nil
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ CALLBACK PARA NOTIFICAR CUANDO EL TEXTOFIELD OBTIENE FOCUS
    var onFocusChange: ((Bool) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // ⭐ SUGERENCIAS MEJORADAS (Welcome o Follow-up)
            if viewModel.showSuggestedOptions {
                if viewModel.conversationHistory.isEmpty {
                    // Sugerencias iniciales (Welcome)
                    SmartSuggestionChips(viewModel: viewModel, showSuggestedOptions: $viewModel.showSuggestedOptions, type: .welcome)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !viewModel.followUpSuggestions.isEmpty {
                    // Sugerencias contextuales (Follow-up)
                    SmartSuggestionChips(viewModel: viewModel, showSuggestedOptions: $viewModel.showSuggestedOptions, type: .followUp)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            
            // ⭐ SEPARADOR CONDICIONAL
            if viewModel.showSuggestedOptions && viewModel.conversationHistory.isEmpty {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(ModernGeminiColors.borderColor)
            }
            
            // ⭐ VISTA PREVIA DE IMAGEN SELECCIONADA
            if let selectedImage = viewModel.selectedImage {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                        
                        Button(action: {
                            viewModel.selectedImage = nil
                            selectedItem = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .font(.system(size: 20))
                        }
                        .offset(x: 10, y: -10)
                    }
                    .padding(.top, 8)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            HStack(alignment: .bottom, spacing: 12) {
                // ✅ Botón para adjuntar imágenes
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ModernGeminiColors.primary, ModernGeminiColors.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 10)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                viewModel.selectedImage = image
                            }
                        }
                    }
                }
                
                // ✅ TextField con cambios en el overlay para rendimiento
                TextField(NSLocalizedString("nova.input.placeholder", comment: "Ask Nova something placeholder"), text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(ModernGeminiColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ModernGeminiColors.borderColor.opacity(isTextFieldFocused ? 0.2 : 0.5),
                                        ModernGeminiColors.primary.opacity(isTextFieldFocused ? 0.1 : 0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
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
                        .padding(.bottom, 2) // Pequeño ajuste para aliñar con el círculo
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // ⭐ PADDING ADICIONAL PARA SAFE AREA CUANDO HAY TECLADO
            .padding(.bottom, isTextFieldFocused ? 0 : 0)
        }
        // ✅ APLICAR EL HALO INTELIGENTE COMO BACKGROUND DEL CONTENEDOR
        .background(
            IntelligentGlow(
                isFocused: isTextFieldFocused,
                cornerRadius: isTextFieldFocused ? 30 : 16,
                colors: [
                    ModernGeminiColors.primary,
                    ModernGeminiColors.secondary,
                    ModernGeminiColors.accent
                ]
            )
        )
        // ✅ Animar solo la aparición/desaparición del botón enviar
        .animation(.easeInOut(duration: 0.25), value: viewModel.inputText.isEmpty)
    }
}

// MARK: - Sugerencias Inteligentes Dinámicas
struct SmartSuggestionChips: View {
    enum SuggestionType {
        case welcome
        case followUp
    }
    
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    let type: SuggestionType
    
    @State private var dynamicSuggestions: [DynamicSuggestion] = []
    @State private var isLoadingSuggestions = true
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if type == .welcome ? isLoadingSuggestions : viewModel.isLoadingFollowUps {
                    // Placeholder mientras carga
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(ModernGeminiColors.secondaryBackground)
                            .frame(width: 120, height: 40)
                            .shimmer()
                    }
                } else {
                    let suggestions = type == .welcome ? 
                        dynamicSuggestions.map { SmartSuggestion(text: $0.text, icon: $0.icon, action: $0.action) } :
                        viewModel.followUpSuggestions
                    
                    ForEach(suggestions.prefix(6), id: \.text) { suggestion in
                        SmartSuggestionChip(
                            suggestion: suggestion
                        ) {
                            viewModel.inputText = suggestion.action ?? suggestion.text
                            viewModel.sendMessage()
                            // No ocultamos automáticamente para que el usuario vea la acción
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            loadDynamicSuggestions()
            // Refrescar sugerencias cada 5 minutos
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                loadDynamicSuggestions()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
        .onChange(of: viewModel.userData) { _ in
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userMemory?.id ?? "") { _ in
            loadDynamicSuggestions()
        }
    }
    
    private func loadDynamicSuggestions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoadingSuggestions = true
        NovaSuggestionService.shared.generateDynamicSuggestions(
            userId: userId,
            userMemory: viewModel.userMemory,
            userData: viewModel.userData
        ) { suggestions in
            Task { @MainActor in
                self.dynamicSuggestions = suggestions
                self.isLoadingSuggestions = false
            }
        }
    }
}

struct SmartSuggestion: Codable {
    let text: String
    let icon: String
    var action: String? = nil
}

// MARK: - Sugerencias Dinámicas para Welcome Section
struct DynamicWelcomeSuggestions: View {
    @ObservedObject var viewModel: GeminiViewModel
    @Binding var showSuggestedOptions: Bool
    @State private var dynamicSuggestions: [DynamicSuggestion] = []
    @State private var isLoadingSuggestions = true
    @State private var refreshTimer: Timer?
    
    var body: some View {
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

            if isLoadingSuggestions {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(ModernGeminiColors.secondaryBackground)
                            .frame(height: 100)
                            .shimmer()
                    }
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(dynamicSuggestions.prefix(4)) { suggestion in
                        ModernSuggestionCard(
                            title: suggestion.text,
                            icon: suggestion.icon,
                            gradient: getGradientForCategory(suggestion.category)
                        ) {
                            viewModel.inputText = suggestion.action
                            viewModel.sendMessage()
                            showSuggestedOptions = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadDynamicSuggestions()
            // Refrescar sugerencias cada 5 minutos
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                loadDynamicSuggestions()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
        .onChange(of: viewModel.userData) { _ in
            loadDynamicSuggestions()
        }
        .onChange(of: viewModel.userMemory?.id ?? "") { _ in
            loadDynamicSuggestions()
        }
    }
    
    private func loadDynamicSuggestions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoadingSuggestions = true
        NovaSuggestionService.shared.generateDynamicSuggestions(
            userId: userId,
            userMemory: viewModel.userMemory,
            userData: viewModel.userData
        ) { suggestions in
            Task { @MainActor in
                self.dynamicSuggestions = suggestions
                self.isLoadingSuggestions = false
            }
        }
    }
    
    private func getGradientForCategory(_ category: DynamicSuggestion.SuggestionCategory) -> [Color] {
        switch category {
        case .activity:
            return [ModernGeminiColors.primary, ModernGeminiColors.secondary]
        case .celebration:
            return [Color(hex: "FFD700"), Color(hex: "FFA500")]
        case .personalized:
            return [ModernGeminiColors.accent, ModernGeminiColors.primary]
        case .temporal:
            return [ModernGeminiColors.secondary, ModernGeminiColors.accent]
        case .general:
            return [ModernGeminiColors.primary, ModernGeminiColors.accent]
        }
    }
}

// MARK: - Shimmer Effect para Nova
extension View {
    func shimmer() -> some View {
        self.modifier(NovaShimmerModifier())
    }
}

struct NovaShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
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
    var text: String
    let image: UIImage? // ✅ NUEVO: Soporte para imágenes
    let isUser: Bool
    let timestamp: Date
    let isHistorical: Bool // ✅ NUEVO: Flag para mensajes históricos
    let isSystem: Bool // ✅ NUEVO: Flag para mensajes del sistema (como WhatsApp)

    init(text: String, isUser: Bool, image: UIImage? = nil, isHistorical: Bool = false, isSystem: Bool = false) {
        self.text = text
        self.image = image
        self.isUser = isUser
        self.timestamp = Date()
        self.isHistorical = isHistorical // ✅ Por defecto es nuevo mensaje
        self.isSystem = isSystem
    }

    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.image == rhs.image &&
               lhs.isUser == rhs.isUser &&
               lhs.isHistorical == rhs.isHistorical &&
               lhs.isSystem == rhs.isSystem
    }
}

// MARK: - GeminiViewModel Mejorado
@MainActor
class GeminiViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var selectedImage: UIImage? = nil
    @Published var responseText = ""
    @Published var isLoading = false
    @Published var conversationHistory: [ChatMessage] = []
    @Published var conversationTitles: [ConversationTitle] = []
    @Published var photoAuthorizationStatus: PHAuthorizationStatus = .notDetermined // ✅ NUEVO: Estado de permisos
    @Published var followUpSuggestions: [SmartSuggestion] = [] // ✅ NUEVO: Sugerencias contextuales
    @Published var isLoadingFollowUps = false // ✅ NUEVO: Estado de carga de sugerencias
    @Published var showSuggestedOptions = true // ✅ MOVIDO DESDE LA VISTA
    @Published var showCelebration = false // 🎉 NUEVO: Efecto de confeti

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
    private var model: GenerativeModel
    private var chatSession: Chat?
    
    private let memoryService = NovaMemoryService()
    // ✅ LAZY: Solo inicializar cuando realmente se necesite (cuando el usuario haga una consulta de actividad)
    private lazy var activityService: NovaActivityService = {
        LogConfig.log("🔧 NovaActivityService inicializado (lazy)", category: "Activity")
        return NovaActivityService.shared
    }()
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
        self.vertexAI = VertexAI.vertexAI(location: "global")
        
        // Inicialización básica (se actualizará cuando carguen los datos del usuario)
        self.model = vertexAI.generativeModel(modelName: "gemini-3-flash-preview")
        
        Task {
            await MainActor.run {
                self.conversationService = ConversationService()
            }
            await self.loadConversationTitles()
        }
    }

    // ✅ NUEVA: Configurar el modelo con instrucciones del sistema y sesión de chat
    private func setupModelAndSession() {
        guard let userData = userData else { return }
        
        let config = GenerationConfig(
            temperature: 0.7,
            topP: 0.8,
            topK: 40,
            candidateCount: 1,
            maxOutputTokens: 2048,
            stopSequences: [],
            responseMIMEType: "text/plain"
        )
        
        let safetySettings = [
            SafetySetting(harmCategory: .harassment, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .hateSpeech, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockMediumAndAbove),
            SafetySetting(harmCategory: .dangerousContent, threshold: .blockMediumAndAbove)
        ]
        
        // Construir instrucciones del sistema (System Instruction)
        // 🔥 Conversational Spark: Seleccionar y marcar
        self.userMemory?.selectRandomSpark()
        let systemInstruction = buildSystemInstruction()
        
        // Si hay un spark activo, marcarlo como usado para que no se repita pronto
        if let spark = self.userMemory?.activeSpark {
            Task {
                await self.markSparkAsProbed(id: spark.id)
            }
        }
        
        self.model = vertexAI.generativeModel(
            modelName: "gemini-3-flash-preview",
            generationConfig: config,
            safetySettings: safetySettings,
            systemInstruction: ModelContent(role: "system", parts: [systemInstruction])
        )
        
        // ✅ INICIAR SESIÓN DE CHAT (OPTIMIZADO: Sliding Window)
        // Convertimos el historial existente al formato de Gemini
        // Limitamos a los últimos 12 mensajes para ahorrar tokens (aprox. 6 turnos)
        let relevantHistory = conversationHistory.filter { !$0.isSystem }.suffix(12)
        
        let history = relevantHistory.map { msg in
            ModelContent(role: msg.isUser ? "user" : "model", parts: [msg.text])
        }
        
        self.chatSession = model.startChat(history: history)
        LogConfig.log("🚀 Sesión de Chat iniciada con \(history.count) mensajes de historial (Ventana deslizante)", category: "Gemini")
        
        // ✅ Verificar permisos al iniciar el VM
        checkPhotoLibraryPermission()
    }
    
    // MARK: - 🔐 PERMISOS DE GALERÍA (Consistente con Stories/Moments)
    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.photoAuthorizationStatus = status
        
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    self.photoAuthorizationStatus = newStatus
                }
            }
        }
    }

    private func buildSystemInstruction() -> String {
        guard let userData = userData else { return "" }
        
        let userContext = buildSimpleContext()
        let memoryContext = userMemory?.contextString ?? ""
        
        // Usamos la lógica de NovaPersona pero enfocada a System Instruction
        let instruction = NovaPersona.getPersonalizedPrompt(
            userContext: userContext,
            memoryContext: memoryContext,
            personalization: userMemory
        )
        
        return """
        \(instruction)
        
        🎯 CONTEXTO DINÁMICO DEL USUARIO:
        - Nombre para usar: \(userMemory?.preferredName ?? userData.username)
        - Intereses principales: \(userData.interests.joined(separator: ", "))
        - Momento actual: \(getCurrentTimeContext())
        
        ⚠️ REGLAS DE SESIÓN:
        - Mantén un tono consistente con el análisis de 'vibe' que recibirás en cada mensaje.
        - NO repitas que eres una IA o que tienes memoria.
        - Sé concisa y directa a menos que se pida detalle.
        """
    }
    // MARK: - 🧠 Helper de Memoria Conversacional
    func markSparkAsProbed(id: String) async {
        guard let memory = userMemory else { return }
        
        // 1. Actualizar memoria localmente (para esta sesión)
        self.userMemory = memory.markingFactAsProbed(id: id)
        
        // 2. Persistir en Firestore
        // Aseguramos que usamos la versión actualizada para guardar
        if let updatedMemory = self.userMemory {
            self.memoryService.saveMemory(updatedMemory) { result in
                switch result {
                case .success:
                    LogConfig.log("✅ Spark marcado como 'probed' exitosamente: \(id)", category: "Memory")
                case .failure(let error):
                    LogConfig.log("❌ Error marcando spark como probed: \(error.localizedDescription)", category: "Memory")
                }
            }
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
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let user):
                    self.userData = user
                    LogConfig.log("Datos del usuario obtenidos para Gemini: \(user.username)", category: "Data")
                    self.fetchRecentMoments(userId: userId)
                    self.fetchMutualConnections(userId: userId)
                    self.fetchUsersWithSharedInterests(userId: userId)
                    self.fetchProfileVisits(userId: userId)
                    self.fetchSuggestedUsers()
                    // Cargar memoria silencisamente
                    self.loadMemoryContextSilently(userId: userId)
                case .failure(let error):
                    LogConfig.log("Error al obtener datos del usuario: \(error.localizedDescription)", category: "Error")
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Memoria de Nova
    private func loadMemoryContextSilently(userId: String) {
        memoryService.loadMemory(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let memory):
                    self.userMemory = memory
                    // 🎯 Log del nombre preferido si existe
                    if let preferredName = memory.preferredName {
                        LogConfig.log("🎭 Nombre preferido detectado: \(preferredName)", category: "Personalization")
                    }
                    LogConfig.log("🧠 Memoria personalizada cargada: \(memory.facts.count) hechos", category: "Memory")
                    // ✅ NUEVO: Marcar que la memoria está lista y configurar sesión
                    self.hasMemoryLoaded = true
                    self.setupModelAndSession()
                case .failure(_):
                    self.userMemory = NovaMemory(userId: userId)
                    self.hasMemoryLoaded = true
                    self.setupModelAndSession()
                }
            }
        }
    }

    func fetchRecentMoments(userId: String) {
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let moments):
                    self.recentMoments = Array(moments.prefix(3))
                    LogConfig.log("Momentos recientes obtenidos: \(self.recentMoments.count)", category: "Data")
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
                            self.mutualConnections = []
                            self.objectWillChange.send() // ✅ Forzar actualización de UI
                            return
                        }
                        
                        // Obtener usuarios mutuos
                        self.firestoreService.fetchUsers(userIds: mutualIds) { result in
                            Task {
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
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let users):
                    self.usersWithSharedInterests = Array(users.prefix(3))
                    LogConfig.log("Usuarios con intereses compartidos obtenidos: \(self.usersWithSharedInterests.count)", category: "Data")
                case .failure(let error):
                    LogConfig.log("Error al obtener usuarios con intereses compartidos: \(error.localizedDescription)", category: "Error")
                }
                self.isLoading = false
            }
        }
    }

    func fetchProfileVisits(userId: String) {
        firestoreService.fetchVisits(userId: userId) { [weak self] result in
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let visits):
                    let visitorIds = visits.map { $0.visitorId }
                    
                    if visitorIds.isEmpty {
                        self.profileVisits = []
                        self.objectWillChange.send()
                        return
                    }
                    
                    // Obtener usuarios visitantes usando fetchUsersInBatches como ProfileView
                    self.fetchUsersInBatches(userIds: visitorIds) { users in
                        Task { @MainActor in
                            self.profileVisits = users
                            self.objectWillChange.send()
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
            guard let self = self else { return }
            Task {
                switch result {
                case .success(let users):
                    self.suggestedUsers = users
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
        
        // ✅ AÑADIR MENSAJE DEL SISTEMA (estilo WhatsApp)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let systemMessage: String
        switch lang {
        case .es:
            systemMessage = "Los mensajes están protegidos con cifrado de extremo a extremo. Nadie fuera de esta conversación puede leerlos, ni siquiera Moments."
        case .en:
            systemMessage = "Messages are protected with end-to-end encryption. No one outside of this conversation can read them, not even Moments."
        case .ca:
            systemMessage = "Els missatges estan protegits amb xifratge d'extrem a extrem. Ningú fora d'aquesta conversa pot llegir-los, ni tan sols Moments."
        }
        conversationHistory.append(ChatMessage(text: systemMessage, isUser: false, isSystem: true))
        
        if let userId = Auth.auth().currentUser?.uid {
            loadMemoryContextSilently(userId: userId)
            
            // 🎯 AÑADIR ESTE DELAY PEQUEÑO
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                // Forzar actualización de la UI para reflejar la memoria cargada
                self.objectWillChange.send()
            }
        }
    }
    
    func loadConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }
        
        LogConfig.log("🔄 Cargando conversación: \(conversationId)", category: "Conversation")
        isLoading = true
        
        let messages = await conversationService.loadConversation(conversationId, for: userId)
        self.conversationHistory = messages
        self.currentConversationId = conversationId
        self.isLoading = false
        self.objectWillChange.send()
        
        // Recargar contexto silenciosamente
        if let userId = Auth.auth().currentUser?.uid {
            self.loadMemoryContextSilently(userId: userId)
        }
    }
    
    func deleteConversation(_ conversationId: String) async {
        guard let userId = Auth.auth().currentUser?.uid,
              let conversationService = conversationService else { return }
        
        let success = await conversationService.deleteConversation(conversationId, for: userId)
        if success {
            self.conversationTitles.removeAll { $0.id == conversationId }
            if self.currentConversationId == conversationId {
                self.startNewConversation()
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

        // 🔥 NUEVO: Detectar preguntas sobre actividad de la app
        // ✅ SOLO ACTIVAR SI EL USUARIO REALMENTE PREGUNTA SOBRE ACTIVIDAD
        if let activityQuery = NovaActivityService.isActivityQuery(inputText) {
            // ✅ FORZAR INICIALIZACIÓN LAZY DEL SERVICIO SOLO AQUÍ
            _ = activityService // Esto activa el lazy var
            handleActivityQuery(activityQuery, userId: userId, userInput: inputText)
            return
        }

        // ✅ AÑADIR MENSAJE DEL SISTEMA SI ES LA PRIMERA VEZ (estilo WhatsApp)
        if conversationHistory.isEmpty && currentConversationId == nil {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            let systemMessage: String
            switch lang {
            case .es:
                systemMessage = "Los mensajes están protegidos con cifrado de extremo a extremo. Nadie fuera de esta conversación puede leerlos, ni siquiera Moments."
            case .en:
                systemMessage = "Messages are protected with end-to-end encryption. No one outside of this conversation can read them, not even Moments."
            case .ca:
                systemMessage = "Els missatges estan protegits amb xifratge d'extrem a extrem. Ningú fora d'aquesta conversa pot llegir-los, ni tan sols Moments."
            }
            conversationHistory.append(ChatMessage(text: systemMessage, isUser: false, isSystem: true))
        }
        
        // ✅ PREPARAR MENSAJE DEL USUARIO (con imagen si existe)
        let currentImage = selectedImage
        let userMessage = ChatMessage(text: inputText, isUser: true, image: currentImage)
        conversationHistory.append(userMessage)
        
        let currentInput = inputText
        inputText = ""
        
        // 🎭 ACTUALIZAR PERFIL DE COMPORTAMIENTO (En segundo plano)
        // 🎭 ACTUALIZAR PERFIL DE COMPORTAMIENTO (En segundo plano)
        if let memory = self.userMemory {
            // Capturar textos recientes (incluyendo el actual)
            let recentTexts = conversationHistory
                .filter { $0.isUser }
                .suffix(10)
                .map { $0.text }
            
            Task.detached(priority: .background) { [weak self] in
                let updatedMemory = NovaBehaviorService.shared.updateBehaviorProfile(memory: memory, recentMessages: Array(recentTexts))
                
                await MainActor.run {
                    self?.userMemory = updatedMemory
                    // Persistir silenciosamente
                    self?.memoryService.saveMemory(updatedMemory) { _ in }
                }
            }
        }
        selectedImage = nil
        isLoading = true

        // ✅ ANÁLISIS DINÁMICO (Mucho más ligero ahora)
        let vibeAnalysis = NovaPersona.analyzeUserVibeWithPersonalization(currentInput, memory: userMemory)
        let engagement = memoryService.analyzeConversationEngagement(conversationHistory)
        let patterns = memoryService.analyzeCommunicationPatterns(conversationHistory)
        let lang = detectInputLanguage(currentInput) ?? (NovaLanguageService.getPreferredLanguage() ?? .es)
        
        // 🔍 RAG: Búsqueda Semántica de Contexto
        var ragContext = ""
        if let memory = userMemory {
            // Buscar solo si hay memoria y query
            let relevantFacts = NovaEmbeddingService.shared.findSimilarFacts(query: currentInput, facts: memory.facts)
            if !relevantFacts.isEmpty {
                let contextContent = relevantFacts.map { "  • \($0.content)" }.joined(separator: "\n")
                // Localizar cabecera según idioma
                let header = lang == .es ? "💡 MEMORIA RELEVANTE:" : (lang == .ca ? "💡 MEMÒRIA RELLEVANT:" : "💡 RELEVANT MEMORY:")
                ragContext = "\n\(header)\n\(contextContent)"
                LogConfig.log("🔍 RAG: Inyectados \(relevantFacts.count) hechos relevantes", category: "Memory")
            }
        }
        
        // ✅ CONSTRUIR PROMPT LIGERO (El contexto pesado está en systemInstruction)
        let langName: String = {
            switch lang {
            case .es: return "Español"
            case .en: return "English"
            case .ca: return "Català"
            }
        }()
        
        let minimalPrompt = """
        🗣️ Responde en \(langName).
        🎭 Vibe actual: \(vibeAnalysis)
        🎯 Adaptación: \(getAdaptationInstructions(engagement: engagement, patterns: patterns))\(ragContext)
        
        Usuario: \(currentInput)
        """

        Task {
            do {
                // ✅ Asegurar sesión inicializada
                if chatSession == nil { setupModelAndSession() }
                
                // 1. Añadimos un mensaje vacío para el bot que iremos llenando
                let botMessage = ChatMessage(text: "", isUser: false)
                self.conversationHistory.append(botMessage)
                let botMessageIndex = self.conversationHistory.count - 1
                
                var fullResponseText = ""
                let stream = sendMessageStreamWithRetry(prompt: minimalPrompt, image: currentImage, maxRetries: 2)
                
                for try await chunk in stream {
                    if let newText = chunk.text {
                        fullResponseText += newText
                        // Actualizamos el mensaje en el historial en tiempo real
                        self.conversationHistory[botMessageIndex].text = fullResponseText
                        self.responseText = fullResponseText // Para otros usos de la UI si existen
                    }
                }
                
                // 🎯 VALIDAR PERSONALIZACIÓN FINAL
                let validatedResponse = NovaPersona.validatePersonalization(
                    input: currentInput,
                    memory: userMemory,
                    response: fullResponseText
                )
                
                // Actualizar con la versión validada si hubo cambios
                if validatedResponse != fullResponseText {
                    self.conversationHistory[botMessageIndex].text = validatedResponse
                    self.responseText = validatedResponse
                }
                
                self.isLoading = false
                triggerHapticFeedback(type: .success)
                
                await self.saveCurrentConversation()
                self.scheduleMemoryProcessing(userId: userId)
                self.analyzeConversationIntelligently(userId: userId)
                
                // 🎉 DETECTAR CELEBRACIÓN
                if self.shouldTriggerCelebration(text: validatedResponse) {
                    self.showCelebration = true
                    NovaHapticFeedback.success() // Doble feedback para enfatizar
                }

                // ✅ GENERAR SUGERENCIAS CONTEXTUALES
                await self.generateFollowUpSuggestions()
                
            } catch {
                await handleSendMessageError(error)
            }
        }
    }
    
    // 🔥 NUEVA: Generar sugerencias inteligentes basadas en el contexto actual
    private func generateFollowUpSuggestions() async {
        guard !conversationHistory.isEmpty else { return }
        
        // ✅ Detectar idioma del último mensaje del usuario para que las sugerencias coincidan
        let lastUserMessage = conversationHistory.last { $0.isUser }?.text ?? ""
        let lang = detectInputLanguage(lastUserMessage) ?? (NovaLanguageService.getPreferredLanguage() ?? .es)
        let langName = lang == .es ? "Español" : (lang == .ca ? "Català" : "English")

        await MainActor.run {
            self.isLoadingFollowUps = true
            self.followUpSuggestions = []
        }
        
        // 🧠 Prompt ligero para Gemini
        let suggestionPrompt = """
        Eres un asistente de IA que genera 3 sugerencias de seguimiento concisas y relevantes para una conversación.
        Las sugerencias deben ser en formato JSON, un array de objetos SmartSuggestion.
        Cada SmartSuggestion debe tener un 'title' (String) y un 'icon' (String, nombre de SF Symbol).
        El 'title' debe ser una pregunta o una frase corta que invite a continuar la conversación.
        El 'icon' debe ser relevante para el título.
        
        Ejemplo de JSON:
        [
            {"title": "¿Qué tal tu día?", "icon": "sun.max.fill"},
            {"title": "Cuéntame más", "icon": "ellipsis.bubble.fill"},
            {"title": "Alguna novedad?", "icon": "sparkles"}
        ]
        
        Contexto de la conversación (últimos 5 mensajes):
        \(conversationHistory.suffix(5).map { "\($0.isUser ? "Usuario" : "Nova"): \($0.text)" }.joined(separator: "\n"))
        
        Usa iconos de SF Symbols apropiados (sparkles, questionmark.circle, arrow.right, etc).
        Idioma: \(langName)
        """
        
        do {
            // Usamos el modelo principal para esto también (es más rápido en flash)
            let result = try await model.generateContent(suggestionPrompt)
            
            if let text = result.text {
                // Limpiar JSON si Gemini añade markdown
                let cleanedJSON = text.replacingOccurrences(of: "```json", with: "")
                                     .replacingOccurrences(of: "```", with: "")
                                     .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let data = cleanedJSON.data(using: .utf8) {
                    let decodedSuggestions = try JSONDecoder().decode([SmartSuggestion].self, from: data)
                    
                    await MainActor.run {
                        self.followUpSuggestions = decodedSuggestions
                        self.isLoadingFollowUps = false
                        // Mostrar sugerencias si no estamos en bienvenida
                        withAnimation(.spring()) {
                            self.showSuggestedOptions = true
                        }
                    }
                }
            }
        } catch {
            LogConfig.log("❌ Error generando sugerencias contextuales: \(error.localizedDescription)", category: "Gemini")
            await MainActor.run {
                self.isLoadingFollowUps = false
            }
        }
    }
    
    // 🎉 DETECTOR DE CELEBRACIONES
    private func shouldTriggerCelebration(text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let keywords = [
            "felicidades", "enhorabuena", "genial", "fantástico", "celebrar", 
            "increíble", "fiesta", "éxito", "congratulations", "amazing", 
            "hooray", "party", "success", "great job", "awesome",
            "felicitats", "enhorabona", "fantàstic"
        ]
        
        return keywords.contains { lowercasedText.contains($0) }
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
    
    // ✅ NUEVA: Envío de mensaje usando la sesión de chat con STREAMING (soporta Imágenes)
    private func sendMessageStreamWithRetry(prompt: String, image: UIImage?, maxRetries: Int) -> AsyncThrowingStream<GenerateContentResponse, Error> {
        return AsyncThrowingStream(GenerateContentResponse.self) { continuation in
            Task {
                var lastError: Error?
                
                for attempt in 0...maxRetries {
                    do {
                        if attempt > 0 {
                            let delay = pow(2.0, Double(attempt)) * 0.5
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            LogConfig.log("🔄 Reintentando envío multimodal con stream (intento \(attempt + 1))", category: "Retry")
                        }
                        
                        // ✅ USAR SESIÓN SI ESTÁ DISPONIBLE
                        guard let session = chatSession else {
                            continuation.finish(throwing: NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sesión no inicializada"]))
                            return
                        }
                        
                        // En FirebaseVertexAI, sendMessageStream puede aceptar variadic arguments o un array de Parts
                        // El objeto UIImage es PartsRepresentable por defecto
                        let stream: AsyncThrowingStream<GenerateContentResponse, Error>
                        if let image = image {
                            stream = try session.sendMessageStream(prompt, image)
                        } else {
                            stream = try session.sendMessageStream(prompt)
                        }
                        
                        for try await response in stream {
                            continuation.yield(response)
                        }
                        
                        continuation.finish()
                        return
                        
                    } catch {
                        lastError = error
                        LogConfig.log("❌ Error en streaming multimodal (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")
                        
                        if !isNetworkError(error) && attempt == 0 {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "GeminiError", code: -1))
            }
        }
    }

    // ✅ ANTIGUA: Envío de mensaje usando la sesión de chat (con historial, NO stream)
    private func sendMessageWithRetry(prompt: String, maxRetries: Int) async throws -> GenerateContentResponse {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    LogConfig.log("🔄 Reintentando envío de mensaje (intento \(attempt + 1))", category: "Retry")
                }
                
                if let session = chatSession {
                    return try await session.sendMessage(prompt)
                } else {
                    return try await model.generateContent(prompt)
                }
                
            } catch {
                lastError = error
                LogConfig.log("❌ Error en envío de mensaje (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")
                
                if !isNetworkError(error) && attempt == 0 {
                    throw error
                }
            }
        }
        
        throw lastError ?? NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error desconocido"])
    }

    // ✅ ANTIGUA: Generación de contenido simple (sin historial de sesión)
    // Se usa para cosas puntuales como regenerar bio, títulos, etc.
    private func generateContentWithRetry(prompt: String, maxRetries: Int) async throws -> GenerateContentResponse {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    LogConfig.log("🔄 Reintentando generación simple (intento \(attempt + 1))", category: "Retry")
                }
                
                return try await model.generateContent(prompt)
                
            } catch {
                lastError = error
                LogConfig.log("❌ Error en generación simple (intento \(attempt + 1)): \(error.localizedDescription)", category: "Error")
                
                if !isNetworkError(error) && attempt == 0 {
                    throw error
                }
            }
        }
        
        throw lastError ?? NSError(domain: "GeminiError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error desconocido"])
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
    
    // ✅ MANEJO MEJORADO DE ERRORES (multilingüe)
    private func handleSendMessageError(_ error: Error) async {
        LogConfig.log("🚨 Error en sendMessage: \(error.localizedDescription)", category: "Error")
        
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        let userFriendlyMessage: String
        
        if isNetworkError(error) {
            switch lang {
            case .es:
                userFriendlyMessage = """
                🌐 Parece que hay un problema de conexión.
                
                ¿Puedes verificar tu internet e intentar de nuevo?
                """
            case .en:
                userFriendlyMessage = """
                🌐 It seems there's a connection problem.
                
                Can you check your internet and try again?
                """
            case .ca:
                userFriendlyMessage = """
                🌐 Sembla que hi ha un problema de connexió.
                
                Pots verificar la teva internet i tornar-ho a provar?
                """
            }
        } else if error.localizedDescription.contains("quota") || error.localizedDescription.contains("limit") {
            switch lang {
            case .es:
                userFriendlyMessage = """
                ⏰ He alcanzado mi límite de consultas por el momento.
                
                Intenta de nuevo en unos minutos, por favor.
                """
            case .en:
                userFriendlyMessage = """
                ⏰ I've reached my query limit for the moment.
                
                Please try again in a few minutes.
                """
            case .ca:
                userFriendlyMessage = """
                ⏰ He arribat al meu límit de consultes per ara.
                
                Si us plau, torna-ho a provar en uns minuts.
                """
            }
        } else {
            switch lang {
            case .es:
                userFriendlyMessage = """
                🤖 Tuve un pequeño problema técnico.
                
                ¿Puedes reformular tu pregunta?
                """
            case .en:
                userFriendlyMessage = """
                🤖 I had a small technical problem.
                
                Can you rephrase your question?
                """
            case .ca:
                userFriendlyMessage = """
                🤖 He tingut un petit problema tècnic.
                
                Pots reformular la teva pregunta?
                """
            }
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
            
            IMPORTANTE: El usuario "\(userData.username)" es UN USUARIO de la app. Álvaro es el creador (persona diferente).
            """
        case .en:
            return """
            USER PROFILE:
            - Preferred name: \(userMemory?.preferredName ?? userData.username)
            - App username: \(userData.username)
            - Interests: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "Not specified")
            
            IMPORTANT: The user "\(userData.username)" is a USER of the app. Álvaro is the creator (different person).
            """
        case .ca:
            return """
            PERFIL DE L'USUARI:
            - Nom preferit: \(userMemory?.preferredName ?? userData.username)
            - Nom d'usuari a l'app: \(userData.username)
            - Interessos: \(userData.interests.joined(separator: ", "))
            - Bio: \(userData.bio ?? "No especificada")
            
            IMPORTANT: L'usuari "\(userData.username)" és un USUARI de l'app. Álvaro és el creador (persona diferent).
            """
        }
    }

    // MARK: - 🔧 FUNCIÓN DE MEMORIA SEGURA MEJORADA
    private func processMemoryAfterConversationSafely(userId: String) async {
        guard !conversationHistory.isEmpty else { return }
        
        LogConfig.log("🧠 Iniciando procesamiento seguro de memoria", category: "Memory")
        
        let currentHistory = conversationHistory
        let existingFacts = self.userMemory?.facts ?? []
        
        await withCheckedContinuation { continuation in
            memoryService.extractFactsFromConversation(currentHistory, userId: userId, existingFacts: existingFacts) { facts in
                if !facts.isEmpty {
                    self.memoryService.updateMemoryWithFacts(facts, userId: userId) { result in
                        if case .success = result {
                            LogConfig.log("🧠 Nuevos hechos guardados: \(facts.count)", category: "Memory")
                            
                            // 🔥 NUEVO: Feedback háptico cuando se guarda un hecho importante
                            let importantFacts = facts.filter { $0.importance >= 4 }
                            if !importantFacts.isEmpty {
                                self.triggerHapticFeedback(type: .medium)
                            }
                            
                            // Recargar memoria
                            self.loadMemoryContextSilently(userId: userId)
                        }
                    }
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - 🔥 NUEVO: Manejo de consultas de actividad
    private func handleActivityQuery(_ queryType: ActivityQueryType, userId: String, userInput: String) {
        let userMessage = ChatMessage(text: userInput, isUser: true)
        conversationHistory.append(userMessage)
        
        let currentInput = userInput
        inputText = ""
        isLoading = true
        
        Task {
            do {
                // Preparar variables de contexto (necesarias para todos los casos)
                let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                let memoryContext = userMemory?.contextString ?? ""
                let displayName = userMemory?.preferredName ?? userData?.username ?? "Usuario"
                
                let activityData: String
                
                switch queryType {
                case .storyChainViewers:
                    // Obtener el último chain y sus viewers (usando resumen optimizado)
                    if let chainInfo = try await getLatestStoryChain(userId: userId) {
                        let viewersSummary = try await getStoryChainViewersSummary(chainId: chainInfo.chainId, userId: userId)
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es:
                            activityData = "Story Chain \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        case .en:
                            activityData = "Story Chain \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        case .ca:
                            activityData = "Cadena d'històries \"\(chainInfo.chainTitle)\":\n\n\(viewersSummary.formattedSummary)"
                        }
                    } else {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es: activityData = "No tienes Story Chains publicados aún."
                        case .en: activityData = "You don't have any Story Chains published yet."
                        case .ca: activityData = "No tens cadenes d'històries publicades encara."
                        }
                    }
                    
                case .latestStoryChain:
                    if let chainInfo = try await getLatestStoryChain(userId: userId) {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es:
                            activityData = "Tu último Story Chain es \"\(chainInfo.chainTitle)\" con \(chainInfo.storyCount) partes, publicado \(timeAgoString(from: chainInfo.createdAt))."
                        case .en:
                            activityData = "Your latest Story Chain is \"\(chainInfo.chainTitle)\" with \(chainInfo.storyCount) parts, published \(timeAgoString(from: chainInfo.createdAt))."
                        case .ca:
                            activityData = "La teva última cadena d'històries és \"\(chainInfo.chainTitle)\" amb \(chainInfo.storyCount) parts, publicada \(timeAgoString(from: chainInfo.createdAt))."
                        }
                    } else {
                        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                        switch lang {
                        case .es: activityData = "No tienes Story Chains publicados aún."
                        case .en: activityData = "You don't have any Story Chains published yet."
                        case .ca: activityData = "No tens cadenes d'històries publicades encara."
                        }
                    }
                    
                case .profileVisits:
                    // Usar resumen optimizado (5 más recientes + conteo total)
                    let visitsSummary = try await getProfileVisitsSummary(userId: userId)
                    activityData = visitsSummary.formattedSummary
                    
                case .weeklySummary:
                    // Resumen semanal comparativo (usando datos crudos)
                    let weeklySummary = try await getWeeklySummary(userId: userId)
                    // Obtener insights proactivos
                    let insights = weeklySummary.proactiveInsights
                    // Convertir datos crudos a JSON string para Nova
                    if let jsonData = try? JSONSerialization.data(withJSONObject: weeklySummary.rawData, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        activityData = jsonString
                        
                        // Construir respuesta con insights proactivos
                        let prompt = buildActivityResponsePrompt(
                            userInput: currentInput,
                            activityData: activityData,
                            memoryContext: memoryContext,
                            displayName: displayName,
                            lang: lang,
                            proactiveInsights: insights
                        )
                        
                        let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                        let responseText = response.text ?? weeklySummary.formattedSummary
                        
                        self.isLoading = false
                        self.responseText = responseText
                        self.conversationHistory.append(ChatMessage(text: responseText, isUser: false))
                        
                        // 🔥 Feedback háptico diferenciado según tipo de insight y tendencias
                        let negativeInsights = insights.filter { $0.type != .positiveTrend && ($0.severity == .high || $0.severity == .medium) }
                        let positiveInsights = insights.filter { $0.type == .positiveTrend }
                        
                        // Detectar tendencias positivas directamente de los datos
                        let rawData = weeklySummary.rawData
                        var hasPositiveTrends = false
                        if let visitsData = rawData["profileVisits"] as? [String: Any],
                           let visitsChange = visitsData["change"] as? Int,
                           visitsChange > 15 {
                            hasPositiveTrends = true
                        }
                        if let engagementData = rawData["engagement"] as? [String: Any],
                           let reachChange = engagementData["reachChange"] as? Int,
                           reachChange > 20 {
                            hasPositiveTrends = true
                        }
                        if let momentsData = rawData["moments"] as? [String: Any],
                           let momentsChange = momentsData["change"] as? Int,
                           momentsChange > 20 {
                            hasPositiveTrends = true
                        }
                        
                        if !positiveInsights.isEmpty || hasPositiveTrends {
                            // Celebrar éxito con vibración de éxito (condicionamiento positivo)
                            triggerHapticFeedback(type: .success)
                        } else if !negativeInsights.isEmpty {
                            // Consejo proactivo sobre tendencia negativa con vibración media
                            triggerHapticFeedback(type: .medium)
                        } else {
                            // Respuesta normal con vibración ligera
                            triggerHapticFeedback(type: .light)
                        }
                        
                        Task {
                            await self.saveCurrentConversation()
                        }
                        return
                    } else {
                        activityData = weeklySummary.formattedSummary // Fallback
                    }
                    
                case .activitySummary:
                    // Resumen general de actividad (usando datos crudos)
                    let summary = try await getActivitySummary(userId: userId)
                    if let jsonData = try? JSONSerialization.data(withJSONObject: summary.rawData, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        activityData = jsonString
                    } else {
                        activityData = summary.formattedSummary // Fallback
                    }
                }
                
                // Construir respuesta con contexto (para todos los casos excepto weeklySummary que ya tiene su propio flujo)
                if queryType != .weeklySummary {
                    let lang = NovaLanguageService.getPreferredLanguage() ?? .es
                    let memoryContext = userMemory?.contextString ?? ""
                    let displayName = userMemory?.preferredName ?? userData?.username ?? "Usuario"
                    
                    let prompt = buildActivityResponsePrompt(
                        userInput: currentInput,
                        activityData: activityData,
                        memoryContext: memoryContext,
                        displayName: displayName,
                        lang: lang
                    )
                    
                    let response = try await generateContentWithRetry(prompt: prompt, maxRetries: 2)
                    let responseText = response.text ?? activityData
                    
                    self.isLoading = false
                    self.responseText = responseText
                    self.conversationHistory.append(ChatMessage(text: responseText, isUser: false))
                    
                    // 🔥 Feedback háptico
                    triggerHapticFeedback(type: .success)
                    
                    Task {
                        await self.saveCurrentConversation()
                    }
                }
                
            } catch {
                await handleSendMessageError(error)
            }
        }
    }
    
    // MARK: - 🔧 Helpers para consultas de actividad
    private func getLatestStoryChain(userId: String) async throws -> StoryChainInfo? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StoryChainInfo?, Error>) in
            activityService.getLatestStoryChain(userId: userId) { result in
                switch result {
                case .success(let chain):
                    continuation.resume(returning: chain)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func getStoryChainViewersSummary(chainId: String, userId: String) async throws -> StoryChainViewersSummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StoryChainViewersSummary, Error>) in
            activityService.getStoryChainViewersSummary(chainId: chainId, userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func getProfileVisitsSummary(userId: String) async throws -> ProfileVisitsSummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProfileVisitsSummary, Error>) in
            activityService.getProfileVisitsSummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func getActivitySummary(userId: String) async throws -> NovaActivitySummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NovaActivitySummary, Error>) in
            activityService.getActivitySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func getWeeklySummary(userId: String) async throws -> WeeklyActivitySummary {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WeeklyActivitySummary, Error>) in
            activityService.getWeeklySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func buildActivityResponsePrompt(userInput: String, activityData: String, memoryContext: String, displayName: String, lang: NovaLanguage, proactiveInsights: [ProactiveInsight]? = nil) -> String {
        let basePrompt = NovaPersona.getPersonalizedPrompt(
            userContext: "",
            memoryContext: memoryContext,
            personalization: userMemory
        )
        
        // 🔥 NUEVO: Convertir insights proactivos a JSON si existen
        var insightsJSON = ""
        if let insights = proactiveInsights, !insights.isEmpty {
            let insightsData = insights.map { $0.rawData }
            if let jsonData = try? JSONSerialization.data(withJSONObject: insightsData, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                insightsJSON = "\n\n💡 **CONSEJOS PROACTIVOS DETECTADOS:**\n\(jsonString)\n\nIMPORTANTE: Si hay insights con severity 'high' o 'medium', debes dar consejos proactivos y amigables. Si el usuario tiene personalidad 'fun', usa bromas. Si es 'formal', da consejos como un reporte ejecutivo.\n"
            }
        }
        
        switch lang {
        case .es:
            return """
            \(basePrompt)
            
            El usuario preguntó: "\(userInput)"
            
            📊 **DATOS DE ACTIVIDAD DE MOMENTS (en formato JSON):**
            \(activityData)
            \(insightsJSON)
            **INSTRUCCIONES:**
            - Los datos están en formato JSON crudo. TÚ debes redactar el mensaje según tu personalidad.
            - Si tu personalidad es "fun" → usa bromas, emojis, y un tono casual
            - Si tu personalidad es "formal" → redacta como un reporte ejecutivo profesional
            - Si tu personalidad es "casual" → sé natural y conversacional
            - NO repitas el JSON literalmente. Interpreta los datos y redacta un mensaje natural.
            - Si hay consejos proactivos, inclúyelos de forma natural en tu respuesta.
            - Si detectas tendencias negativas (cambios < -15%), ofrece consejos útiles y proactivos.
            - Si detectas tendencias positivas, celebra con el usuario según tu personalidad.
            """
        case .en:
            return """
            \(basePrompt)
            
            The user asked: "\(userInput)"
            
            📊 **MOMENTS ACTIVITY DATA (in JSON format):**
            \(activityData)
            \(insightsJSON)
            **INSTRUCTIONS:**
            - The data is in raw JSON format. YOU must write the message according to your personality.
            - If your personality is "fun" → use jokes, emojis, and a casual tone
            - If your personality is "formal" → write like a professional executive report
            - If your personality is "casual" → be natural and conversational
            - DO NOT repeat the JSON literally. Interpret the data and write a natural message.
            - If there are proactive insights, include them naturally in your response.
            - If you detect negative trends (changes < -15%), offer useful and proactive advice.
            - If you detect positive trends, celebrate with the user according to your personality.
            """
        case .ca:
            return """
            \(basePrompt)
            
            L'usuari ha preguntat: "\(userInput)"
            
            📊 **DADES D'ACTIVITAT DE MOMENTS (en format JSON):**
            \(activityData)
            \(insightsJSON)
            **INSTRUCCIONS:**
            - Les dades estan en format JSON cru. TU has de redactar el missatge segons la teva personalitat.
            - Si la teva personalitat és "fun" → usa bromes, emojis, i un to casual
            - Si la teva personalitat és "formal" → redacta com un informe executiu professional
            - Si la teva personalitat és "casual" → sigues natural i conversacional
            - NO repeteixis el JSON literalment. Interpreta les dades i redacta un missatge natural.
            - Si hi ha consells proactius, inclou-los de forma natural a la teva resposta.
            - Si detectes tendències negatives (canvis < -15%), ofereix consells útils i proactius.
            - Si detectes tendències positives, celebra amb l'usuari segons la teva personalitat.
            """
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        switch lang {
        case .es:
            if interval < 60 {
                return "hace un momento"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "hace \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "hace \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "hace \(days)d"
            }
        case .en:
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "\(minutes) min ago"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            } else {
                let days = Int(interval / 86400)
                return "\(days)d ago"
            }
        case .ca:
            if interval < 60 {
                return "fa un moment"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "fa \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "fa \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "fa \(days)d"
            }
        }
    }
    
    // MARK: - 🔥 NUEVO: Feedback háptico
    private func triggerHapticFeedback(type: HapticFeedbackType) {
        switch type {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
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
            Task { @MainActor in
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
                await self.saveCurrentConversation()
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
                if let newBio = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    self.firestoreService.updateBio(userId: userId, bio: newBio) { error in
                        Task { @MainActor in
                            
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

// MARK: - 🔥 Feedback Háptico
enum HapticFeedbackType {
    case light
    case medium
    case heavy
    case success
}
