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
            applyTypewriter(to: view.layer)
        case .reveal:
            applyReveal(to: view.layer)
        case .none:
            break
        }

        _ = replayToken
    }

    private static func applyPop(to layer: CALayer) {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.78, 1.12, 0.97, 1.05, 1.0]
        scale.keyTimes = [0, 0.28, 0.5, 0.72, 1]
        scale.duration = 0.95
        scale.repeatCount = .infinity
        scale.isRemovedOnCompletion = false
        layer.add(scale, forKey: motionKey)
    }

    private static func applyBounce(to layer: CALayer) {
        let ty = CAKeyframeAnimation(keyPath: "transform.translation.y")
        ty.values = [0, -14, 2, -8, 0]
        ty.keyTimes = [0, 0.22, 0.45, 0.68, 1]
        ty.duration = 0.9
        ty.repeatCount = .infinity
        ty.isRemovedOnCompletion = false

        let sx = CAKeyframeAnimation(keyPath: "transform.scale.y")
        sx.values = [1.0, 0.92, 1.04, 0.98, 1.0]
        sx.keyTimes = ty.keyTimes
        sx.duration = ty.duration
        sx.repeatCount = .infinity
        sx.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [ty, sx]
        group.duration = ty.duration
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

    private static func applyTypewriter(to layer: CALayer) {
        guard layer.bounds.width > 1, layer.bounds.height > 1 else { return }

        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 0.5)
        mask.position = CGPoint(x: 0, y: layer.bounds.midY)
        mask.bounds = CGRect(x: 0, y: 0, width: 0, height: layer.bounds.height)
        layer.mask = mask

        let reveal = CABasicAnimation(keyPath: "bounds.size.width")
        reveal.fromValue = 0
        reveal.toValue = layer.bounds.width
        reveal.duration = max(1.2, Double(layer.bounds.width) / 90)
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
