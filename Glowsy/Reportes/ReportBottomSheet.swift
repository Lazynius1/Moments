import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ✅ Vista de reporte universal para momentos Y historias
struct ReportBottomSheet: View {
    // ✅ CAMBIAR: Propiedades opcionales para ambos tipos
    let moment: Moment?
    let story: Story?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedCategory: ReportCategory?
    @State private var additionalDetails: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessMessage: Bool = false
    
    private let firestoreService = FirestoreService()
    
    // ✅ NUEVOS INICIALIZADORES
    init(moment: Moment) {
        self.moment = moment
        self.story = nil
    }
    
    init(story: Story) {
        self.moment = nil
        self.story = story
    }
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    // ✅ NUEVAS PROPIEDADES COMPUTADAS
    private var contentType: String {
        return moment != nil ? "momento" : "historia"
    }
    
    private var contentId: String {
        return moment?.id ?? story?.id ?? ""
    }
    
    private var authorId: String {
        return moment?.authorId ?? story?.authorId ?? ""
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // ✅ Fondo moderno adaptativo
                if colorScheme == .dark {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black,
                            Color(hex: "1a1a2e").opacity(0.95),
                            Color(hex: "16213e").opacity(0.85)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                } else {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color(hex: "f8f9fa"),
                            Color(hex: "e9ecef")
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ✅ Header
                        headerView
                        
                        // ✅ Lista de categorías
                        categoriesView
                        
                        // ✅ Campo de detalles adicionales
                        if selectedCategory != nil {
                            additionalDetailsView
                        }
                        
                        // ✅ Botón de enviar
                        if selectedCategory != nil {
                            submitButtonView
                        }
                        
                        // ✅ Mensaje de éxito
                        if showSuccessMessage {
                            successMessageView
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
    
    // MARK: - ✅ Header ACTUALIZADO para ambos tipos
    private var headerView: some View {
        VStack(spacing: 16) {
            // ✅ Indicador de arrastre
            RoundedRectangle(cornerRadius: 3)
                .fill(adaptiveColors.tertiary)
                .frame(width: 40, height: 5)
                .padding(.top, 12)
            
            // ✅ Título y botón cerrar
            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(adaptiveColors.accent)
                
                Spacer()
                
                Text(String(format: NSLocalizedString("report.title", comment: "Report title"), contentType.capitalized))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                // ✅ Espacio para balancear
                Color.clear
                    .frame(width: 70)
            }
            .padding(.horizontal, 20)
            
            // ✅ Descripción DINÁMICA
            Text(String(format: NSLocalizedString("report.subtitle", comment: "Report subtitle"), contentType))
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - ✅ Vista de categorías (sin cambios)
    private var categoriesView: some View {
        VStack(spacing: 12) {
            ForEach(ReportCategory.allCases, id: \.self) { category in
                ReportCategoryRow(
                    category: category,
                    isSelected: selectedCategory == category,
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - ✅ Campo de detalles adicionales (sin cambios)
    private var additionalDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("report.additionalDetails", comment: "Additional details label"))
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(adaptiveColors.primary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            VStack(spacing: 0) {
                TextEditor(text: $additionalDetails)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(adaptiveColors.primary)
                    .background(Color.clear)
                    .frame(minHeight: 100)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .overlay(
                        VStack {
                            HStack {
                                if additionalDetails.isEmpty {
                                    Text(NSLocalizedString("report.detailsPlaceholder", comment: "Details placeholder text"))
                                        .font(.custom("Poppins-Regular", size: 15))
                                        .foregroundColor(adaptiveColors.tertiary)
                                        .padding(.leading, 20)
                                        .padding(.top, 16)
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    )
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - ✅ Botón de enviar (sin cambios)
    private var submitButtonView: some View {
        VStack(spacing: 16) {
            Button(action: submitReport) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.9)
                            .tint(.white)
                    } else {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text(NSLocalizedString("report.sendButton", comment: "Send report button"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.red.opacity(0.8),
                            Color.red
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.red.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(isSubmitting)
            .scaleEffect(isSubmitting ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSubmitting)
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    // MARK: - ✅ Mensaje de éxito (sin cambios)
    private var successMessageView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text(NSLocalizedString("report.success.title", comment: "Report success title"))
                .font(.custom("Poppins-SemiBold", size: 20))
                .foregroundColor(adaptiveColors.primary)
            
            Text(NSLocalizedString("report.success.message", comment: "Report success message"))
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 30)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
    }
    
    // MARK: - ✅ Función ACTUALIZADA para enviar reporte
    private func submitReport() {
        guard let category = selectedCategory,
              let currentUserId = Auth.auth().currentUser?.uid,
              !contentId.isEmpty else { return }
        
        isSubmitting = true
        
        let reportData: [String: Any] = [
            "reporterId": currentUserId,
            "reportedUserId": authorId,
            "reportedContentType": moment != nil ? "moment" : "story", // ✅ DINÁMICO
            "reportedContentId": contentId,
            "category": category.rawValue,
            "description": additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": "pending",
            "priority": category.priority.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "resolvedAt": NSNull(),
            "moderatorId": NSNull(),
            "moderatorNotes": ""
        ]
        
        Firestore.firestore().collection("reports").addDocument(data: reportData) { error in
            DispatchQueue.main.async {
                self.isSubmitting = false
                
                if let error = error {
                    // Aquí podrías mostrar un mensaje de error
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        self.showSuccessMessage = true
                    }
                }
            }
        }
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
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(adaptiveColors.primary)
                        .multilineTextAlignment(.leading)
                    
                    if !category.subtitle.isEmpty {
                        Text(category.subtitle)
                            .font(.custom("Poppins-Regular", size: 13))
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
