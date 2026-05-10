import Foundation
import CoreMotion
import UIKit

class OrientationManager: ObservableObject {
    @Published var orientation: UIDeviceOrientation = .portrait
    private let motionManager = CMMotionManager()
    private var lastValidOrientation: UIDeviceOrientation = .portrait
    private var activeConsumers = 0
    
    static let shared = OrientationManager()
    
    private init() {}
    
    func startTracking() {
        activeConsumers += 1
        guard activeConsumers == 1 else { return }
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.3
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let acceleration = data?.acceleration else { return }
            
            var newOrientation: UIDeviceOrientation = self?.lastValidOrientation ?? .portrait
            
            // Umbral para evitar cambios constantes con vibraciones leves
            let threshold = 0.6
            
            if acceleration.z < -0.85 {
                // El teléfono está casi plano hacia arriba, mantenemos la última orientación válida
                return
            }
            
            if abs(acceleration.x) > threshold {
                newOrientation = acceleration.x > 0 ? .landscapeRight : .landscapeLeft
            } else if abs(acceleration.y) > threshold {
                newOrientation = acceleration.y > 0 ? .portraitUpsideDown : .portrait
            }
            
            if newOrientation != self?.orientation && newOrientation.isValidInterfaceOrientation {
                self?.lastValidOrientation = newOrientation
                self?.orientation = newOrientation
            }
        }
    }
    
    func stopTracking() {
        activeConsumers = max(activeConsumers - 1, 0)
        guard activeConsumers == 0 else { return }
        motionManager.stopAccelerometerUpdates()
    }
}
