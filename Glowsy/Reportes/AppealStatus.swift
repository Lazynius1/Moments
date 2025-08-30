import SwiftUI

struct AppealStatusView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var appealService = AppealService.shared
    @State private var appeals: [AppealStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedAppeal: AppealStatus?
    @State private var refreshing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
                if isLoading {
                    LoadingView()
                } else if appeals.isEmpty {
                    EmptyAppealsView()
                } else {
                    AppealsListView(
                        appeals: appeals,
                        selectedAppeal: $selectedAppeal,
                        refreshing: $refreshing,
                        onRefresh: fetchAppeals
                    )
                }
            }
            .navigationTitle(NSLocalizedString("appeal.status.title", comment: "My appeals navigation title"))
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                trailing: Button(action: fetchAppeals) {
                    Image(systemName: refreshing ? "arrow.clockwise" : "arrow.clockwise")
                        .foregroundColor(.primary)  // ✅ Cambio: .primary para adaptabilidad
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(refreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: refreshing)
                }
                .disabled(refreshing)
            )
        }
        .sheet(item: $selectedAppeal) { appeal in
            AppealDetailView(appeal: appeal)
        }
        .onAppear {
            fetchAppeals()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Error desconocido")
        }
    }
    
    private func fetchAppeals() {
        guard let userId = authService.currentFirebaseUser?.uid else { return }
        
        if !refreshing {
            isLoading = true
        }
        refreshing = true
        
        Task {
            do {
                let fetchedAppeals = try await appealService.fetchUserAppeals(userId: userId)
                
                await MainActor.run {
                    self.appeals = fetchedAppeals
                    self.isLoading = false
                    self.refreshing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.refreshing = false
                }
            }
        }
    }
}

// MARK: - Appeals List View
struct AppealsListView: View {
    let appeals: [AppealStatus]
    @Binding var selectedAppeal: AppealStatus?
    @Binding var refreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(appeals, id: \.id) { appeal in
                    AppealCard(appeal: appeal) {
                        selectedAppeal = appeal
                    }
                }
            }
            .padding()
        }
        .refreshable {
            onRefresh()
        }
    }
}

// MARK: - Appeal Card
struct AppealCard: View {
    let appeal: AppealStatus
    let onTap: () -> Void
    @State private var isVisible = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header con ticket y estado
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("appeal.status.ticket", comment: "Ticket number format"), appeal.ticketNumber))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)  // ✅ Cambio
                        
                        Text(appeal.submittedAt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)  // ✅ Cambio
                    }
                    
                    Spacer()
                    
                    AppealStatusBadge(status: appeal.status, priority: appeal.priority)
                }
                
                // Progreso visual
                AppealProgressBar(
                    status: appeal.status,
                    priority: appeal.priority
                )
                
                // Información principal
                VStack(alignment: .leading, spacing: 8) {
                    if let reason = appeal.suspensionReason {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            
                            Text(String(format: NSLocalizedString("appeal.status.reason", comment: "Suspension reason format"), reason))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)  // ✅ Cambio
                                .lineLimit(2)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        
                        Text(String(format: NSLocalizedString("appeal.status.estimatedResponse", comment: "Estimated response format"), appeal.estimatedResponseTime))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)  // ✅ Cambio
                    }
                    
                    if let moderatorNotes = appeal.moderatorNotes, !moderatorNotes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            
                            Text(String(format: NSLocalizedString("appeal.status.moderatorNotes", comment: "Moderator notes format"), moderatorNotes))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)  // ✅ Cambio
                                .lineLimit(3)
                        }
                    }
                }
                
                // Botón de acción según estado
                AppealActionButton(appeal: appeal)
            }
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    statusColor(for: appeal.status).opacity(0.4),
                                    statusColor(for: appeal.status).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .opacity(isVisible ? 1.0 : 0.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "reviewing": return .blue
        case "approved": return .green
        case "denied": return .red
        case "requires_info": return .purple
        default: return .gray
        }
    }
}

// MARK: - Appeal Status Badge
struct AppealStatusBadge: View {
    let status: String
    let priority: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(statusColor.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(statusColor.opacity(0.4), lineWidth: 1)
                    )
            )
            
            // Priority indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 6, height: 6)
                
                Text(priority.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)  // ✅ Cambio
            }
        }
    }
    
    private var statusIcon: String {
        switch status {
        case "pending": return "clock.fill"
        case "reviewing": return "eye.fill"
        case "approved": return "checkmark.circle.fill"
        case "denied": return "xmark.circle.fill"
        case "requires_info": return "questionmark.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private var statusText: String {
        switch status {
        case "pending": return "Pendiente"
        case "reviewing": return "Revisando"
        case "approved": return "Aprobada"
        case "denied": return "Denegada"
        case "requires_info": return "Info Requerida"
        default: return status.capitalized
        }
    }
    
    private var statusColor: Color {
        switch status {
        case "pending": return .orange
        case "reviewing": return .blue
        case "approved": return .green
        case "denied": return .red
        case "requires_info": return .purple
        default: return .gray
        }
    }
    
    private var priorityColor: Color {
        switch priority {
        case "high": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .gray
        }
    }
}

// MARK: - Appeal Progress Bar
struct AppealProgressBar: View {
    let status: String
    let priority: String
    
    private var progress: CGFloat {
        switch status {
        case "pending": return 0.2
        case "reviewing": return 0.6
        case "approved", "denied": return 1.0
        case "requires_info": return 0.4
        default: return 0.0
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("appeal.status.progress", comment: "Progress label"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)  // ✅ Cambio
                
                Spacer()
                
                Text(String(format: NSLocalizedString("appeal.status.percentage", comment: "Progress percentage format"), Int(progress * 100)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)  // ✅ Cambio
            }
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.2))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [statusColor.opacity(0.8), statusColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: progress * 200, height: 6)
                    .animation(.easeInOut(duration: 1.0), value: progress)
            }
            .frame(width: 200)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case "pending": return .orange
        case "reviewing": return .blue
        case "approved": return .green
        case "denied": return .red
        case "requires_info": return .purple
        default: return .gray
        }
    }
}

// MARK: - Appeal Action Button
struct AppealActionButton: View {
    let appeal: AppealStatus
    
    var body: some View {
        if shouldShowActionButton {
            Button(action: actionButtonTapped) {
                HStack(spacing: 8) {
                    Image(systemName: actionButtonIcon)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text(actionButtonText)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(actionButtonColor.opacity(0.8))
                )
            }
        }
    }
    
    private var shouldShowActionButton: Bool {
        appeal.status == "requires_info" || appeal.status == "approved"
    }
    
    private var actionButtonText: String {
        switch appeal.status {
        case "requires_info": return NSLocalizedString("appeal.action.provideInfo", comment: "Provide info button")
        case "approved": return NSLocalizedString("appeal.action.reactivateAccount", comment: "Reactivate account button")
        default: return ""
        }
    }
    
    private var actionButtonIcon: String {
        switch appeal.status {
        case "requires_info": return "plus.circle.fill"
        case "approved": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
    
    private var actionButtonColor: Color {
        switch appeal.status {
        case "requires_info": return .blue
        case "approved": return .green
        default: return .gray
        }
    }
    
    private func actionButtonTapped() {
        // TODO: Implementar acciones específicas
        switch appeal.status {
        case "requires_info":
            // Mostrar formulario para información adicional
            break
        case "approved":
            // Proceso de reactivación de cuenta
            break
        default:
            break
        }
    }
}

// MARK: - Empty Appeals View
struct EmptyAppealsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)  // ✅ Cambio
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("appeal.status.noAppeals.title", comment: "No appeals title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)  // ✅ Cambio
                
                Text(NSLocalizedString("appeal.status.noAppeals.description", comment: "No appeals description"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)  // ✅ Cambio
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primary))  // ✅ Cambio
                .scaleEffect(1.5)
            
            Text(NSLocalizedString("appeal.status.loading", comment: "Loading appeals text"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)  // ✅ Cambio
        }
    }
}

// MARK: - Data Models
struct AppealStatus: Identifiable {
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
}

// MARK: - ✅ NUEVO: AppealDetailView
struct AppealDetailView: View {
    let appeal: AppealStatus
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        AppealDetailHeader(appeal: appeal)
                        
                        // Content sections
                        VStack(spacing: 20) {
                            AppealDetailInfoSection(appeal: appeal)
                            AppealDetailTimelineSection(appeal: appeal)
                            AppealDetailMessageSection(appeal: appeal)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(NSLocalizedString("appeal.detail.title", comment: "Appeal detail title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(NSLocalizedString("appeal.detail.close", comment: "Close button")) {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.primary)
            )
        }
    }
}

// MARK: - Appeal Detail Components
struct AppealDetailHeader: View {
    let appeal: AppealStatus
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Ticket #\(appeal.ticketNumber)")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            
            AppealStatusBadge(status: appeal.status, priority: appeal.priority)
            
            AppealProgressBar(status: appeal.status, priority: appeal.priority)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 20)
    }
}

struct AppealDetailInfoSection: View {
    let appeal: AppealStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Información")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                if let reason = appeal.suspensionReason {
                    AppealInfoRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Motivo de suspensión",
                        content: reason,
                        color: .orange
                    )
                }
                
                AppealInfoRow(
                    icon: "clock.fill",
                    title: "Tiempo estimado",
                    content: appeal.estimatedResponseTime,
                    color: .blue
                )
                
                AppealInfoRow(
                    icon: "calendar",
                    title: "Enviado",
                    content: appeal.submittedAt,
                    color: .green
                )
                
                if let moderatorNotes = appeal.moderatorNotes, !moderatorNotes.isEmpty {
                    AppealInfoRow(
                        icon: "person.badge.shield.checkmark.fill",
                        title: "Notas del moderador",
                        content: moderatorNotes,
                        color: .purple
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct AppealDetailTimelineSection: View {
    let appeal: AppealStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Próximos pasos")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(appeal.nextSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.blue))
                        
                        Text(step)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct AppealDetailMessageSection: View {
    let appeal: AppealStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tu mensaje")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            Text(appeal.appealMessage)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
            
            if let additionalInfo = appeal.additionalInfo, !additionalInfo.isEmpty {
                Divider()
                
                Text("Información adicional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(additionalInfo)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct AppealInfoRow: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(content)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}
