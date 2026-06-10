import SwiftUI
import UIKit

// MARK: - Progress chrome aislado

/// Barra de progreso de stories: solo este subárbol se invalida al avanzar `progress`.
struct StorySegmentProgressChrome: View {
    let storyCount: Int
    let storyIndex: Int
    @ObservedObject var playbackCoordinator: StoryPlaybackCoordinator
    let audienceForSegment: (Int) -> String?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<storyCount, id: \.self) { index in
                GlassmorphicProgressBar(
                    progress: playbackCoordinator.progressForSegment(index: index, storyIndex: storyIndex),
                    isActive: index == storyIndex,
                    audience: audienceForSegment(index)
                )
            }
        }
    }
}

// MARK: - Floating reaction burst (estilo IG, sin doble tap)

/// Capa de reacciones flotantes aislada del chrome de stories.
struct StoryFloatingReactionLayer: View {
    let hearts: [FloatingHeart]
    let frameSize: CGSize
    let midX: CGFloat
    let midY: CGFloat

    var body: some View {
        FloatingHeartsView(hearts: hearts, containerSize: frameSize)
            .frame(width: frameSize.width, height: frameSize.height)
            .position(x: midX, y: midY)
    }
}

enum StoryReactionBurst {
    static let maxConcurrent = 48

    private static let reducedMotionCount = 3
    private static let normalCountRange = 5...8

    static func emit(
        _ hearts: inout [FloatingHeart],
        emoji: String,
        from sourcePoint: CGPoint? = nil,
        in containerSize: CGSize,
        onExpire: @escaping (UUID) -> Void
    ) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }

        let particles = makeParticles(emoji: emoji, from: sourcePoint, in: containerSize)
        hearts.append(contentsOf: particles)
        trimPool(&hearts)

        for particle in particles {
            let lifetime = particle.delay + particle.duration + 0.2
            let particleId = particle.id
            DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
                onExpire(particleId)
            }
        }

        if !MotionPolicy.reduceMotion {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private static func makeParticles(emoji: String, from sourcePoint: CGPoint?, in size: CGSize) -> [FloatingHeart] {
        let count = MotionPolicy.reduceMotion
            ? reducedMotionCount
            : Int.random(in: normalCountRange)

        // Default to the smiley button area (bottom right) if sourcePoint is nil
        let originX = sourcePoint?.x ?? (size.width * 0.82)
        let originY = sourcePoint?.y ?? (size.height * 0.92)

        return (0..<count).map { index in
            let isMainPop = (index == 0) && !MotionPolicy.reduceMotion
            
            // Stagger particles with delays and duration
            let delay = isMainPop ? 0.0 : (Double(index) * 0.035 + Double.random(in: 0...0.03))
            let duration = isMainPop ? 1.4 : Double.random(in: 1.3...2.1)
            
            // Sizes (main pop is larger to capture eye, others are bubbles)
            let fontSize = isMainPop ? CGFloat.random(in: 60...72) : CGFloat.random(in: 22...42)
            
            // Travel path: vertical distance and drift
            let verticalTravel = isMainPop ? size.height * 0.62 : size.height * CGFloat.random(in: 0.48...0.70)
            let lateralDrift = isMainPop ? CGFloat.random(in: -15...15) : CGFloat.random(in: -30...30)
            
            // Subtle offset from origin
            let spread = CGFloat.random(in: -20...20)
            let lift = CGFloat.random(in: -8...8)
            
            // Sway and rotation details
            let rotation = Double.random(in: -28...28)
            let rotationDelta = Double.random(in: -35...35)
            let swayAmplitude = isMainPop ? 8.0 : CGFloat.random(in: 6...14)
            let swayFrequency = isMainPop ? 0.5 : Double.random(in: 1.0...2.2)
            
            // Scale values
            let peakScale = isMainPop ? 1.45 : CGFloat.random(in: 1.1...1.26)
            let targetScale = isMainPop ? 1.05 : CGFloat.random(in: 0.72...0.88)

            return FloatingHeart(
                emoji: emoji,
                startX: originX + spread,
                startY: originY + lift,
                fontSize: fontSize,
                rotation: rotation,
                delay: delay,
                duration: duration,
                lateralDrift: lateralDrift,
                verticalTravel: verticalTravel,
                peakScale: peakScale,
                targetScale: targetScale,
                rotationDelta: rotationDelta,
                swayAmplitude: swayAmplitude,
                swayFrequency: swayFrequency
            )
        }
    }

    private static func trimPool(_ hearts: inout [FloatingHeart]) {
        guard hearts.count > maxConcurrent else { return }
        hearts.removeFirst(hearts.count - maxConcurrent)
    }
}
