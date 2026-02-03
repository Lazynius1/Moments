import Foundation

extension Date {
    /// Devuelve una representación relativa del tiempo (ej: "hace 2 min")
    /// respetando el idioma configurado para Nova y evitando ambigüedades.
    func timeAgoDisplay() -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute, .second], from: self, to: now)
        
        // Determinar idioma para sufijos claros
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        var timeString = ""
        
        if let year = components.year, year > 0 {
            // Años
            let unit = NSLocalizedString(year == 1 ? "time.unit.yr" : "time.unit.yrs", comment: "Year unit")
            timeString = "\(year) \(unit)"
        } else if let month = components.month, month > 0 {
            // Meses
            let unit = NSLocalizedString(month == 1 ? "time.unit.mo" : "time.unit.mos", comment: "Month unit")
            timeString = "\(month) \(unit)"
        } else if let week = components.weekOfYear, week > 0 {
            // Semanas
            let unit = NSLocalizedString("time.unit.wk", comment: "Week unit")
            timeString = "\(week) \(unit)"
        } else if let day = components.day, day > 0 {
            // Días
            let unit = NSLocalizedString("time.unit.d", comment: "Day unit")
            timeString = "\(day)\(unit)"
        } else if let hour = components.hour, hour > 0 {
            // Horas
            let unit = NSLocalizedString("time.unit.h", comment: "Hour unit")
            timeString = "\(hour)\(unit)"
        } else if let minute = components.minute, minute > 0 {
            // Minutos
            let unit = NSLocalizedString("time.unit.min", comment: "Minute unit")
            timeString = "\(minute) \(unit)"
        } else {
            // Menos de un minuto
            return NSLocalizedString("time.now", comment: "Just now")
        }
        
        // Usar formato localizado "hace %@" / "%@ ago"
        let format = NSLocalizedString("time.ago", comment: "Time ago")
        return String(format: format, timeString)
    }
}
