import UIKit

enum StoryTextMotionEngine {
    private static let motionKey = "story.text.motion"

    static func apply(to view: UIView, motion: StoryEditingView.TextMotion, replayToken: Int) {
        view.layer.removeAnimation(forKey: motionKey)
        view.layer.mask = nil
        view.transform = .identity
        view.alpha = 1

        guard motion != .none else { return }

        switch motion {
        case .pop:
            applyPop(to: view.layer)
        case .bounce:
            applyBounce(to: view.layer)
        case .wave:
            applyWave(to: view.layer)
        case .typewriter:
            applyTypewriter(to: view)
        case .reveal:
            applyReveal(to: view.layer)
        case .none:
            break
        }

        _ = replayToken
    }

    private static func applyPop(to layer: CALayer) {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.15, 0.94, 1.05, 1.0, 1.0, 1.0]
        scale.keyTimes = [0.0, 0.14, 0.28, 0.42, 0.54, 0.80, 1.0]
        scale.duration = 1.2
        scale.repeatCount = .infinity
        scale.isRemovedOnCompletion = false

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        let linear = CAMediaTimingFunction(name: .linear)

        scale.timingFunctions = [
            easeOut,   // 1.0 -> 1.15 (snappy pop out)
            easeInOut, // 1.15 -> 0.94 (spring overshoot back)
            easeInOut, // 0.94 -> 1.05 (settling up)
            easeInOut, // 1.05 -> 1.0 (settling down)
            linear,    // 1.0 -> 1.0 (hold)
            linear     // 1.0 -> 1.0 (hold)
        ]
        layer.add(scale, forKey: motionKey)
    }

    private static func applyBounce(to layer: CALayer) {
        // Translation Y (vertical jump motion)
        let ty = CAKeyframeAnimation(keyPath: "transform.translation.y")
        ty.values = [
            0,      // Start
            0,      // Pre-launch compression
            -20,    // Ascent
            -26,    // Peak airtime
            -12,    // Descent
            0,      // Impact landing
            0,      // Bounce settle
            0       // Rest hold
        ]
        ty.keyTimes = [
            0.0,
            0.12,
            0.28,
            0.42,
            0.56,
            0.70,
            0.85,
            1.0
        ]

        // Scale X (horizontal squash and stretch)
        let sx = CAKeyframeAnimation(keyPath: "transform.scale.x")
        sx.values = [
            1.0,    // Start
            1.12,   // Pre-launch squash (widens)
            0.90,   // Ascent stretch (narrows)
            1.00,   // Peak (reforms)
            0.92,   // Descent stretch (narrows)
            1.15,   // Landing squash (absorbs impact)
            0.98,   // Settle
            1.00    // Rest hold
        ]
        sx.keyTimes = ty.keyTimes

        // Scale Y (vertical squash and stretch)
        let sy = CAKeyframeAnimation(keyPath: "transform.scale.y")
        sy.values = [
            1.0,    // Start
            0.86,   // Pre-launch squash (compresses)
            1.14,   // Ascent stretch (extends)
            1.00,   // Peak (reforms)
            1.10,   // Descent stretch (extends)
            0.83,   // Landing squash (absorbs impact)
            1.02,   // Settle
            1.00    // Rest hold
        ]
        sy.keyTimes = ty.keyTimes

        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let easeIn = CAMediaTimingFunction(name: .easeIn)

        let timingFunctions = [
            easeInOut, // Start -> squash
            easeOut,   // Squash -> launch
            easeInOut, // Ascent -> peak
            easeIn,    // Peak -> descent
            easeIn,    // Descent -> landing
            easeInOut, // Landing -> settle
            easeInOut  // Settle -> rest
        ]

        ty.timingFunctions = timingFunctions
        sx.timingFunctions = timingFunctions
        sy.timingFunctions = timingFunctions

        let group = CAAnimationGroup()
        group.animations = [ty, sx, sy]
        group.duration = 1.3
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: motionKey)
    }

    private static func applyWave(to layer: CALayer) {
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [0, 0.06, -0.06, 0.04, 0]
        rotation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        rotation.duration = 1.2
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false

        let ty = CAKeyframeAnimation(keyPath: "transform.translation.y")
        ty.values = [0, -4, 4, -2, 0]
        ty.keyTimes = rotation.keyTimes
        ty.duration = rotation.duration
        ty.repeatCount = .infinity
        ty.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [rotation, ty]
        group.duration = rotation.duration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: motionKey)
    }

    private static func applySparkle(to layer: CALayer) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1.0, 0.65, 1.0, 0.78, 1.0]
        opacity.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        opacity.duration = 1.0
        opacity.repeatCount = .infinity
        opacity.isRemovedOnCompletion = false

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.07, 1.0, 1.04, 1.0]
        scale.keyTimes = opacity.keyTimes
        scale.duration = opacity.duration
        scale.repeatCount = .infinity
        scale.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = opacity.duration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: motionKey)
    }

    private static func applyTypewriter(to view: UIView) {
        let layer = view.layer
        guard layer.bounds.width > 1, layer.bounds.height > 1 else { return }

        // Find the visible text character count
        var textLength = 10
        for subview in view.subviews {
            if let label = subview as? UILabel, !label.isHidden {
                if let text = label.text, !text.isEmpty {
                    textLength = text.count
                    break
                }
            }
        }

        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 0.5)
        mask.position = CGPoint(x: 0, y: layer.bounds.midY)
        mask.bounds = CGRect(x: 0, y: 0, width: 0, height: layer.bounds.height)
        layer.mask = mask

        let N = max(1, textLength)
        // Add hold steps at the end (about 25-30% of the total duration) to pause on full word
        let M = max(2, N / 3)
        let totalSteps = N + M

        var values: [CGFloat] = []
        var keyTimes: [NSNumber] = []

        // Typing phase (discrete steps)
        for i in 0...N {
            values.append(layer.bounds.width * CGFloat(i) / CGFloat(N))
            keyTimes.append(NSNumber(value: Double(i) / Double(totalSteps)))
        }

        // Holding phase
        for j in 1...M {
            values.append(layer.bounds.width)
            keyTimes.append(NSNumber(value: Double(N + j) / Double(totalSteps)))
        }

        let reveal = CAKeyframeAnimation(keyPath: "bounds.size.width")
        reveal.values = values
        reveal.keyTimes = keyTimes
        reveal.calculationMode = .discrete
        reveal.duration = max(1.2, Double(N) * 0.15) // snapper speed per character
        reveal.repeatCount = .infinity
        reveal.autoreverses = true
        reveal.isRemovedOnCompletion = false
        mask.add(reveal, forKey: motionKey)
    }

    private static func applyReveal(to layer: CALayer) {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.2
        opacity.toValue = 1.0
        opacity.duration = 0.65
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        opacity.isRemovedOnCompletion = false
        layer.add(opacity, forKey: motionKey)
    }
}
