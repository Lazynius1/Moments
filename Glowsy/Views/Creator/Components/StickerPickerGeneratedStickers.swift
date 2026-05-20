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
                image: createWeatherBackgroundImage(for: weather.symbol),
                position: constrainPositionToBounds(CGPoint(
                    x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                    y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
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

        // ✅ CREAR IMAGEN DE FONDO PARA ANIMACIÓN
        private func createWeatherBackgroundImage(for symbol: String) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
            let image = renderer.image { context in
                let rect = CGRect(x: 0, y: 0, width: 140, height: 50)

                // ✅ FONDO CON GRADIENTE SEGÚN CLIMA
                // ✅ FONDO CON GRADIENTE SEGÚN CLIMA
                let colors = getWeatherGradientColors(for: symbol)

                let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
                context.cgContext.saveGState()
                path.addClip()

                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
                } else {
                    UIColor.systemBlue.setFill()
                    context.fill(rect)
                }
                context.cgContext.restoreGState()

                // ✅ BORDE ELEGANTE
                UIColor.white.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1
                path.stroke()

                // ✅ TEXTO CENTRADO (solo símbolo del clima)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                symbol.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
            }

            return image
        }

        // ✅ CREAR STICKER CON PLACEHOLDER
        private func createWeatherStickerWithPlaceholder() {
            let weatherText = "🌤️"



            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 140, height: 50))
            let image = renderer.image { context in
                let rect = CGRect(x: 0, y: 0, width: 140, height: 50)

                // ✅ FONDO AZUL POR DEFECTO
                let colors = [
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                    UIColor.systemCyan.withAlphaComponent(0.9).cgColor
                ] as CFArray

                let path = UIBezierPath(roundedRect: rect, cornerRadius: 25)
                context.cgContext.saveGState()
                path.addClip()

                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: rect.width, y: rect.height), options: [])
                } else {
                    UIColor.systemBlue.setFill()
                    context.fill(rect)
                }
                context.cgContext.restoreGState()

                // ✅ BORDE ELEGANTE
                UIColor.white.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1
                path.stroke()

                // ✅ TEXTO CENTRADO
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                weatherText.draw(in: CGRect(x: 10, y: 15, width: 120, height: 20), withAttributes: attributes)
            }

            let sticker = StickerItem(
                image: image,
                position: constrainPositionToBounds(CGPoint(
                    x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                    y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
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

        // ✅ OBTENER COLORES DE GRADIENTE SEGÚN CLIMA
        private func getWeatherGradientColors(for symbol: String) -> CFArray {
            switch symbol {
            case "☀️": // Soleado
                return [
                    UIColor.systemOrange.withAlphaComponent(0.9).cgColor,
                    UIColor.systemYellow.withAlphaComponent(0.9).cgColor
                ] as CFArray
            case "🌧️", "⛈️": // Lluvia/Tormenta
                return [
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                    UIColor.systemIndigo.withAlphaComponent(0.9).cgColor
                ] as CFArray
            case "❄️", "🌨️": // Nieve
                return [
                    UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor
                ] as CFArray
            case "☁️", "⛅": // Nublado
                return [
                    UIColor.systemGray.withAlphaComponent(0.9).cgColor,
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor
                ] as CFArray
            case "🔥": // Calor
                return [
                    UIColor.systemRed.withAlphaComponent(0.9).cgColor,
                    UIColor.systemOrange.withAlphaComponent(0.9).cgColor
                ] as CFArray
            case "🥶": // Frío
                return [
                    UIColor.systemCyan.withAlphaComponent(0.9).cgColor,
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor
                ] as CFArray
            default: // Por defecto
                return [
                    UIColor.systemBlue.withAlphaComponent(0.9).cgColor,
                    UIColor.systemCyan.withAlphaComponent(0.9).cgColor
                ] as CFArray
            }
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
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            timeFormatter.locale = Locale(identifier: "es_ES")

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "d MMM"
            dateFormatter.locale = Locale(identifier: "es_ES")

            let timeString = timeFormatter.string(from: now)
            let dateString = dateFormatter.string(from: now)

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
                    x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -40...40),
                    y: UIScreen.main.bounds.height / 2 + CGFloat.random(in: -40...40)
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
