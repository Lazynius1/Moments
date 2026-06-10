import SwiftUI
import UIKit

/// Capa de efectos climáticos para los mapas (lluvia, nieve, tormenta).
/// Reemplaza al antiguo WeatherParticleEffectView, que configuraba los emisores
/// antes de que la vista tuviera tamaño y dejaba timers vivos.
struct MapWeatherEffectsView: UIViewRepresentable {
    let weather: WeatherData

    func makeUIView(context: Context) -> WeatherEffectsUIView {
        WeatherEffectsUIView()
    }

    func updateUIView(_ uiView: WeatherEffectsUIView, context: Context) {
        uiView.apply(weather: weather)
    }

    static func dismantleUIView(_ uiView: WeatherEffectsUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class WeatherEffectsUIView: UIView {
    private var currentCondition: WeatherCondition?
    private var currentIsNight = false
    private var emitters: [CAEmitterLayer] = []
    private var lightningTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        lightningTimer?.invalidate()
    }

    func tearDown() {
        lightningTimer?.invalidate()
        lightningTimer = nil
        emitters.forEach { $0.removeFromSuperlayer() }
        emitters.removeAll()
    }

    func apply(weather: WeatherData) {
        guard weather.condition != currentCondition || weather.isNight != currentIsNight else { return }
        currentCondition = weather.condition
        currentIsNight = weather.isNight
        rebuildEffects(for: weather)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // El tamaño llega después del primer update: recolocar los emisores aquí.
        for emitter in emitters {
            layout(emitter: emitter)
        }
    }

    private func layout(emitter: CAEmitterLayer) {
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
        emitter.emitterSize = CGSize(width: bounds.width + 120, height: 1)
    }

    private func rebuildEffects(for weather: WeatherData) {
        tearDown()

        guard !MotionPolicy.reduceMotion else { return }

        switch weather.condition {
        case .rain:
            addRainLayers(intensity: rainIntensity(for: weather))
        case .snow:
            addSnowLayers()
        case .thunderstorm:
            addRainLayers(intensity: 1.0)
            startLightning()
        default:
            break
        }
    }

    private func rainIntensity(for weather: WeatherData) -> CGFloat {
        // 0.4 llovizna … 1.0 aguacero
        let normalized = min(max(weather.precipitation / 8.0, 0), 1)
        return 0.4 + CGFloat(normalized) * 0.6
    }

    private var particleBudget: CGFloat {
        CGFloat(MotionPolicy.maxParticleCount)
    }

    // MARK: - Lluvia (dos planos de profundidad)

    private func addRainLayers(intensity: CGFloat) {
        let windAngle: CGFloat = .pi + 0.12 // ligera inclinación, cae casi vertical

        // Plano lejano: gotas pequeñas, lentas, más tenues
        let far = makeEmitter()
        let farCell = CAEmitterCell()
        farCell.contents = Self.rainStreakImage(width: 1.5, height: 14, alpha: 0.35)?.cgImage
        farCell.birthRate = Float(particleBudget * 0.45 * intensity)
        farCell.lifetime = 2.6
        farCell.velocity = 320
        farCell.velocityRange = 40
        farCell.emissionLongitude = windAngle
        farCell.emissionRange = 0.04
        farCell.scale = 0.7
        farCell.scaleRange = 0.15
        far.emitterCells = [farCell]

        // Plano cercano: gotas largas y rápidas
        let near = makeEmitter()
        let nearCell = CAEmitterCell()
        nearCell.contents = Self.rainStreakImage(width: 2.5, height: 26, alpha: 0.55)?.cgImage
        nearCell.birthRate = Float(particleBudget * 0.3 * intensity)
        nearCell.lifetime = 1.6
        nearCell.velocity = 560
        nearCell.velocityRange = 80
        nearCell.emissionLongitude = windAngle
        nearCell.emissionRange = 0.03
        nearCell.scale = 1.0
        nearCell.scaleRange = 0.2
        near.emitterCells = [nearCell]
    }

    // MARK: - Nieve (deriva lateral + rotación)

    private func addSnowLayers() {
        let far = makeEmitter()
        let farCell = CAEmitterCell()
        farCell.contents = Self.snowflakeImage(diameter: 5, alpha: 0.5)?.cgImage
        farCell.birthRate = Float(particleBudget * 0.25)
        farCell.lifetime = 12
        farCell.velocity = 26
        farCell.velocityRange = 12
        farCell.emissionLongitude = .pi
        farCell.emissionRange = .pi / 8
        farCell.xAcceleration = 6
        farCell.scale = 0.6
        farCell.scaleRange = 0.25
        farCell.spin = 0.3
        farCell.spinRange = 0.6
        far.emitterCells = [farCell]

        let near = makeEmitter()
        let nearCell = CAEmitterCell()
        nearCell.contents = Self.snowflakeImage(diameter: 9, alpha: 0.85)?.cgImage
        nearCell.birthRate = Float(particleBudget * 0.12)
        nearCell.lifetime = 9
        nearCell.velocity = 55
        nearCell.velocityRange = 25
        nearCell.emissionLongitude = .pi
        nearCell.emissionRange = .pi / 6
        nearCell.xAcceleration = -8
        nearCell.scale = 1.0
        nearCell.scaleRange = 0.3
        nearCell.spin = 0.5
        nearCell.spinRange = 1.0
        near.emitterCells = [nearCell]
    }

    // MARK: - Tormenta

    private func startLightning() {
        scheduleNextLightning()
    }

    private func scheduleNextLightning() {
        lightningTimer?.invalidate()
        lightningTimer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: 4...10),
            repeats: false
        ) { [weak self] _ in
            self?.fireLightningFlash()
            self?.scheduleNextLightning()
        }
    }

    private func fireLightningFlash() {
        guard bounds.width > 0 else { return }

        let flash = CAGradientLayer()
        flash.frame = bounds
        flash.type = .radial
        let centerX = CGFloat.random(in: 0.2...0.8)
        flash.startPoint = CGPoint(x: centerX, y: 0)
        flash.endPoint = CGPoint(x: centerX + 0.9, y: 1.0)
        flash.colors = [
            UIColor.white.withAlphaComponent(0.55).cgColor,
            UIColor.white.withAlphaComponent(0.18).cgColor,
            UIColor.clear.cgColor
        ]
        flash.opacity = 0
        layer.addSublayer(flash)

        // Doble pulso: destello corto + réplica más tenue
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 1, 0.1, 0.6, 0]
        pulse.keyTimes = [0, 0.08, 0.25, 0.4, 1]
        pulse.duration = 0.55
        pulse.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            flash.removeFromSuperlayer()
        }
        flash.add(pulse, forKey: "lightning")
        CATransaction.commit()
    }

    // MARK: - Helpers

    private func makeEmitter() -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        layout(emitter: emitter)
        layer.addSublayer(emitter)
        emitters.append(emitter)
        return emitter
    }

    /// Gota alargada con degradado (transparente arriba → visible abajo).
    private static func rainStreakImage(width: CGFloat, height: CGFloat, alpha: CGFloat) -> UIImage? {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor.white.withAlphaComponent(0).cgColor,
                UIColor(red: 0.75, green: 0.88, blue: 1.0, alpha: alpha).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: width / 2)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.clip()
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: height),
                options: []
            )
        }
    }

    /// Copo suave: círculo con halo difuminado.
    private static func snowflakeImage(diameter: CGFloat, alpha: CGFloat) -> UIImage? {
        let padding: CGFloat = 4
        let size = CGSize(width: diameter + padding * 2, height: diameter + padding * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [
                UIColor.white.withAlphaComponent(alpha).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
    }
}

extension WeatherData {
    var mapOverlayColor: Color {
        switch condition {
        case .clear:
            return isNight ? Color.blue : Color.yellow
        case .partlyCloudy:
            return isNight ? Color.indigo : Color.orange
        case .cloudy:
            return Color.gray
        case .rain:
            return Color.blue
        case .snow:
            return Color.white
        case .thunderstorm:
            return Color.purple
        case .unknown:
            return Color.clear
        }
    }

    var mapOverlayOpacity: Double {
        switch condition {
        case .clear:
            return isNight ? 0.1 : 0.05
        case .partlyCloudy:
            return 0.08
        case .cloudy:
            return 0.15
        case .rain:
            return 0.2
        case .snow:
            return 0.25
        case .thunderstorm:
            return 0.3
        case .unknown:
            return 0.0
        }
    }
}
