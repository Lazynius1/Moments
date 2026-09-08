import SwiftUI
import CoreLocation
import UIKit

extension StickerPickerView {
        // MARK: - ✅ WEATHER STICKER
        func createWeatherSticker() {
            // ✅ OBTENER CLIMA ACTUAL CON WEATHER KIT
            Task {
                do {
                    let weather = try await getCurrentWeather()
                    await MainActor.run {
                        createWeatherStickerWithData(weather)
                    }
                } catch {
                    // ✅ FALLBACK: Crear sticker con placeholder
                    await MainActor.run {
                        createWeatherStickerWithPlaceholder()
                    }
                }
            }
        }

        // ✅ FUNCIÓN PARA OBTENER CLIMA ACTUAL
        private func getCurrentWeather() async throws -> (temperature: Double, condition: String, symbol: String) {
            let locationManager = CLLocationManager()

            // ✅ VERIFICAR PERMISOS
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                break
            default:
                throw WeatherError.noLocationPermission
            }

            // ✅ OBTENER UBICACIÓN ACTUAL
            guard let location = locationManager.location else {
                throw WeatherError.noLocation
            }

            // ✅ USAR WEATHERSERVICE EXISTENTE
            let weatherService = WeatherService.shared
            let currentWeather = try await weatherService.getWeather(for: location.coordinate)

            let temperature = currentWeather.temperature
            let condition = currentWeather.condition.displayName
            let symbol = getWeatherSymbol(for: condition)

            return (temperature: temperature, condition: condition, symbol: symbol)
        }

        // ✅ CONVERTIR CONDICIÓN A SÍMBOLO (MEJORADO CON HORA DEL DÍA)
        private func getWeatherSymbol(for condition: String) -> String {
            let lowercased = condition.lowercased()
            let hour = Calendar.current.component(.hour, from: Date())

            // ✅ DETECTAR SI ES NOCHE (entre 20:00 y 6:00)
            let isNight = hour >= 20 || hour < 6

            if lowercased.contains("clear") || lowercased.contains("sunny") {
                return isNight ? "🌙" : "☀️"
            } else if lowercased.contains("cloud") {
                return isNight ? "☁️" : "🌤️"
            } else if lowercased.contains("rain") || lowercased.contains("drizzle") {
                return "🌧️"
            } else if lowercased.contains("snow") || lowercased.contains("sleet") {
                return "❄️"
            } else if lowercased.contains("storm") || lowercased.contains("thunder") {
                return "⛈️"
            } else if lowercased.contains("fog") || lowercased.contains("haze") {
                return "🌫️"
            } else if lowercased.contains("wind") || lowercased.contains("breeze") {
                return "💨"
            } else if lowercased.contains("hot") {
                return "🔥"
            } else if lowercased.contains("cold") {
                return "🥶"
            } else {
                return isNight ? "🌙" : "🌤️"
            }
        }

        // ✅ CREAR STICKER CON DATOS REALES
        private func createWeatherStickerWithData(_ weather: (temperature: Double, condition: String, symbol: String)) {
            let temperature = Int(round(weather.temperature))
            let weatherText = "\(temperature)°C"



            // ✅ CREAR STICKER ANIMADO
            let sticker = StickerItem(
                image: weatherStickerPlaceholderImage(temperature: weatherText),
                position: constrainPositionToBounds(CGPoint(
                    x: canvasSize.width / 2 + CGFloat.random(in: -40...40),
                    y: canvasSize.height / 2 + CGFloat.random(in: -40...40)
                )),
                type: .weather,
                interactionData: StickerItem.StickerInteractionData(
                    username: nil,
                    userId: nil,
                    hashtag: nil,
                    location: nil,
                    locationCoordinate: nil,
                    pollData: nil,
                    questionText: weatherText,
                    weatherSymbol: weather.symbol,
                    caption: nil,
                    profileImagePath: nil, momentId: nil
                )
            )



            selectedStickers.append(sticker)

            dismiss()
        }

        /// `StickerItem` exige imagen; el visor pinta `AnimatedWeatherSticker`.
        private func weatherStickerPlaceholderImage(temperature: String) -> UIImage {
            let size = weatherStickerRenderingSize(temperature: temperature)
            return UIGraphicsImageRenderer(size: size).image { _ in }
        }

        private func createWeatherStickerWithPlaceholder() {
            let weatherText = "🌤️"
            let sticker = StickerItem(
                image: weatherStickerPlaceholderImage(temperature: weatherText),
                position: constrainPositionToBounds(CGPoint(
                    x: canvasSize.width / 2 + CGFloat.random(in: -40...40),
                    y: canvasSize.height / 2 + CGFloat.random(in: -40...40)
                )),
                type: .weather,
                interactionData: StickerItem.StickerInteractionData(
                    username: nil,
                    userId: nil,
                    hashtag: nil,
                    location: nil,
                    locationCoordinate: nil,
                    pollData: nil,
                    questionText: weatherText,
                    weatherSymbol: "🌤️",
                    caption: nil,
                    profileImagePath: nil, momentId: nil
                )
            )

            selectedStickers.append(sticker)
            dismiss()
        }

        // ✅ ENUM PARA ERRORES DE CLIMA
        enum WeatherError: Error {
            case noLocationPermission
            case noLocation
            case unsupportedVersion
        }

        // MARK: - ✅ TIME STICKER
        func createTimeSticker() {
            let now = Date()

            // ✅ FORMATO: "14:30" (Hora) + "7 Ago" (Fecha)
            let timeString = MomentsFormat.smartDate(from: now, context: .timeOnly)
            let dateString = MomentsFormat.smartDate(from: now, context: .dayMonthLabel)

            let width: CGFloat = 164
            let height: CGFloat = 56
            let cornerRadius: CGFloat = 22

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            let image = renderer.image { context in
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                drawStickerCardBackground(in: context, rect: rect, cornerRadius: cornerRadius)

                drawStickerAccentPill(
                    in: context,
                    rect: CGRect(x: 14, y: 14, width: 28, height: 28),
                    fillColor: UIColor(red: 0.18, green: 0.66, blue: 0.98, alpha: 1),
                    iconSystemName: "clock.fill"
                )

                let timeAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
                    .foregroundColor: UIColor.black.withAlphaComponent(0.92)
                ]

                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: UIColor.black.withAlphaComponent(0.48)
                ]

                timeString.draw(in: CGRect(x: 52, y: 12, width: 92, height: 20), withAttributes: timeAttributes)
                dateString.draw(in: CGRect(x: 52, y: 31, width: 92, height: 14), withAttributes: dateAttributes)
            }

            let sticker = StickerItem(
                image: image,
                position: constrainPositionToBounds(CGPoint(
                    x: canvasSize.width / 2 + CGFloat.random(in: -40...40),
                    y: canvasSize.height / 2 + CGFloat.random(in: -40...40)
                )),
                type: .time,
                interactionData: StickerItem.StickerInteractionData(
                    username: nil,
                    userId: nil,
                    hashtag: nil,
                    location: nil,
                    locationCoordinate: nil,
                    pollData: nil,
                    questionText: timeString, // ✅ Guardamos la hora para el visor
                    weatherSymbol: nil,
                    caption: dateString, // ✅ Guardamos la fecha para el visor
                    profileImagePath: nil, momentId: nil
                )
            )

            selectedStickers.append(sticker)
            dismiss()
        }
}
