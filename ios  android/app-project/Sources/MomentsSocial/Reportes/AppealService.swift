import Foundation

// MARK: - Data Models
struct AppealRequest: Codable {
    let userId: String
    let appealMessage: String
    let additionalInfo: String?
    let contactEmail: String
    let deviceInfo: DeviceInfo
    let appVersion: String
}

struct DeviceInfo: Codable {
    let platform: String
    let version: String
    let model: String
}

struct AppealResponse: Codable {
    let success: Bool
    let appealId: String?
    let ticketNumber: String?
    let message: String?
    let estimatedResponseTime: String?
    let priority: String?
    let status: String?
    let error: String?
    let code: String?
    let currentLength: Int?
    let requiredLength: Int?
    let existingAppeal: ExistingAppeal?
    let nextSteps: [String]?
    let supportInfo: SupportInfo?
}

struct ExistingAppeal: Codable {
    let ticketNumber: String
    let status: String
    let submittedAt: String
}

struct SupportInfo: Codable {
    let email: String
    let responseTime: String
    let ticketNumber: String
}

// MARK: - Appeal Service
class AppealService: ObservableObject {
    static let shared = AppealService()
    
    // Configuración del servidor - cambiar según tu setup
    private let baseURL = "https://moment-admin-panel.vercel.app" // 🔧 CAMBIAR POR TU URL
    
    init() {}
    
    func submitAppeal(
        userId: String,
        message: String,
        email: String,
        additionalInfo: String? = nil
    ) async throws -> AppealResponse {
        
        // Validaciones básicas
        guard !userId.isEmpty else {
            throw AppealError.invalidUserId
        }
        
        guard !message.isEmpty else {
            throw AppealError.emptyMessage
        }
        
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 50 else {
            throw AppealError.messageTooShort(current: trimmedMessage.count, required: 50)
        }
        
        guard trimmedMessage.count <= 2000 else {
            throw AppealError.messageTooLong(current: trimmedMessage.count)
        }
        
        guard !email.isEmpty, email.contains("@") else {
            throw AppealError.invalidEmail
        }
        
        // Construir URL
        guard let url = URL(string: "\(baseURL)/api/appeals-create") else {
            throw AppealError.invalidURL
        }
        
        // Preparar device info
        let deviceInfo = DeviceInfo(
            platform: "iOS",
            version: UIDevice.current.systemVersion,
            model: UIDevice.current.model
        )
        
        // Preparar request body
        let appealRequest = AppealRequest(
            userId: userId,
            appealMessage: trimmedMessage,
            additionalInfo: additionalInfo?.isEmpty == false ? additionalInfo : nil,
            contactEmail: email,
            deviceInfo: deviceInfo,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        
        // Crear HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encodificar body
        do {
            request.httpBody = try JSONEncoder().encode(appealRequest)
        } catch {
            throw AppealError.encodingError
        }
        
        // Realizar petición
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Verificar respuesta HTTP
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppealError.invalidResponse
            }
            
            // Decodificar respuesta
            let appealResponse = try JSONDecoder().decode(AppealResponse.self, from: data)
            
            // Manejar códigos de estado HTTP
            switch httpResponse.statusCode {
            case 201:
                // Éxito
                return appealResponse
                
            case 400:
                // Error de validación
                if let code = appealResponse.code {
                    switch code {
                    case "MESSAGE_TOO_SHORT":
                        throw AppealError.messageTooShort(
                            current: appealResponse.currentLength ?? 0,
                            required: appealResponse.requiredLength ?? 50
                        )
                    case "MESSAGE_TOO_LONG":
                        throw AppealError.messageTooLong(current: appealResponse.currentLength ?? 0)
                    case "USER_NOT_SUSPENDED":
                        throw AppealError.userNotSuspended
                    case "MISSING_REQUIRED_FIELDS":
                        throw AppealError.validationError("Faltan campos requeridos")
                    case "TOO_MANY_ATTACHMENTS":
                        throw AppealError.validationError("Demasiados archivos adjuntos")
                    default:
                        throw AppealError.validationError(appealResponse.error ?? "Error de validación")
                    }
                } else {
                    throw AppealError.validationError(appealResponse.error ?? "Error de validación")
                }
                
            case 404:
                throw AppealError.userNotFound
                
            case 409:
                // Ya existe una apelación
                throw AppealError.appealAlreadyExists(
                    ticketNumber: appealResponse.existingAppeal?.ticketNumber ?? "Desconocido",
                    status: appealResponse.existingAppeal?.status ?? "unknown"
                )
                
            case 429:
                throw AppealError.rateLimited
                
            case 500:
                throw AppealError.serverError
                
            default:
                throw AppealError.httpError(statusCode: httpResponse.statusCode)
            }
            
        } catch let error as AppealError {
            throw error
        } catch {
            // Error de red o decodificación
            if error is DecodingError {
                throw AppealError.decodingError
            } else {
                throw AppealError.networkError(error.localizedDescription)
            }
        }
    }
}

// MARK: - Appeal Errors
enum AppealError: LocalizedError, Equatable {
    case invalidUserId
    case emptyMessage
    case messageTooShort(current: Int, required: Int)
    case messageTooLong(current: Int)
    case invalidEmail
    case invalidURL
    case encodingError
    case decodingError
    case invalidResponse
    case userNotFound
    case userNotSuspended
    case appealAlreadyExists(ticketNumber: String, status: String)
    case rateLimited
    case serverError
    case networkError(String)
    case validationError(String)
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidUserId:
            return "ID de usuario inválido"
        case .emptyMessage:
            return "El mensaje no puede estar vacío"
        case .messageTooShort(let current, let required):
            return "El mensaje debe tener al menos \(required) caracteres. Actualmente tiene \(current)."
        case .messageTooLong(let current):
            return "El mensaje es demasiado largo (\(current) caracteres). Máximo 2000 caracteres."
        case .invalidEmail:
            return "Debe proporcionar un email válido"
        case .invalidURL:
            return "Error de configuración de la aplicación"
        case .encodingError:
            return "Error al procesar los datos"
        case .decodingError:
            return "Error al procesar la respuesta del servidor"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .userNotFound:
            return "Usuario no encontrado en el sistema"
        case .userNotSuspended:
            return "Tu cuenta no está suspendida actualmente"
        case .appealAlreadyExists(let ticketNumber, let status):
            return "Ya tienes una apelación \(status): \(ticketNumber)"
        case .rateLimited:
            return "Has alcanzado el límite de apelaciones. Inténtalo más tarde."
        case .serverError:
            return "Error interno del servidor. Inténtalo más tarde."
        case .networkError(let message):
            return "Error de conexión: \(message)"
        case .validationError(let message):
            return message
        case .httpError(let statusCode):
            return "Error del servidor (código \(statusCode))"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .messageTooShort:
            return "Agrega más detalles sobre por qué consideras que la suspensión es incorrecta."
        case .messageTooLong:
            return "Reduce el mensaje a máximo 2000 caracteres."
        case .invalidEmail:
            return "Verifica que tu email tenga un formato válido (ej: usuario@ejemplo.com)."
        case .appealAlreadyExists:
            return "Puedes verificar el estado de tu apelación existente en Configuración."
        case .rateLimited:
            return "Espera un poco antes de intentar enviar otra apelación."
        case .networkError:
            return "Verifica tu conexión a internet e inténtalo de nuevo."
        case .serverError:
            return "El problema es temporal. Inténtalo en unos minutos."
        default:
            return "Si el problema persiste, contacta a soporte técnico."
        }
    }
}

// MARK: - Appeal Result
struct AppealResult {
    let success: Bool
    let ticketNumber: String?
    let message: String
    let estimatedResponseTime: String?
    let priority: String?
    let nextSteps: [String]
    
    init(from response: AppealResponse) {
        self.success = response.success
        self.ticketNumber = response.ticketNumber
        self.message = response.message ?? "Apelación procesada"
        self.estimatedResponseTime = response.estimatedResponseTime
        self.priority = response.priority
        self.nextSteps = response.nextSteps ?? []
    }
}


extension AppealService {
    
    // MARK: - Fetch User Appeals
    func fetchUserAppeals(userId: String) async throws -> [AppealStatus] {
        guard !userId.isEmpty else {
            throw AppealError.invalidUserId
        }
        
        // Construir URL
        guard let url = URL(string: "\(baseURL)/api/appeals-status?userId=\(userId)") else {
            throw AppealError.invalidURL
        }
        
        // Crear HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Realizar petición
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Verificar respuesta HTTP
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppealError.invalidResponse
            }
            
            // Decodificar respuesta
            switch httpResponse.statusCode {
            case 200:
                let appealsResponse = try JSONDecoder().decode(AppealsListResponse.self, from: data)
                return appealsResponse.appeals.map { AppealStatus(from: $0) }
                
            case 404:
                // No hay apelaciones - devolver array vacío
                return []
                
            case 400:
                let errorResponse = try? JSONDecoder().decode(AppealResponse.self, from: data)
                throw AppealError.validationError(errorResponse?.error ?? "Error de validación")
                
            case 500:
                throw AppealError.serverError
                
            default:
                throw AppealError.httpError(statusCode: httpResponse.statusCode)
            }
            
        } catch let error as AppealError {
            throw error
        } catch {
            if error is DecodingError {
                throw AppealError.decodingError
            } else {
                throw AppealError.networkError(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Fetch Single Appeal by Ticket
    func fetchAppealByTicket(ticketNumber: String) async throws -> AppealStatus {
        guard !ticketNumber.isEmpty else {
            throw AppealError.validationError("Número de ticket requerido")
        }
        
        // Construir URL
        guard let url = URL(string: "\(baseURL)/api/appeals-status?ticketNumber=\(ticketNumber)") else {
            throw AppealError.invalidURL
        }
        
        // Crear HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Realizar petición
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppealError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                let appealResponse = try JSONDecoder().decode(SingleAppealResponse.self, from: data)
                return AppealStatus(from: appealResponse.appeal)
                
            case 404:
                throw AppealError.validationError("Apelación no encontrada")
                
            case 400:
                let errorResponse = try? JSONDecoder().decode(AppealResponse.self, from: data)
                throw AppealError.validationError(errorResponse?.error ?? "Error de validación")
                
            case 500:
                throw AppealError.serverError
                
            default:
                throw AppealError.httpError(statusCode: httpResponse.statusCode)
            }
            
        } catch let error as AppealError {
            throw error
        } catch {
            if error is DecodingError {
                throw AppealError.decodingError
            } else {
                throw AppealError.networkError(error.localizedDescription)
            }
        }
    }
}

// MARK: - Additional Response Models
struct AppealsListResponse: Codable {
    let success: Bool
    let appeals: [AppealResponseData]
    let total: Int
    let summary: AppealsSummary
    let timestamp: String
}

struct SingleAppealResponse: Codable {
    let success: Bool
    let appeal: AppealResponseData
    let message: String
    let timestamp: String
}

struct AppealResponseData: Codable {
    let id: String
    let ticketNumber: String
    let status: String
    let priority: String
    let appealMessage: String
    let additionalInfo: String?
    let contactEmail: String
    let suspensionReason: String?
    let suspensionDate: String?
    let suspensionExpiry: String?
    let submittedAt: String
    let reviewedAt: String?
    let resolvedAt: String?
    let moderatorId: String?
    let moderatorNotes: String?
    let estimatedResponseTime: String
    let nextSteps: [String]
    let statusDescription: String
    let progress: AppealProgress?
    let timeline: [AppealTimelineEvent]?
}

struct AppealsSummary: Codable {
    let pending: Int
    let reviewing: Int
    let approved: Int
    let denied: Int
    let requires_info: Int
}

struct AppealProgress: Codable {
    let percentage: Int
    let currentStage: String
    let totalStages: Int
}

struct AppealTimelineEvent: Codable {
    let date: String
    let event: String
    let description: String
    let moderator: String?
}

// MARK: - AppealStatus Extension
extension AppealStatus {
    init(from response: AppealResponseData) {
        self.id = response.id
        self.ticketNumber = response.ticketNumber
        self.status = response.status
        self.priority = response.priority
        self.appealMessage = response.appealMessage
        self.additionalInfo = response.additionalInfo
        self.contactEmail = response.contactEmail
        self.suspensionReason = response.suspensionReason
        self.suspensionDate = response.suspensionDate
        self.suspensionExpiry = response.suspensionExpiry
        self.submittedAt = response.submittedAt
        self.reviewedAt = response.reviewedAt
        self.resolvedAt = response.resolvedAt
        self.moderatorId = response.moderatorId
        self.moderatorNotes = response.moderatorNotes
        self.estimatedResponseTime = response.estimatedResponseTime
        self.nextSteps = response.nextSteps
        self.statusDescription = response.statusDescription
    }
}
