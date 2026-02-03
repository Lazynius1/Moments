import Foundation
import UIKit
import AVFoundation
import FirebaseFirestore

// MARK: - MediaModerationService.swift
// Sistema avanzado de moderación con múltiples frames + análisis de audio
// 🔥 OPTIMIZADO PARA NO BLOQUEAR LA UI

enum ModerationCategory: String {
    case adult = "adult"
    case violence = "violence"
    case racy = "racy"
    case medical = "medical"
    case spoofed = "spoofed"
    case clean = "clean"
    case audioToxic = "audio_toxic"
    case systemError = "system_error"
}

// MARK: - Tipo de contenido para moderación
enum ContentType: String {
    case moment = "moment"
    case story = "story"
}

// MARK: - 🔥 NUEVOS TIPOS PARA MODERACIÓN AVANZADA
enum MediaModerationAction: Equatable {
    case approved
    case deleted(reason: String, category: String)
    case warning(reason: String, category: String)
    case error(String)

    static func == (lhs: MediaModerationAction, rhs: MediaModerationAction) -> Bool {
        switch (lhs, rhs) {
        case (.approved, .approved): return true
        case (.error(let l), .error(let r)): return l == r
        case (.deleted(let lr, let lc), .deleted(let rr, let rc)): return lr == rr && lc == rc
        case (.warning(let lr, let lc), .warning(let rr, let rc)): return lr == rr && lc == rc
        default: return false
        }
    }
}

struct MediaModerationResult {
    let visualScore: Double
    let audioScore: Double?
    let combinedScore: Double
    let action: MediaModerationAction
    let details: [String: Any]
}

class MediaModerationService {
    static let shared = MediaModerationService()

    private let sightengineUser = "208616776"
    private let sightengineSecret = "tBgwREigE3caEC8UHEya9ZkpdUM5rtTd"
    private let sightengineBaseURL = "https://api.sightengine.com/1.0/check.json"
    
    // Mantenemos speech por si se usa en audio moderación, pero Sightengine también puede hacerlo
    private let speechAPIKey = "AIzaSyAfaYObVRF4G5Dk2ir2w7qMhhR57LaP-u4" 
    private let speechBaseURL = "https://speech.googleapis.com/v1/speech:recognize"
    
    // ✅ NUEVO: Queues dedicados para operaciones pesadas
    private let moderationQueue = DispatchQueue(label: "moderation.heavy.operations", qos: .background)
    private let concurrentQueue = DispatchQueue(label: "moderation.concurrent", qos: .background, attributes: .concurrent)
    
    // ✅ NUEVO: Control de operaciones en progreso
    private var activeModerationTasks: Set<String> = []
    private let taskLock = NSLock()

    private init() {}

    // MARK: - 🔥 FUNCIÓN PRINCIPAL: Moderación completamente en background
    func moderateMedia(
        mediaURL: String,
        mediaType: MediaType,
        userId: String,
        contentId: String? = nil,
        contentType: ContentType = .moment,
        completion: @escaping (MediaModerationAction) -> Void
    ) {
        
        // ✅ NUEVO: Crear task ID único para evitar duplicados
        let taskId = "\(userId)_\(contentId ?? UUID().uuidString)"
        
        taskLock.lock()
        if activeModerationTasks.contains(taskId) {
            taskLock.unlock()
            completion(.approved)
            return
        }
        activeModerationTasks.insert(taskId)
        taskLock.unlock()
        
        // ✅ TODA LA MODERACIÓN EN BACKGROUND
        moderationQueue.async { [weak self] in
            defer {
                self?.taskLock.lock()
                self?.activeModerationTasks.remove(taskId)
                self?.taskLock.unlock()
            }
            
            switch mediaType {
            case .image:
                self?.moderateImageAdvanced(url: mediaURL, userId: userId, contentId: contentId, contentType: contentType, completion: completion)
            case .video:
                self?.moderateVideoAdvanced(url: mediaURL, userId: userId, contentId: contentId, contentType: contentType, completion: completion)
            }
        }
    }

    // MARK: - 📸 MODERACIÓN AVANZADA DE IMÁGENES (OPTIMIZADA)
    private func moderateImageAdvanced(
        url: String,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationAction) -> Void
    ) {
        downloadImageForAnalysis(from: url) { [weak self] result in
            switch result {
            case .success(let imageData):

                // ✅ ANÁLISIS EN BACKGROUND CONCURRENTE
                self?.concurrentQueue.async {
                    self?.analyzeImageWithVisionAdvanced(
                        imageData: imageData,
                        originalURL: url,
                        userId: userId,
                        contentId: contentId,
                        contentType: contentType,
                        completion: { action in
                            if let contentId = contentId {
                                switch action {
                                case .deleted, .warning:
                                    self?.hideContentUsingOnlyMe(
                                        userId: userId,
                                        contentId: contentId,
                                        contentType: contentType,
                                        action: action,
                                        mediaURL: url,
                                        mediaType: "image"
                                    )
                                    DispatchQueue.main.async {
                                        completion(.approved)
                                    }
                                    return
                                default:
                                    break
                                }
                            }
                            DispatchQueue.main.async {
                                completion(action)
                            }
                        }
                    )
                }

            case .failure(let error):
                self?.logModerationEvent(
                    userId: userId,
                    mediaURL: url,
                    mediaType: "image",
                    contentType: contentType.rawValue,
                    action: "moderation_error",
                    reason: "Error descargando imagen: \(error.localizedDescription)",
                    category: "system_error",
                    contentId: contentId
                )
                DispatchQueue.main.async {
                    completion(.approved) // ✅ En caso de error, aprobar para no bloquear
                }
            }
        }
    }

    // MARK: - 🎥 MODERACIÓN AVANZADA DE VIDEOS (OPTIMIZADA)
    private func moderateVideoAdvanced(
        url: String,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationAction) -> Void
    ) {

        getVideoDuration(from: url) { [weak self] duration in
            guard let duration = duration else {
                self?.logModerationEvent(
                    userId: userId,
                    mediaURL: url,
                    mediaType: "video",
                    contentType: contentType.rawValue,
                    action: "moderation_error",
                    reason: "No se pudo obtener duración del video",
                    category: "system_error",
                    contentId: contentId
                )
                DispatchQueue.main.async {
                    completion(.approved) // ✅ En caso de error, aprobar
                }
                return
            }


            // ✅ EXTRACCIÓN DE FRAMES EN BACKGROUND
            self?.concurrentQueue.async {
                self?.extractSmartFrames(from: url, duration: duration) { framesResult in
                    switch framesResult {
                    case .success(let frames):

                        // ✅ ANÁLISIS EN BACKGROUND CONCURRENTE
                        self?.analyzeMultipleFrames(
                            frames: frames,
                            originalURL: url,
                            userId: userId,
                            contentId: contentId,
                            contentType: contentType
                        ) { visualResult in
                            // ✅ AUDIO ANÁLISIS SIMPLIFICADO (OPCIONAL)
                            if duration > 5.0 {
                                self?.extractAndAnalyzeAudioLightweight(
                                    from: url,
                                    duration: duration,
                                    userId: userId,
                                    contentId: contentId,
                                    contentType: contentType
                                ) { audioResult in
                                    let finalResult = self?.combineResults(
                                        visual: visualResult,
                                        audio: audioResult,
                                        mediaURL: url,
                                        userId: userId,
                                        contentId: contentId,
                                        contentType: contentType
                                    )

                                    self?.handleModerationResult(
                                        result: finalResult,
                                        userId: userId,
                                        contentId: contentId,
                                        contentType: contentType,
                                        mediaURL: url,
                                        completion: completion
                                    )
                                }
                            } else {
                                // ✅ Videos cortos: solo análisis visual
                                self?.handleModerationResult(
                                    result: visualResult,
                                    userId: userId,
                                    contentId: contentId,
                                    contentType: contentType,
                                    mediaURL: url,
                                    completion: completion
                                )
                            }
                        }

                    case .failure(let error):
                        self?.logModerationEvent(
                            userId: userId,
                            mediaURL: url,
                            mediaType: "video",
                            contentType: contentType.rawValue,
                            action: "moderation_error",
                            reason: "Error extrayendo frames: \(error.localizedDescription)",
                            category: "system_error",
                            contentId: contentId
                        )
                        DispatchQueue.main.async {
                            completion(.approved) // ✅ En caso de error, aprobar
                        }
                    }
                }
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Manejar resultado de moderación
    private func handleModerationResult(
        result: MediaModerationResult?,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        mediaURL: String,
        completion: @escaping (MediaModerationAction) -> Void
    ) {
        guard let finalResult = result else {
            DispatchQueue.main.async {
                completion(.approved)
            }
            return
        }
        
        if let contentId = contentId {
            switch finalResult.action {
            case .deleted, .warning:
                hideContentUsingOnlyMe(
                    userId: userId,
                    contentId: contentId,
                    contentType: contentType,
                    action: finalResult.action,
                    mediaURL: mediaURL,
                    mediaType: "video",
                    visualScore: finalResult.visualScore,
                    audioScore: finalResult.audioScore,
                    combinedScore: finalResult.combinedScore,
                    details: finalResult.details
                )
                DispatchQueue.main.async {
                    completion(.approved)
                }
                return
            default:
                break
            }
        }

        DispatchQueue.main.async {
            completion(finalResult.action)
        }
    }

    // MARK: - ⏱️ OBTENER DURACIÓN DEL VIDEO (SIN CAMBIOS)
    private func getVideoDuration(from urlString: String, completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        let asset = AVAsset(url: url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)
                DispatchQueue.main.async {
                    completion(durationInSeconds)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - 🎯 EXTRACCIÓN INTELIGENTE DE FRAMES (OPTIMIZADA)
    private func extractSmartFrames(
        from urlString: String,
        duration: Double,
        completion: @escaping (Result<[(Data, Double)], Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // ✅ REDUCIDO para mayor velocidad

        // ✅ REDUCIR NÚMERO DE FRAMES para mayor velocidad
        var timesToExtract: [(CMTime, Double)] = []
        
        if duration <= 10 {
            // Videos cortos: solo 1 frame
            let time = CMTime(seconds: duration / 2, preferredTimescale: 600)
            timesToExtract.append((time, duration / 2))
        } else if duration <= 30 {
            // Videos medianos: 2 frames
            for i in [5.0, duration / 2].prefix(2) {
                let time = CMTime(seconds: i, preferredTimescale: 600)
                timesToExtract.append((time, i))
            }
        } else {
            // Videos largos: 3 frames máximo
            for i in [5.0, duration / 2, duration - 5.0].prefix(3) {
                let time = CMTime(seconds: i, preferredTimescale: 600)
                timesToExtract.append((time, i))
            }
        }


        let group = DispatchGroup()
        var extractedFrames: [(Data, Double)] = []
        var errors: [Error] = []

        for (time, timestamp) in timesToExtract {
            group.enter()
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                defer { group.leave() }
                if let error = error {
                    errors.append(error)
                    return
                }
                guard let cgImage = cgImage else { return }
                let uiImage = UIImage(cgImage: cgImage)
                // ✅ MAYOR COMPRESIÓN para mayor velocidad
                guard let imageData = uiImage.jpegData(compressionQuality: 0.5) else { return }
                extractedFrames.append((imageData, timestamp))
            }
        }

        group.notify(queue: .global(qos: .background)) {
            if extractedFrames.isEmpty && !errors.isEmpty {
                completion(.failure(errors.first!))
            } else {
                extractedFrames.sort { $0.1 < $1.1 }
                completion(.success(extractedFrames))
            }
        }
    }

    // MARK: - 🖼️ ANÁLISIS DE MÚLTIPLES FRAMES (OPTIMIZADA)
    private func analyzeMultipleFrames(
        frames: [(Data, Double)],
        originalURL: String,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationResult) -> Void
    ) {

        let group = DispatchGroup()
        var visionResults: [(Double, [String: Any])] = []

        for (frameData, timestamp) in frames {
            group.enter()
            
            // ✅ ANÁLISIS CONCURRENTE
            concurrentQueue.async {
                self.analyzeFrameWithVision(frameData: frameData, timestamp: timestamp) { result in
                    defer { group.leave() }
                    if let safeSearchData = result {
                        visionResults.append((timestamp, safeSearchData))
                    }
                }
            }
        }

        group.notify(queue: .global(qos: .background)) {
            let combinedResult = self.combineFrameResults(visionResults)
            DispatchQueue.main.async {
                completion(combinedResult)
            }
        }
    }

    // MARK: - 🖼️ ANÁLISIS DE UN FRAME CON VISION (OPTIMIZADA)
    private func analyzeFrameWithVision(
        frameData: Data,
        timestamp: Double,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        // Sightengine prefiere multipart/form-data para imágenes
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: sightengineBaseURL) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        
        // Parámetros
        let parameters = [
            "api_user": sightengineUser,
            "api_secret": sightengineSecret,
            "models": "nudity-2.1,face-attributes,scam,offensive"
        ]
        
        for (key, value) in parameters {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Imagen
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(frameData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        request.timeoutInterval = 20.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil)
                return
            }

            guard let data = data else {
                completion(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let status = json["status"] as? String, status == "failure" {
                        completion(nil)
                        return
                    }
                    completion(json)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }

    // MARK: - 🎵 EXTRACCIÓN Y ANÁLISIS DE AUDIO LIGERO (NUEVO)
    private func extractAndAnalyzeAudioLightweight(
        from urlString: String,
        duration: Double,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationResult?) -> Void
    ) {

        // ✅ SOLO ANALIZAR AUDIO SI EL VIDEO ES LARGO
        guard duration > 10.0 else {
            completion(nil)
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        // ✅ ANÁLISIS DE AUDIO MÁS LIGERO
        extractAudioSegmentsLightweight(from: url, duration: min(duration, 15.0)) { [weak self] audioResult in
            switch audioResult {
            case .success(let audioData):

                self?.convertAudioToText(audioData: audioData) { textResult in
                    switch textResult {
                    case .success(let transcript):

                        Task {
                            do {
                                let commentModerationResult = try await CommentModerationService.shared.moderateComment(transcript)
                                let mediaModerationAction: MediaModerationAction
                                switch commentModerationResult {
                                case .approved:
                                    mediaModerationAction = .approved
                                case .warning(let reason, let category):
                                    mediaModerationAction = .warning(reason: reason, category: category)
                                case .rejected(let reason, let category):
                                    mediaModerationAction = .deleted(reason: reason, category: category)
                                }

                                let audioScore = self?.calculateAudioScore(from: mediaModerationAction) ?? 0.0
                                let result = MediaModerationResult(
                                    visualScore: 0.0,
                                    audioScore: audioScore,
                                    combinedScore: audioScore,
                                    action: mediaModerationAction,
                                    details: ["transcript": transcript]
                                )

                                completion(result)
                            } catch {
                                completion(nil)
                            }
                        }

                    case .failure(let error):
                        completion(nil)
                    }
                }

            case .failure(let error):
                completion(nil)
            }
        }
    }

    // MARK: - 🎵 EXTRAER SEGMENTOS DE AUDIO LIGERO (NUEVO)
    private func extractAudioSegmentsLightweight(
        from url: URL,
        duration: Double,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let asset = AVAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let audioFileName = "audio_\(UUID().uuidString).m4a"
        let audioURL = tempDir.appendingPathComponent(audioFileName)

        if FileManager.default.fileExists(atPath: audioURL.path) {
            do {
                try FileManager.default.removeItem(at: audioURL)
            } catch {
            }
        }

        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a
        // ✅ EXTRAER MENOS AUDIO para mayor velocidad
        let extractDuration = min(10.0, duration) // Máximo 10 segundos
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: extractDuration, preferredTimescale: 600)
        )
        exportSession.timeRange = timeRange


        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                do {
                    let audioData = try Data(contentsOf: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                    completion(.success(audioData))
                } catch {
                    completion(.failure(error))
                }

            case .failed, .cancelled:
                let error = exportSession.error ?? StorageError.invalidData
                try? FileManager.default.removeItem(at: audioURL)
                completion(.failure(error))
            default:
                break
            }
        }
    }

    // MARK: - 🗣️ CONVERTIR AUDIO A TEXTO (SIN CAMBIOS PERO CON TIMEOUT)
    private func convertAudioToText(
        audioData: Data,
        completion: @escaping (Result<String, Error>) -> Void
    ) {

        let base64Audio = audioData.base64EncodedString()
        let requestBody: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 44100,
                "languageCode": "es-ES",
                "enableAutomaticPunctuation": true,
                "model": "latest_short"
            ],
            "audio": [
                "content": base64Audio
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "\(speechBaseURL)?key=\(speechAPIKey)") else {
            completion(.failure(StorageError.invalidData))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15.0 // ✅ TIMEOUT REDUCIDO

        URLSession.shared.dataTask(with: request) { data, response, error in
            // ... (resto de la función igual)
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(StorageError.invalidData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(StorageError.invalidData))
                    return
                }

                if let errorJson = json["error"] as? [String: Any],
                   let errorMessage = errorJson["message"] as? String {
                    completion(.failure(NSError(domain: "SpeechToTextError", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    return
                }

                guard let results = json["results"] as? [[String: Any]],
                      let firstResult = results.first,
                      let alternatives = firstResult["alternatives"] as? [[String: Any]],
                      let firstAlternative = alternatives.first,
                      let transcript = firstAlternative["transcript"] as? String else {
                    completion(.success(""))
                    return
                }

                completion(.success(transcript))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - RESTO DE FUNCIONES (SIN CAMBIOS PERO MANTENIENDO NOMBRES ORIGINALES)
    
    private func combineFrameResults(_ results: [(Double, [String: Any])]) -> MediaModerationResult {
        guard !results.isEmpty else {
            return MediaModerationResult(
                visualScore: 0.0,
                audioScore: nil,
                combinedScore: 0.0,
                action: .approved,
                details: [:]
            )
        }

        var maxAdultScore = 0.0
        var maxViolenceScore = 0.0
        var problematicFrames: [String] = []
        var finalAction: MediaModerationAction = .approved

        for (timestamp, json) in results {
            // Parsing Sightengine Nudity
            if let nudity = json["nudity"] as? [String: Any] {
                let sexualDisplay = nudity["sexual_display"] as? Double ?? 0.0
                let sexualActivity = nudity["sexual_activity"] as? Double ?? 0.0
                let erotic = nudity["erotica"] as? Double ?? 0.0
                let sexting = nudity["sexting"] as? Double ?? 0.0
                
                // Estos son los que permitimos (Fitness y Swimwear)
                let fitness = nudity["fitness"] as? Double ?? 0.0
                let swimwear = nudity["swimwear"] as? Double ?? 0.0
                
                // Lógica "Modo Instagram": 
                // Si es fitness o swimwear, ignoramos si no hay contenido sexual explícito
                let combinedAdult = max(sexualDisplay, sexualActivity, erotic * 0.8, sexting)
                
                if combinedAdult > 0.90 {
                    finalAction = .deleted(reason: "Contenido sexual explícito detectado", category: "adult")
                    problematicFrames.append("\(Int(timestamp))s")
                } else if combinedAdult > 0.70 {
                    finalAction = .warning(reason: "Contenido sugerente", category: "adult")
                }
                
                maxAdultScore = max(maxAdultScore, combinedAdult)
            }
            
            // Parsing Scam/Fraud (El pájaro)
            if let scam = json["scam"] as? [String: Any] {
                let prob = scam["prob"] as? Double ?? 0.0
                // Solo bloqueamos si es extremadamente seguro que es un scam o falsificación
                if prob > 0.98 {
                    finalAction = .deleted(reason: "Posible fraude o falsificación", category: "scam")
                }
            }

            // Parsing Offensive/Hate
            if let offensive = json["offensive"] as? [String: Any] {
                let prob = offensive["prob"] as? Double ?? 0.0
                if prob > 0.90 {
                    finalAction = .deleted(reason: "Contenido ofensivo detectado", category: "offensive")
                }
            }
        }

        let visualScore = maxAdultScore
        
        return MediaModerationResult(
            visualScore: visualScore,
            audioScore: nil,
            combinedScore: visualScore,
            action: finalAction,
            details: [
                "frames_analyzed": results.count,
                "problematic_frames": problematicFrames,
                "provider": "sightengine"
            ]
        )
    }

    private func combineResults(
        visual: MediaModerationResult,
        audio: MediaModerationResult?,
        mediaURL: String,
        userId: String,
        contentId: String?,
        contentType: ContentType
    ) -> MediaModerationResult {
        let visualScore = visual.visualScore
        let audioScore = audio?.audioScore ?? 0.0
        let combinedScore = (visualScore * 0.7) + (audioScore * 0.3)
        let finalAction = determineFinalAction(visual: visual.action, audio: audio?.action)

        var combinedDetails = visual.details
        if let audioDetails = audio?.details {
            combinedDetails.merge(audioDetails) { (current, _) in current }
        }
        combinedDetails["combined_score"] = combinedScore
        combinedDetails["final_action_reason"] = getReasonFromAction(finalAction)
        combinedDetails["final_action_category"] = getCategoryFromAction(finalAction)

        logAdvancedModerationEvent(
            userId: userId,
            mediaURL: mediaURL,
            mediaType: "video",
            contentType: contentType.rawValue,
            action: actionToString(finalAction),
            visualScore: visualScore,
            audioScore: audioScore,
            combinedScore: combinedScore,
            details: combinedDetails,
            contentId: contentId
        )

        return MediaModerationResult(
            visualScore: visualScore,
            audioScore: audioScore,
            combinedScore: combinedScore,
            action: finalAction,
            details: combinedDetails
        )
    }

    private func scoreFromLevel(_ level: String?) -> Double {
        switch level {
        case "VERY_LIKELY": return 1.0
        case "LIKELY": return 0.8
        case "POSSIBLE": return 0.5
        case "UNLIKELY": return 0.2
        case "VERY_UNLIKELY": return 0.1
        default: return 0.0
        }
    }

    private func calculateAudioScore(from action: MediaModerationAction) -> Double {
        switch action {
        case .deleted: return 1.0
        case .warning: return 0.6
        case .approved: return 0.1
        case .error: return 0.0
        }
    }

    private func determineActionFromScores(adult: Double, violence: Double, racy: Double) -> MediaModerationAction {
        var result: MediaModerationAction = .approved
        let group = DispatchGroup()
        group.enter()
        determineActionFromScoresWithConfig(adult: adult, violence: violence, racy: racy) { action in
            result = action
            group.leave()
        }
        group.wait()
        return result
    }

    private func determineFinalAction(visual: MediaModerationAction, audio: MediaModerationAction?) -> MediaModerationAction {
        let actions = [visual, audio].compactMap { $0 }
        if actions.contains(where: { if case .deleted = $0 { return true } else { return false } }) {
            if let deletedAction = actions.first(where: { if case .deleted = $0 { return true } else { return false } }) {
                return deletedAction
            }
        }
        if actions.contains(where: { if case .warning = $0 { return true } else { return false } }) {
            if let warningAction = actions.first(where: { if case .warning = $0 { return true } else { return false } }) {
                return warningAction
            }
        }
        if actions.contains(where: { if case .error = $0 { return true } else { return false } }) {
            if let errorAction = actions.first(where: { if case .error = $0 { return true } else { return false } }) {
                return errorAction
            }
        }
        return .approved
    }

    private func actionToString(_ action: MediaModerationAction) -> String {
        switch action {
        case .approved: return "approved"
        case .deleted: return "auto_deleted_silent"
        case .warning: return "flagged_for_review"
        case .error: return "moderation_error"
        }
    }

    private func analyzeImageWithVisionAdvanced(
        imageData: Data,
        originalURL: String,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationAction) -> Void
    ) {
        analyzeFrameWithVision(frameData: imageData, timestamp: 0.0) { [weak self] json in
            guard let json = json else {
                let errorAction: MediaModerationAction = .error("Error analizando imagen con Sightengine")
                completion(errorAction)
                return
            }

            let result = self?.analyzeSightengineResult(json) ?? .approved
            
            self?.logModerationEvent(
                userId: userId,
                mediaURL: originalURL,
                mediaType: "image",
                contentType: contentType.rawValue,
                action: self?.actionToString(result) ?? "approved",
                reason: self?.getReasonFromAction(result) ?? "Contenido analizado",
                category: self?.getCategoryFromAction(result) ?? "clean",
                contentId: contentId,
                visionData: ["provider": "sightengine"] // Simplificado para el log
            )

            completion(result)
        }
    }

    private func analyzeSightengineResult(_ json: [String: Any]) -> MediaModerationAction {
        // Usamos la misma lógica que combineFrameResults pero para una sola imagen
        let result = combineFrameResults([(0.0, json)])
        return result.action
    }

    private func getReasonFromAction(_ action: MediaModerationAction) -> String {
        switch action {
        case .deleted(let reason, _): return reason
        case .warning(let reason, _): return reason
        case .approved: return "Contenido apropiado"
        case .error(let error): return error
        }
    }

    private func getCategoryFromAction(_ action: MediaModerationAction) -> String {
        switch action {
        case .deleted(_, let category): return category
        case .warning(_, let category): return category
        case .approved: return "clean"
        case .error: return "system_error"
        }
    }

    private func downloadImageForAnalysis(from urlString: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(StorageError.invalidData))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0 // ✅ TIMEOUT REDUCIDO

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(StorageError.invalidData))
                return
            }

            completion(.success(data))
        }.resume()
    }

    private func logModerationEvent(
        userId: String,
        mediaURL: String,
        mediaType: String,
        contentType: String,
        action: String,
        reason: String,
        category: String,
        contentId: String?,
        visionData: [String: String]? = nil
    ) {
        // ✅ LOGGING EN BACKGROUND
        DispatchQueue.global(qos: .utility).async {
            let db = Firestore.firestore()
            var logData: [String: Any] = [
                "userId": userId,
                "mediaURL": mediaURL,
                "mediaType": mediaType,
                "contentType": contentType,
                "action": action,
                "reason": reason,
                "category": category,
                "timestamp": FieldValue.serverTimestamp()
            ]

            if let contentId = contentId {
                logData["contentId"] = contentId
            }

            if let visionData = visionData {
                logData["visionData"] = visionData
            }

            db.collection("mediaModerationLogs").addDocument(data: logData) { error in
                if let error = error {
                } else {
                }
            }
        }
    }

    private func logAdvancedModerationEvent(
        userId: String,
        mediaURL: String,
        mediaType: String,
        contentType: String,
        action: String,
        visualScore: Double,
        audioScore: Double,
        combinedScore: Double,
        details: [String: Any],
        contentId: String?
    ) {
        // ✅ LOGGING EN BACKGROUND
        DispatchQueue.global(qos: .utility).async {
            let db = Firestore.firestore()
            var logData: [String: Any] = [
                "userId": userId,
                "mediaURL": mediaURL,
                "mediaType": mediaType,
                "contentType": contentType,
                "action": action,
                "visualScore": visualScore,
                "audioScore": audioScore,
                "combinedScore": combinedScore,
                "details": details,
                "timestamp": FieldValue.serverTimestamp()
            ]

            if let contentId = contentId {
                logData["contentId"] = contentId
            }

            db.collection("mediaModerationLogs").addDocument(data: logData) { error in
                if let error = error {
                } else {
                }
            }
        }
    }

    private func hideContentUsingOnlyMe(
        userId: String,
        contentId: String,
        contentType: ContentType,
        action: MediaModerationAction,
        mediaURL: String,
        mediaType: String,
        visualScore: Double? = nil,
        audioScore: Double? = nil,
        combinedScore: Double? = nil,
        details: [String: Any] = [:]
    ) {
        // ✅ OCULTAR CONTENIDO EN BACKGROUND
        DispatchQueue.global(qos: .utility).async {
            let db = Firestore.firestore()
            let collectionName = contentType == .moment ? "moments" : "stories"
            let contentRef = db.collection("users").document(userId).collection(collectionName).document(contentId)

            contentRef.getDocument { document, error in
                guard let document = document, document.exists,
                      let contentData = document.data() else {
                    return
                }

                let originalAudience = contentData["audience"] as? String ?? "everyone"
                var hideData: [String: Any] = [
                    "audience": "onlyMe",
                    "moderatedAt": FieldValue.serverTimestamp(),
                    "moderatedBy": "auto_moderation",
                    "originalAudience": originalAudience,
                    "isModerationHidden": true,
                    "reviewRequired": true,
                    "canRestore": true
                ]

                switch action {
                case .deleted(let reason, let category):
                    hideData["moderationReason"] = reason
                    hideData["moderationCategory"] = category
                    hideData["confidence"] = self.determineConfidence(
                        visualScore: visualScore ?? 0.0,
                        audioScore: audioScore ?? 0.0,
                        combinedScore: combinedScore ?? 0.0
                    )
                case .warning(let reason, let category):
                    hideData["moderationReason"] = "Advertencia: \(reason)"
                    hideData["moderationCategory"] = category
                    hideData["confidence"] = "medium"
                default:
                    hideData["moderationReason"] = "Contenido flagged por moderación automática"
                    hideData["moderationCategory"] = "general"
                    hideData["confidence"] = "unknown"
                }

                hideData["moderationDetails"] = details
                hideData["originalMediaURL"] = mediaURL
                hideData["mediaType"] = mediaType

                if let visualScore = visualScore { hideData["visualScore"] = visualScore }
                if let audioScore = audioScore { hideData["audioScore"] = audioScore }
                if let combinedScore = combinedScore { hideData["combinedScore"] = combinedScore }

                contentRef.updateData(hideData) { error in
                    if let error = error {
                    } else {
                    }
                }
            }
        }
    }

    private func determineConfidence(visualScore: Double, audioScore: Double, combinedScore: Double) -> String {
        let maxScore = max(visualScore, audioScore, combinedScore)
        if maxScore >= 0.9 {
            return "very_high"
        } else if maxScore >= 0.7 {
            return "high"
        } else if maxScore >= 0.5 {
            return "medium"
        } else if maxScore >= 0.3 {
            return "low"
        } else {
            return "very_low"
        }
    }

    private func loadModerationSettings(completion: @escaping ([String: Any]?) -> Void) {
        let db = Firestore.firestore()
        db.collection("moderationSettings").document("media").getDocument { document, error in
            if let error = error {
                completion(nil)
                return
            }
            if let document = document, document.exists, let data = document.data() {
                completion(data)
            } else {
                completion(nil)
            }
        }
    }

    private func determineActionFromScoresWithConfig(adult: Double, violence: Double, racy: Double, completion: @escaping (MediaModerationAction) -> Void) {
        loadModerationSettings { [weak self] config in
            // ✅ UMBRALES EQUILIBRADOS Y MÁS TOLERANTES
            // Modificado para permitir fotos "racy" (sin camiseta, playa, fitness) y evitar falsos positivos con pájaros (spoofed)
            let deleteThresholds = config?["deleteThresholds"] as? [String: Double] ?? [
                "adult": 0.95,     // Muy estricto: Solo desnudez explícita
                "violence": 0.85,  // Solo violencia gráfica extrema
                "racy": 0.99,      // Prácticamente deshabilitado para borrar
                "medical": 0.95,   // Solo contenido médico explícito
                "spoofed": 0.99    // Evitar que detecte animales/pájaros como falsos
            ]

            let warningThresholds = config?["warningThresholds"] as? [String: Double] ?? [
                "adult": 0.90,     // Advertencia solo si es casi seguro (VERY_LIKELY)
                "violence": 0.80,  
                "racy": 0.98,      // Deshabilitado en la práctica
                "medical": 0.90,   
                "spoofed": 0.95    
            ]

            // 1. ADULT CONTENT
            if adult >= deleteThresholds["adult"]! {
                completion(.deleted(reason: "Contenido adulto explícito detectado", category: ModerationCategory.adult.rawValue))
                return
            }
            if adult >= warningThresholds["adult"]! {
                completion(.warning(reason: "Contenido potencialmente adulto", category: ModerationCategory.adult.rawValue))
                return
            }

            // 2. VIOLENCE
            if violence >= deleteThresholds["violence"]! {
                completion(.deleted(reason: "Contenido violento extremo detectado", category: ModerationCategory.violence.rawValue))
                return
            }
            if violence >= warningThresholds["violence"]! {
                completion(.warning(reason: "Contenido potencialmente violento", category: ModerationCategory.violence.rawValue))
                return
            }

            // 3. SPOOFED (El problema de los pájaros/animales)
            // Solo actuar si es una falsificación extremadamente evidente
            if racy >= deleteThresholds["spoofed"]! {
                completion(.deleted(reason: "Contenido falsificado detectado", category: ModerationCategory.spoofed.rawValue))
                return
            }

            // ✅ RACY está deshabilitado intencionadamente para permitir fotos de perfil fitness/playa
            
            completion(.approved)
        }
    }

    // ✅ MANTENER FUNCIÓN ORIGINAL PARA COMPATIBILIDAD
    private func extractAndAnalyzeAudio(
        from urlString: String,
        duration: Double,
        userId: String,
        contentId: String?,
        contentType: ContentType,
        completion: @escaping (MediaModerationResult?) -> Void
    ) {
        // ✅ REDIGIR A LA VERSIÓN LIGERA
        extractAndAnalyzeAudioLightweight(
            from: urlString,
            duration: duration,
            userId: userId,
            contentId: contentId,
            contentType: contentType,
            completion: completion
        )
    }

    // ✅ MANTENER FUNCIÓN ORIGINAL PARA COMPATIBILIDAD
    private func extractAudioSegments(
        from url: URL,
        duration: Double,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // ✅ REDIGIR A LA VERSIÓN LIGERA
        extractAudioSegmentsLightweight(from: url, duration: duration, completion: completion)
    }
}

// MARK: - UIImage Extension for Resizing (SIN CAMBIOS)
extension UIImage {
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let currentWidth = self.size.width
        let currentHeight = self.size.height
        var newWidth: CGFloat = 0
        var newHeight: CGFloat = 0

        if currentWidth > currentHeight {
            newWidth = min(currentWidth, maxDimension)
            newHeight = (newWidth / currentWidth) * currentHeight
        } else {
            newHeight = min(currentHeight, maxDimension)
            newWidth = (newHeight / currentHeight) * currentWidth
        }

        newWidth = max(1, newWidth)
        newHeight = max(1, newHeight)
        let newSize = CGSize(width: newWidth, height: newHeight)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? self
    }
}
