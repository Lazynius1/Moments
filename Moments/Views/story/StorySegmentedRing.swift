import SwiftUI

// MARK: - Componente para anillo segmentado con gaps visibles
struct StorySegmentedRing: View {
    let storyCount: Int
    let hasStory: Bool
    let hasUnseenStory: Bool
    let storyViewedStatus: [Bool] // ✅ Estado de visto por cada historia
    let storyAudiences: [String?] // ✅ Audiencia por historia (alineada por índice)
    let isOwnStory: Bool // ✅ Para identificar historias propias
    let colorScheme: ColorScheme
    let hapticsEnabled: Bool // ✅ Respuesta háptica interactiva
    let ringSize: CGFloat
    let lineWidth: CGFloat
    
    private let gapAngle: Double = 15.0 // Grados de separación entre segmentos
    
    init(
        storyCount: Int,
        hasStory: Bool,
        hasUnseenStory: Bool,
        storyViewedStatus: [Bool],
        storyAudiences: [String?] = [],
        isOwnStory: Bool,
        colorScheme: ColorScheme,
        ringSize: CGFloat = 50,
        lineWidth: CGFloat = 2.5,
        hapticsEnabled: Bool = true
    ) {
        self.storyCount = storyCount
        self.hasStory = hasStory
        self.hasUnseenStory = hasUnseenStory
        self.storyViewedStatus = storyViewedStatus
        self.storyAudiences = storyAudiences
        self.isOwnStory = isOwnStory
        self.colorScheme = colorScheme
        self.ringSize = ringSize
        self.lineWidth = lineWidth
        self.hapticsEnabled = hapticsEnabled
    }
    
    // ✅ Función helper para disparar el haptic (Tier 1 feel)
    static func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    var body: some View {
        ZStack {
            if hasStory && storyCount > 0 {
                if storyCount == 1 {
                    // Si solo hay 1 historia, mostrar círculo completo sin gaps
                    Circle()
                        .stroke(storyRingGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: ringSize, height: ringSize)
                } else {
                    // Si hay múltiples historias, mostrar segmentos con gaps
                    ForEach(0..<storyCount, id: \.self) { index in
                        StorySegment(
                            index: index,
                            totalSegments: storyCount,
                            gapAngle: gapAngle,
                            gradient: segmentGradient(for: index),
                            lineWidth: lineWidth,
                            size: ringSize
                        )
                    }
                }
            } else {
                // ✅ SIN HISTORIAS: Sin anillo (transparente)
                Circle()
                    .stroke(Color.clear, lineWidth: 1)
                    .frame(width: ringSize, height: ringSize)
            }
        }
        .padding(lineWidth / 2 + 1) // ✅ Margen de seguridad para evitar cortes en los bordes por el grosor de línea
        .rotationEffect(.degrees(-90)) // Rotar todo el anillo para empezar arriba
    }
    
    private enum AudienceStyle {
        case bestFriends
        case mutuals
    }
    
    private func normalizedAudience(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? ""
    }
    
    private func audienceStyle(for index: Int) -> AudienceStyle? {
        guard storyAudiences.indices.contains(index) else { return nil }
        let key = normalizedAudience(storyAudiences[index])
        
        if key == "bestfriends" || key == "bestfriend" {
            return .bestFriends
        }
        
        if key == "mutuals" || key == "mutual" {
            return .mutuals
        }
        
        return nil
    }
    
    private func audienceGradient(_ style: AudienceStyle) -> LinearGradient {
        switch style {
        case .bestFriends:
            return LinearGradient(
                colors: [Color(hex: "24C26A"), Color(hex: "5BE584")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .mutuals:
            return LinearGradient(
                colors: [Color(hex: "00B4D8"), Color(hex: "4CC9F0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var viewedGrayGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ?
            [Color.gray.opacity(0.58), Color.gray.opacity(0.82)] :
            [Color.gray.opacity(0.76), Color.gray.opacity(0.94)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // ✅ Gradiente para un segmento específico
    private func segmentGradient(for index: Int) -> LinearGradient {
        let wasViewed = index < storyViewedStatus.count ? storyViewedStatus[index] : false
        
        // ✅ Para usuarios externos: una historia vista siempre vuelve a gris (incluye bestfriends/mutuals)
        if !isOwnStory && wasViewed {
            return viewedGrayGradient
        }
        
        // ✅ PRIORIDAD: color por audiencia del segmento (bestfriends/mutuals) cuando NO está vista
        if let style = audienceStyle(for: index) {
            return audienceGradient(style)
        }
        
        if isOwnStory {
            // ✅ HISTORIAS PROPIAS: Siempre iluminadas (azul → morado → rosa)
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // ✅ Para otros usuarios: verificar si esta historia específica ha sido vista
            if wasViewed {
                // ✅ HISTORIA YA VISTA: Gris según el tema
                return viewedGrayGradient
            } else {
                // ✅ HISTORIA NO VISTA: Iluminada (azul → morado → rosa)
                return LinearGradient(
                    colors: [Color.blue, Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    // ✅ Gradiente para círculo completo (cuando solo hay 1 historia)
    private var storyRingGradient: LinearGradient {
        let wasViewed = !hasUnseenStory
        
        // ✅ Para usuarios externos: vista => gris siempre
        if !isOwnStory && wasViewed {
            return viewedGrayGradient
        }
        
        // ✅ PRIORIDAD: si la única historia es bestfriends/mutuals, mantener su color
        if let style = audienceStyle(for: 0) {
            return audienceGradient(style)
        }
        
        if isOwnStory {
            // ✅ HISTORIAS PROPIAS: Siempre iluminadas (azul → morado → rosa)
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasUnseenStory {
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasStory {
            // ✅ HISTORIA YA VISTA: Gris según el tema
            return viewedGrayGradient
        } else {
            // ✅ SIN HISTORIAS: Sin anillo (transparente)
            return LinearGradient(
                colors: [Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Segmento individual del anillo con gap visible
struct StorySegment: View {
    let index: Int
    let totalSegments: Int
    let gapAngle: Double
    let gradient: LinearGradient
    let lineWidth: CGFloat
    let size: CGFloat
    
    var body: some View {
        // Calcular el ángulo total por segmento (en grados)
        let segmentAngleTotal = 360.0 / Double(totalSegments)
        // Ángulo útil de cada segmento (sin el gap)
        let segmentAngleUseful = segmentAngleTotal - gapAngle
        
        // Convertir a fracciones (0.0 a 1.0)
        let segmentFraction = segmentAngleUseful / 360.0
        
        // Posición inicial del segmento (en fracción 0.0 a 1.0)
        // 0.0 = punto más arriba del círculo en SwiftUI
        let startFraction = Double(index) * segmentAngleTotal / 360.0
        // Posición final del segmento (antes del gap)
        let endFraction = startFraction + segmentFraction
        
        // Asegurar que endFraction no exceda 1.0
        let clampedEnd = min(endFraction, 1.0)
        
        Circle()
            .trim(from: startFraction, to: clampedEnd)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
    }
}
