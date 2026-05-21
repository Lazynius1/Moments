import Foundation
import FirebaseAuth

// MARK: - 🎯 Servicio de Sugerencias Dinámicas para Nova
// Genera sugerencias personalizadas basadas en actividad, tendencias, memoria y contexto
class NovaSuggestionService {
    static let shared = NovaSuggestionService()
    private let activityService = NovaActivityService.shared
    private let memoryService = NovaMemoryService()
    
    private init() {}
    
    // MARK: - Generar Sugerencias Dinámicas
    func generateDynamicSuggestions(
        userId: String,
        userMemory: NovaMemory?,
        userData: AppUser?,
        completion: @escaping ([DynamicSuggestion]) -> Void
    ) {
        Task {
            let lang = NovaLanguageService.getPreferredLanguage() ?? .es
            var suggestions: [DynamicSuggestion] = []
            
            // 1. Obtener actividad reciente y tendencias
            let weeklySummary = await getWeeklySummary(userId: userId)
            let activitySummary = await getActivitySummary(userId: userId)
            let proactiveInsights = weeklySummary?.proactiveInsights ?? []
            
            // 2. Generar sugerencias basadas en tendencias (prioridad alta)
            suggestions.append(contentsOf: generateTrendBasedSuggestions(
                insights: proactiveInsights,
                weeklySummary: weeklySummary,
                lang: lang
            ))
            
            // 3. Generar sugerencias basadas en actividad reciente
            suggestions.append(contentsOf: generateActivityBasedSuggestions(
                activitySummary: activitySummary,
                lang: lang
            ))
            
            
            // 5. Generar sugerencias basadas en contexto temporal
            suggestions.append(contentsOf: generateTimeBasedSuggestions(lang: lang))
            
            // 6. Asegurar que tenemos al menos 6 sugerencias (rellenar con genéricas si es necesario)
            if suggestions.count < 6 {
                suggestions.append(contentsOf: generateFallbackSuggestions(lang: lang))
            }
            
            // 7. Ordenar por prioridad y tomar las mejores
            let sortedSuggestions = Array(
                Dictionary(grouping: suggestions, by: \.text)
                    .compactMap { $0.value.max(by: { $0.priority < $1.priority }) }
            )
                .sorted { $0.priority > $1.priority }
                .prefix(4)
            
            await MainActor.run {
                completion(Array(sortedSuggestions))
            }
        }
    }
    
    // MARK: - Sugerencias basadas en Tendencias
    private func generateTrendBasedSuggestions(
        insights: [ProactiveInsight],
        weeklySummary: WeeklyActivitySummary?,
        lang: NovaLanguage
    ) -> [DynamicSuggestion] {
        var suggestions: [DynamicSuggestion] = []
        
        for insight in insights {
            switch insight.type {
            case .profileVisitsDeclining:
                suggestions.append(DynamicSuggestion(
                    text: getLocalizedText(key: "suggestions.boostProfile", lang: lang),
                    icon: "person.crop.circle.badge.plus",
                    priority: insight.severity == .high ? 10 : 8,
                    category: .activity,
                    action: "¿Cómo puedo aumentar las visitas a mi perfil?"
                ))
                
            case .engagementDeclining:
                suggestions.append(DynamicSuggestion(
                    text: getLocalizedText(key: "suggestions.boostEngagement", lang: lang),
                    icon: "heart.circle.fill",
                    priority: insight.severity == .high ? 10 : 8,
                    category: .activity,
                    action: "¿Cómo puedo mejorar el engagement de mis momentos?"
                ))
                
            case .lowActivity:
                suggestions.append(DynamicSuggestion(
                    text: getLocalizedText(key: "suggestions.createMoreContent", lang: lang),
                    icon: "camera.fill",
                    priority: 9,
                    category: .activity,
                    action: "Dame ideas para crear nuevos momentos"
                ))
                
            case .storyViewsLow:
                suggestions.append(DynamicSuggestion(
                    text: getLocalizedText(key: "suggestions.improveStories", lang: lang),
                    icon: "photo.on.rectangle.angled",
                    priority: 8,
                    category: .activity,
                    action: "¿Cómo puedo hacer que mis stories tengan más visualizaciones?"
                ))
                
            case .positiveTrend:
                if let weeklySummary = weeklySummary {
                    let visitsChange = NovaActivityService.shared.calculatePercentageChange(
                        weeklySummary.thisWeek.profileVisits,
                        weeklySummary.lastWeek.profileVisits
                    )
                    if visitsChange > 20 {
                        suggestions.append(DynamicSuggestion(
                            text: getLocalizedText(key: "suggestions.celebrateGrowth", lang: lang),
                            icon: "star.fill",
                            priority: 7,
                            category: .celebration,
                            action: "Dame un resumen de mi crecimiento esta semana"
                        ))
                    }
                }
                
            case .echoAvailable:
                // 🌊 Sugerencia de Echo disponible (manejado por banners push)
                break
            }
        }
        
        return suggestions
    }
    
    // MARK: - Sugerencias basadas en Actividad
    private func generateActivityBasedSuggestions(
        activitySummary: NovaActivitySummary?,
        lang: NovaLanguage
    ) -> [DynamicSuggestion] {
        var suggestions: [DynamicSuggestion] = []
        
        guard let summary = activitySummary else { return suggestions }
        
        // Si hay visitas recientes pero no hay último Story Chain
        if !summary.recentVisits.isEmpty && summary.latestStoryChain == nil {
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.createStoryChain", lang: lang),
                icon: "photo.stack.fill",
                priority: 7,
                category: .activity,
                action: "Ayúdame a crear un nuevo Story Chain"
            ))
        }
        
        // Si hay último Story Chain pero pocas visitas
        if let chain = summary.latestStoryChain, summary.recentVisits.count < 3 {
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.shareMore", lang: lang),
                icon: "square.and.arrow.up.fill",
                priority: 6,
                category: .activity,
                action: "¿Cómo puedo hacer que más gente vea mi contenido?"
            ))
        }
        
        return suggestions
    }
    
    
    // MARK: - Sugerencias basadas en Tiempo
    private func generateTimeBasedSuggestions(lang: NovaLanguage) -> [DynamicSuggestion] {
        var suggestions: [DynamicSuggestion] = []
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        
        // Sugerencias según hora del día
        switch hour {
        case 6..<12:
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.morningBoost", lang: lang),
                icon: "sunrise.fill",
                priority: 4,
                category: .temporal,
                action: "Dame ideas para empezar bien el día en Moments"
            ))
        case 12..<18:
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.afternoonContent", lang: lang),
                icon: "sun.max.fill",
                priority: 4,
                category: .temporal,
                action: "¿Qué tipo de contenido funciona mejor por las tardes?"
            ))
        case 18..<22:
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.eveningEngagement", lang: lang),
                icon: "moon.stars.fill",
                priority: 5,
                category: .temporal,
                action: "¿Cuál es el mejor momento para publicar contenido?"
            ))
        default:
            break
        }
        
        // Sugerencias según día de la semana
        if weekday == 1 || weekday == 7 { // Domingo o Sábado
            suggestions.append(DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.weekendPlanning", lang: lang),
                icon: "calendar.badge.clock",
                priority: 4,
                category: .temporal,
                action: "Ayúdame a planificar mi contenido para el fin de semana"
            ))
        }
        
        return suggestions
    }
    
    // MARK: - Sugerencias de Respaldo (Fallback)
    private func generateFallbackSuggestions(lang: NovaLanguage) -> [DynamicSuggestion] {
        return [
            DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.weeklySummary", lang: lang),
                icon: "chart.bar.fill",
                priority: 3,
                category: .general,
                action: "Dame un resumen semanal"
            ),
            DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.contentIdeas", lang: lang),
                icon: "sparkles",
                priority: 3,
                category: .general,
                action: "Dame ideas para compartir algo hoy en Moments"
            ),
            DynamicSuggestion(
                text: getLocalizedText(key: "suggestions.organizeDay", lang: lang),
                icon: "person.2.fill",
                priority: 2,
                category: .general,
                action: "¿Con qué audiencia encajaría mejor lo que quiero compartir?"
            )
        ]
    }
    
    // MARK: - Helpers
    private func getWeeklySummary(userId: String) async -> WeeklyActivitySummary? {
        return await withCheckedContinuation { continuation in
            activityService.getWeeklySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func getActivitySummary(userId: String) async -> NovaActivitySummary? {
        return await withCheckedContinuation { continuation in
            activityService.getActivitySummary(userId: userId) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func getLocalizedText(key: String, lang: NovaLanguage) -> String {
        switch lang {
        case .es:
            switch key {
            case "suggestions.boostProfile": return "Mejorar mi perfil"
            case "suggestions.boostEngagement": return "Qué publicar ahora"
            case "suggestions.createMoreContent": return "Ideas para un momento"
            case "suggestions.improveStories": return "Ideas para una story"
            case "suggestions.celebrateGrowth": return "Ver cómo voy"
            case "suggestions.createStoryChain": return "Crear una cadena"
            case "suggestions.shareMore": return "Llegar a más gente"
            case "suggestions.contentAbout": return "Contenido sobre %@"
            case "suggestions.professionalTips": return "Pulir una idea"
            case "suggestions.morningBoost": return "Ideas para empezar"
            case "suggestions.afternoonContent": return "Algo para esta tarde"
            case "suggestions.eveningEngagement": return "Qué publicar esta noche"
            case "suggestions.weekendPlanning": return "Ideas para el finde"
            case "suggestions.weeklySummary": return "Resumen semanal"
            case "suggestions.contentIdeas": return "Ideas para hoy"
            case "suggestions.organizeDay": return "Elegir audiencia"
            default: return ""
            }
        case .en:
            switch key {
            case "suggestions.boostProfile": return "Improve my profile"
            case "suggestions.boostEngagement": return "What to post now"
            case "suggestions.createMoreContent": return "Moment ideas"
            case "suggestions.improveStories": return "Story ideas"
            case "suggestions.celebrateGrowth": return "See how I'm doing"
            case "suggestions.createStoryChain": return "Create a chain"
            case "suggestions.shareMore": return "Reach more people"
            case "suggestions.contentAbout": return "Content about %@"
            case "suggestions.professionalTips": return "Polish an idea"
            case "suggestions.morningBoost": return "Ideas to start"
            case "suggestions.afternoonContent": return "Something for later"
            case "suggestions.eveningEngagement": return "What to post tonight"
            case "suggestions.weekendPlanning": return "Weekend ideas"
            case "suggestions.weeklySummary": return "Weekly summary"
            case "suggestions.contentIdeas": return "Ideas for today"
            case "suggestions.organizeDay": return "Choose audience"
            default: return ""
            }
        case .ca:
            switch key {
            case "suggestions.boostProfile": return "Millorar el meu perfil"
            case "suggestions.boostEngagement": return "Què publicar ara"
            case "suggestions.createMoreContent": return "Idees per a un moment"
            case "suggestions.improveStories": return "Idees per a una història"
            case "suggestions.celebrateGrowth": return "Veure com vaig"
            case "suggestions.createStoryChain": return "Crear una cadena"
            case "suggestions.shareMore": return "Arribar a més gent"
            case "suggestions.contentAbout": return "Contingut sobre %@"
            case "suggestions.professionalTips": return "Polir una idea"
            case "suggestions.morningBoost": return "Idees per començar"
            case "suggestions.afternoonContent": return "Alguna cosa per la tarda"
            case "suggestions.eveningEngagement": return "Què publicar aquesta nit"
            case "suggestions.weekendPlanning": return "Idees pel cap de setmana"
            case "suggestions.weeklySummary": return "Resum setmanal"
            case "suggestions.contentIdeas": return "Idees per avui"
            case "suggestions.organizeDay": return "Triar audiència"
            default: return ""
            }
        }
    }
}

// MARK: - Modelo de Sugerencia Dinámica
struct DynamicSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
    let priority: Int // 1-10, mayor = más relevante
    let category: SuggestionCategory
    let action: String // Texto que se enviará cuando se seleccione
    
    enum SuggestionCategory {
        case activity
        case celebration
        case personalized
        case temporal
        case general
    }
}
