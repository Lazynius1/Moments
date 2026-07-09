import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ✅ Vista de reporte universal para momentos Y historias
struct ReportBottomSheet: View {
    let moment: Moment?
    let story: Story?
    let reportedUserId: String?
    let reportedUsername: String?
    
    @Environment(\.dismiss) private var dismiss
    
    init(moment: Moment) {
        self.moment = moment
        self.story = nil
        self.reportedUserId = nil
        self.reportedUsername = nil
    }
    
    init(story: Story) {
        self.moment = nil
        self.story = story
        self.reportedUserId = nil
        self.reportedUsername = nil
    }

    init(userId: String, username: String? = nil) {
        self.moment = nil
        self.story = nil
        self.reportedUserId = userId
        self.reportedUsername = username
    }
    
    var body: some View {
        Group {
            if let reportedUserId {
                UserReportContent(
                    reportedUserId: reportedUserId,
                    reportedUsername: reportedUsername,
                    onBack: { dismiss() },
                    onDismiss: { dismiss() }
                )
            } else {
                ModernReportContent(
                    moment: moment,
                    story: story,
                    reportedUserId: reportedUserId,
                    reportedUsername: reportedUsername,
                    onBack: { dismiss() },
                    onDismiss: { dismiss() }
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - ✅ Fila de categoría de reporte (sin cambios)
struct ReportCategoryRow: View {
    let category: ReportCategory
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // ✅ Icono de la categoría
                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? adaptiveColors.accent : adaptiveColors.secondary)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(adaptiveColors.primary)
                        .multilineTextAlignment(.leading)
                    
                    if !category.subtitle.isEmpty {
                        Text(category.subtitle)
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundColor(adaptiveColors.tertiary)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // ✅ Indicador de selección
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(adaptiveColors.accent)
                } else {
                    Circle()
                        .stroke(adaptiveColors.tertiary, lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                LinearGradient(
                                    colors: isSelected ?
                                    [adaptiveColors.accent.opacity(0.6), adaptiveColors.accent.opacity(0.3)] :
                                    [adaptiveColors.tertiary.opacity(0.3), adaptiveColors.tertiary.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isSelected), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ✅ Enum de categorías de reporte (sin cambios)
enum ReportCategory: String, CaseIterable {
    case dislike = "no_me_gusta"
    case bullying = "bullying_contacto_no_deseado"
    case selfHarm = "suicidio_autolesion_trastornos"
    case violence = "violencia_odio_explotacion"
    case restrictedSales = "venta_articulos_restringidos"
    case nudity = "desnudos_actividad_sexual"
    case scams = "estafas_fraudes_spam"
    case falseInfo = "informacion_falsa"
    case intellectualProperty = "propiedad_intelectual"
    
    var title: String {
        switch self {
        case .dislike:
            return NSLocalizedString("report.category.dislike.title", comment: "Dislike category title")
        case .bullying:
            return NSLocalizedString("report.category.bullying.title", comment: "Bullying category title")
        case .selfHarm:
            return NSLocalizedString("report.category.selfHarm.title", comment: "Self harm category title")
        case .violence:
            return NSLocalizedString("report.category.violence.title", comment: "Violence category title")
        case .restrictedSales:
            return NSLocalizedString("report.category.restrictedSales.title", comment: "Restricted sales category title")
        case .nudity:
            return NSLocalizedString("report.category.nudity.title", comment: "Nudity category title")
        case .scams:
            return NSLocalizedString("report.category.scams.title", comment: "Scams category title")
        case .falseInfo:
            return NSLocalizedString("report.category.falseInfo.title", comment: "False info category title")
        case .intellectualProperty:
            return NSLocalizedString("report.category.intellectualProperty.title", comment: "Intellectual property category title")
        }
    }
    
    var subtitle: String {
        switch self {
        case .dislike:
            return NSLocalizedString("report.category.dislike.subtitle", comment: "Dislike category subtitle")
        case .bullying:
            return NSLocalizedString("report.category.bullying.subtitle", comment: "Bullying category subtitle")
        case .selfHarm:
            return NSLocalizedString("report.category.selfHarm.subtitle", comment: "Self harm category subtitle")
        case .violence:
            return NSLocalizedString("report.category.violence.subtitle", comment: "Violence category subtitle")
        case .restrictedSales:
            return NSLocalizedString("report.category.restrictedSales.subtitle", comment: "Restricted sales category subtitle")
        case .nudity:
            return NSLocalizedString("report.category.nudity.subtitle", comment: "Nudity category subtitle")
        case .scams:
            return NSLocalizedString("report.category.scams.subtitle", comment: "Scams category subtitle")
        case .falseInfo:
            return NSLocalizedString("report.category.falseInfo.subtitle", comment: "False info category subtitle")
        case .intellectualProperty:
            return NSLocalizedString("report.category.intellectualProperty.subtitle", comment: "Intellectual property category subtitle")
        }
    }
    
    var icon: String {
        switch self {
        case .dislike:
            return "hand.thumbsdown"
        case .bullying:
            return "person.2.slash"
        case .selfHarm:
            return "heart.slash"
        case .violence:
            return "exclamationmark.triangle"
        case .restrictedSales:
            return "cart.badge.minus"
        case .nudity:
            return "eye.slash"
        case .scams:
            return "questionmark.diamond"
        case .falseInfo:
            return "info.circle.and.exclamationmark"
        case .intellectualProperty:
            return "c.circle"
        }
    }
    
    var priority: ReportPriority {
        switch self {
        case .dislike:
            return .low
        case .bullying, .scams, .falseInfo:
            return .medium
        case .selfHarm, .violence, .nudity, .restrictedSales:
            return .high
        case .intellectualProperty:
            return .medium
        }
    }
}

// MARK: - ✅ Enum de prioridad (sin cambios)
enum ReportPriority: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}
