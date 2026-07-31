import AVFoundation

// Centraliza AVAudioSession fuera del hilo principal: setCategory/setActive bloquean y
// en el main thread congelan la UI.
//
// Se usa `setActive` en lugar de los `activate`/`deactivate` asíncronos de iOS 27: esos
// símbolos no existen en SDKs anteriores, y `#available` solo comprueba en ejecución, así
// que el archivo no compilaba con el Xcode estable. Como aquí ya se llama desde una tarea
// aparte, que la API sea bloqueante da igual.
enum MomentsAudioSession {

    // Desactiva la sesión sin bloquear al llamante. Nada depende del resultado, así que
    // no hace falta esperarla. Siempre avisa a otras apps para que reanuden su audio.
    static func deactivate() {
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // Restaura la categoría que había antes y desactiva, fuera del main thread.
    // Para vistas que cambian la categoría temporalmente (p. ej. stickers de audio).
    static func restore(
        category: AVAudioSession.Category?,
        mode: AVAudioSession.Mode?,
        options: AVAudioSession.CategoryOptions
    ) {
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            if let category, let mode {
                try? session.setCategory(category, mode: mode, options: options)
            }

            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // Configura categoría y activa la sesión fuera del main thread. Hay que esperarla antes
    // de crear un AVAudioPlayer/AVAudioRecorder: si no, el I/O arranca con la sesión inactiva.
    @discardableResult
    static func activate(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode = .default,
        options: AVAudioSession.CategoryOptions = []
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) { () -> Bool in
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(category, mode: mode, options: options)
            } catch {
                return false
            }

            do {
                try session.setActive(true)
                return true
            } catch {
                return false
            }
        }.value
    }
}
