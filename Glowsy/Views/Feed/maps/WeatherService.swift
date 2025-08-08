// ================== WeatherService_Final.swift ==================
// Versión final corregida con API correcta de WeatherKit

import Foundation
import WeatherKit
import CoreLocation
import SwiftUI

// MARK: - Weather Models
struct WeatherData {
    let temperature: Double
    let condition: WeatherCondition
    let precipitation: Double
    let cloudCover: Double
    let isNight: Bool
    let location: CLLocationCoordinate2D
    let timestamp: Date
    
    var isDaytime: Bool { !isNight }
}

enum WeatherCondition: String, CaseIterable {
    case clear = "clear"
    case partlyCloudy = "partly_cloudy"
    case cloudy = "cloudy"
    case rain = "rain"
    case snow = "snow"
    case thunderstorm = "thunderstorm"
    case unknown = "unknown"
    
    var systemImageName: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
        case .cloudy:
            return "cloud.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .clear:
            return "Despejado"
        case .partlyCloudy:
            return "Parcialmente nublado"
        case .cloudy:
            return "Nublado"
        case .rain:
            return "Lluvia"
        case .snow:
            return "Nieve"
        case .thunderstorm:
            return "Tormenta"
        case .unknown:
            return "Desconocido"
        }
    }
}

// MARK: - Weather Cache
private struct WeatherCacheEntry {
    let data: WeatherData
    let expiry: Date
    
    var isExpired: Bool {
        Date() > expiry
    }
}

// MARK: - Weather Service (API Correcta)
@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()
    
    @Published var currentWeather: WeatherData?
    @Published var isLoading = false
    @Published var error: WeatherError?
    
    private let weatherService = WeatherKit.WeatherService()
    private var cache: [String: WeatherCacheEntry] = [:]
    private let cacheExpiryInterval: TimeInterval = 3600 // 1 hora
    private let maxCacheSize = 50
    
    // Rate limiting
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 10 // 10 segundos entre requests
    private var dailyRequestCount = 0
    private var lastResetDate = Date()
    private let maxDailyRequests = 1000
    
    private init() {
        cleanExpiredCache()
    }
    
    // MARK: - Public Methods
    
    func getWeather(for coordinate: CLLocationCoordinate2D) async throws -> WeatherData {
        // Verificar cache primero
        let cacheKey = generateCacheKey(for: coordinate)
        if let cachedEntry = cache[cacheKey], !cachedEntry.isExpired {
            print("☀️ [WeatherService] Usando datos del cache para: \(coordinate)")
            DispatchQueue.main.async {
                self.currentWeather = cachedEntry.data
            }
            return cachedEntry.data
        }
        
        // Rate limiting
        try await enforceRateLimit()
        
        print("🌤️ [WeatherService] Solicitando datos del clima para: \(coordinate)")
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            // ✅ API CORRECTA DE WEATHERKIT
            let currentWeather = try await weatherService.weather(
                for: location,
                including: .current
            )
            
            let hourlyForecast = try await weatherService.weather(
                for: location,
                including: .hourly
            )
            
            let dailyForecast = try await weatherService.weather(
                for: location,
                including: .daily
            )
            
            let weatherData = mapWeatherKitData(
                current: currentWeather,
                hourly: hourlyForecast,
                daily: dailyForecast,
                coordinate: coordinate
            )
            
            // Guardar en cache
            cache[cacheKey] = WeatherCacheEntry(
                data: weatherData,
                expiry: Date().addingTimeInterval(cacheExpiryInterval)
            )
            
            // Limpiar cache si está muy grande
            if cache.count > maxCacheSize {
                cleanOldestCacheEntries()
            }
            
            DispatchQueue.main.async {
                self.currentWeather = weatherData
                self.isLoading = false
            }
            
            incrementRequestCount()
            print("✅ [WeatherService] Datos del clima obtenidos: \(weatherData.condition.displayName)")
            
            return weatherData
            
        } catch {
            let weatherError = mapError(error)
            
            DispatchQueue.main.async {
                self.error = weatherError
                self.isLoading = false
            }
            
            print("❌ [WeatherService] Error obteniendo clima: \(weatherError.localizedDescription)")
            throw weatherError
        }
    }
    
    func getWeatherSafely(for coordinate: CLLocationCoordinate2D) async -> WeatherData? {
        do {
            return try await getWeather(for: coordinate)
        } catch {
            print("⚠️ [WeatherService] Fallo silencioso del clima: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAll()
        print("🗑️ [WeatherService] Cache limpiado")
    }
    
    func getCacheStatus() -> (count: Int, oldestEntry: Date?) {
        let count = cache.count
        let oldestEntry = cache.values.map(\.data.timestamp).min()
        return (count: count, oldestEntry: oldestEntry)
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        // Redondear coordenadas para agrupar ubicaciones cercanas (±0.01 grados ≈ 1km)
        let roundedLat = round(coordinate.latitude * 100) / 100
        let roundedLng = round(coordinate.longitude * 100) / 100
        return "\(roundedLat),\(roundedLng)"
    }
    
    private func enforceRateLimit() async throws {
        let now = Date()
        
        // Reset contador diario
        if !Calendar.current.isDate(now, inSameDayAs: lastResetDate) {
            dailyRequestCount = 0
            lastResetDate = now
        }
        
        // Verificar límite diario
        if dailyRequestCount >= maxDailyRequests {
            throw WeatherError.quotaExceeded
        }
        
        // Verificar intervalo mínimo
        let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minRequestInterval {
            let waitTime = minRequestInterval - timeSinceLastRequest
            print("⏳ [WeatherService] Rate limit: esperando \(waitTime)s")
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        lastRequestTime = now
    }
    
    private func incrementRequestCount() {
        dailyRequestCount += 1
        print("📊 [WeatherService] Requests hoy: \(dailyRequestCount)/\(maxDailyRequests)")
    }
    
    // ✅ MAPEO CORREGIDO CON PARÁMETROS SEPARADOS
    private func mapWeatherKitData(
        current: CurrentWeather,
        hourly: Forecast<HourWeather>,
        daily: Forecast<DayWeather>,
        coordinate: CLLocationCoordinate2D
    ) -> WeatherData {
        
        let condition = mapWeatherKitCondition(current.condition)
        
        // Determinar si es de noche
        let isNight = determineIfNight(daily: daily)
        
        // Obtener precipitación de manera segura
        let precipitation = getPrecipitation(current: current, hourly: hourly, daily: daily)
        
        return WeatherData(
            temperature: current.temperature.value,
            condition: condition,
            precipitation: precipitation,
            cloudCover: current.cloudCover,
            isNight: isNight,
            location: coordinate,
            timestamp: Date()
        )
    }
    
    private func determineIfNight(daily: Forecast<DayWeather>) -> Bool {
        // Intentar usar datos de salida/puesta del sol
        if let todayForecast = daily.first,
           let sunrise = todayForecast.sun.sunrise,
           let sunset = todayForecast.sun.sunset {
            let now = Date()
            return now < sunrise || now > sunset
        }
        
        // Fallback: usar hora local (6PM - 6AM)
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 || hour < 6
    }
    
    private func getPrecipitation(
        current: CurrentWeather,
        hourly: Forecast<HourWeather>,
        daily: Forecast<DayWeather>
    ) -> Double {
        // Intentar obtener de hourly forecast (más preciso)
        if let firstHour = hourly.first {
            return firstHour.precipitationAmount.value
        }
        
        // Fallback: usar daily forecast
        if let firstDay = daily.first {
            return firstDay.precipitationAmount.value
        }
        
        // Último fallback: estimar basado en condición actual
        return estimatePrecipitationFromCondition(current.condition)
    }
    
    private func estimatePrecipitationFromCondition(_ condition: WeatherKit.WeatherCondition) -> Double {
        switch condition {
        case .rain, .drizzle:
            return 2.0 // mm estimados
        case .freezingRain:
            return 1.5
        case .snow, .sleet, .freezingDrizzle:
            return 3.0
        case .thunderstorms:
            return 5.0
        default:
            return 0.0
        }
    }
    
    // ✅ MAPEO CORREGIDO DE CONDICIONES (SIN FOG)
    private func mapWeatherKitCondition(_ condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        switch condition {
        case .clear:
            return .clear
        case .partlyCloudy:
            return .partlyCloudy
        case .cloudy, .mostlyCloudy:
            return .cloudy
        case .rain, .drizzle, .freezingRain:
            return .rain
        case .snow, .sleet, .freezingDrizzle:
            return .snow
        case .thunderstorms:
            return .thunderstorm
        case .haze:
            return .cloudy // Mapear haze a cloudy
        case .windy:
            return .partlyCloudy
        case .hot:
            return .clear
        default:
            return .unknown
        }
    }
    
    private func mapError(_ error: Error) -> WeatherError {
        if let weatherError = error as? WeatherError {
            return weatherError
        }
        
        // Mapear errores específicos de WeatherKit
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("quota") || errorDescription.contains("limit") || errorDescription.contains("exceeded") {
            return .quotaExceeded
        } else if errorDescription.contains("network") || errorDescription.contains("internet") || errorDescription.contains("connection") {
            return .networkError
        } else if errorDescription.contains("location") || errorDescription.contains("coordinate") {
            return .locationError
        } else if errorDescription.contains("permission") || errorDescription.contains("authorization") {
            return .permissionDenied
        } else {
            return .unknown(error.localizedDescription)
        }
    }
    
    private func cleanExpiredCache() {
        let expiredKeys = cache.compactMap { key, entry in
            entry.isExpired ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            print("🧹 [WeatherService] Limpiadas \(expiredKeys.count) entradas expiradas del cache")
        }
    }
    
    private func cleanOldestCacheEntries() {
        let sortedEntries = cache.sorted { $0.value.data.timestamp < $1.value.data.timestamp }
        let entriesToRemove = sortedEntries.prefix(cache.count - maxCacheSize + 10)
        
        for (key, _) in entriesToRemove {
            cache.removeValue(forKey: key)
        }
        
        print("🧹 [WeatherService] Limpiadas \(entriesToRemove.count) entradas antiguas del cache")
    }
}

// MARK: - Weather Errors
enum WeatherError: LocalizedError {
    case quotaExceeded
    case networkError
    case locationError
    case permissionDenied
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            return "Límite de consultas meteorológicas alcanzado"
        case .networkError:
            return "Error de conexión al servicio meteorológico"
        case .locationError:
            return "Ubicación no válida para consulta meteorológica"
        case .permissionDenied:
            return "Permisos de ubicación requeridos para el clima"
        case .unknown(let message):
            return "Error meteorológico: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .quotaExceeded:
            return "Los efectos climáticos estarán disponibles mañana"
        case .networkError:
            return "Verifica tu conexión a internet"
        case .locationError:
            return "Verifica que la ubicación sea válida"
        case .permissionDenied:
            return "Habilita permisos de ubicación en Configuración"
        case .unknown:
            return "Los efectos climáticos no están disponibles temporalmente"
        }
    }
}

// MARK: - Extensions
extension WeatherData {
    var temperatureFormatted: String {
        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        let temp = Measurement(value: temperature, unit: UnitTemperature.celsius)
        return formatter.string(from: temp)
    }
    
    var precipitationFormatted: String {
        if precipitation < 0.1 {
            return "Sin precipitación"
        } else {
            return String(format: "%.1f mm", precipitation)
        }
    }
    
    var cloudCoverFormatted: String {
        return String(format: "%.0f%% nublado", cloudCover * 100)
    }
}
