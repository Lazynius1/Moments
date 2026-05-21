import Foundation
import NaturalLanguage

// MARK: - 🎭 SERVICIO DE COMPORTAMIENTO
// Analiza el estilo de comunicación del usuario para adaptar la personalidad de Nova
class NovaBehaviorService {
    static let shared = NovaBehaviorService()
    
    private init() {}
    
    // MARK: - 🔄 ACTUALIZACIÓN DE PERFIL
    
    /// Actualiza el perfil de comportamiento basado en los mensajes recientes
    /// Utiliza una media móvil exponencial para suavizar los cambios
    func updateBehaviorProfile(memory: NovaMemory, recentMessages: [String]) -> NovaMemory {
        // Solo analizar si hay suficientes mensajes nuevos para ser significativo
        guard !recentMessages.isEmpty else { return memory }
        
        let analyzer = ConversationAnalyzer()
        let analysis = analyzer.analyze(messages: recentMessages)
        
        // Recuperar perfil actual o por defecto
        var profile = memory.behaviorProfile ?? .default
        
        // ⚖️ FACTOR DE APRENDIZAJE (0.0 - 1.0)
        // 0.2 significa que los nuevos datos pesan un 20% y el histórico un 80%
        // Esto evita cambios bruscos por un solo día "raro"
        let alpha = 0.2
        
        // Actualizar métricas con Media Móvil Exponencial (EMA)
        profile.averageMessageLength = (analysis.avgLength * alpha) + (profile.averageMessageLength * (1 - alpha))
        profile.emojiFrequency = (analysis.emojiFreq * alpha) + (profile.emojiFrequency * (1 - alpha))
        
        // Complejidad y Sentimiento (similar)
        let newComplexity = Double(analysis.complexity)
        let oldComplexity = Double(profile.vocabularyComplexity)
        profile.vocabularyComplexity = Int((newComplexity * alpha) + (oldComplexity * (1 - alpha)))
        
        // El sentimiento es más volátil, usamos un alpha mayor para que se adapte rápido al 'vibe' actual
        let sentimentAlpha = 0.5
        profile.sentimentTrend = (analysis.sentiment * sentimentAlpha) + (profile.sentimentTrend * (1 - sentimentAlpha))
        
        profile.lastUpdated = Date()
        
        // Devolver memoria actualizada
        var updatedMemory = memory
        updatedMemory.behaviorProfile = profile
        return updatedMemory
    }
}

// MARK: - 🧠 ANALIZADOR DE CONVERSACIÓN
struct ConversationAnalysisResult {
    let avgLength: Double
    let emojiFreq: Double
    let complexity: Int
    let sentiment: Double
}

class ConversationAnalyzer {
    
    func analyze(messages: [String]) -> ConversationAnalysisResult {
        var totalWords = 0
        var totalEmojis = 0
        var totalSentiment = 0.0
        var totalComplexWords = 0
        
        for msg in messages {
            // 1. Longitud
            let words = msg.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            totalWords += words.count
            
            // 2. Emojis
            let emojiCount = msg.unicodeScalars.filter { $0.properties.isEmoji }.count
            totalEmojis += emojiCount
            
            // 3. Complejidad (palabras > 6 letras)
            totalComplexWords += words.filter { $0.count > 6 }.count
            
            // 4. Sentimiento (NLTK muy básico usando NaturalLanguage framework si es posible, o heurística)
            totalSentiment += analyzeSentiment(text: msg)
        }
        
        let count = Double(messages.count)
        guard count > 0 else {
            return ConversationAnalysisResult(avgLength: 0, emojiFreq: 0, complexity: 5, sentiment: 0)
        }
        
        // Calcular promedio de longitud
        let avgLen = Double(totalWords) / count
        
        // Calcular frecuencia de emojis
        let emojiFreq = Double(totalEmojis) / count
        
        // Calcular complejidad (1-10)
        // Heurística: Si el 20% de las palabras son complejas (>6 letras) -> Complejidad alta
        let complexRatio = totalWords > 0 ? Double(totalComplexWords) / Double(totalWords) : 0
        // Mapear 0.0-0.3 a 1-10
        let complexityScore = min(10, max(1, Int(complexRatio * 30) + 2))
        
        // Promedio de sentimiento
        let avgSentiment = totalSentiment / count
        
        return ConversationAnalysisResult(
            avgLength: avgLen,
            emojiFreq: emojiFreq,
            complexity: complexityScore,
            sentiment: avgSentiment
        )
    }
    
    // Análisis de sentimiento usando NaturalLanguage
    private func analyzeSentiment(text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        var sentiment = 0.0
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        if let score = tag?.rawValue, let scoreDouble = Double(score) {
            sentiment = scoreDouble
        }
        
        return sentiment
    }
}
