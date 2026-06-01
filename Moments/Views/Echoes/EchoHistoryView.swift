import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

/// Vista que muestra el historial de Echoes del usuario
struct EchoHistoryView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var echoes: [Echo] = []
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?
    @State private var selectedEcho: Echo?
    @State private var showEchoInfoSheet = false
    
    private let echoService = EchoService.shared
    private var activeCount: Int { echoes.filter { $0.status == .active }.count }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView

            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(.primary)
                Spacer()
            } else if echoes.isEmpty {
                Spacer()
                emptyStateView
                Spacer()
            } else {
                VStack(spacing: 14) {
                    summaryHeader
                    echoListView
                }
            }
        }
        .onAppear {
            fetchEchoes()
        }
        .onDisappear {
            listener?.remove()
        }
        .fullScreenCover(item: $selectedEcho) { echo in
            EchoViewerUI(echoId: echo.id ?? "", initialEcho: echo)
        }
        .sheet(isPresented: $showEchoInfoSheet) {
            EchoHistoryInfoSheetView()
                .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Views
    
    private var headerView: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .liquidGlass(in: Circle(), interactive: true)
                }

                Spacer()

                Button {
                    showEchoInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }

            VStack(spacing: 3) {
                Text(NSLocalizedString("echo.history.title", comment: ""))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            EchoesIconView(
                size: EchoesIconMetrics.historyEmpty,
                gradient: EchoesIconView.echoesBrandGradient
            )
            
            Text(NSLocalizedString("echo.history.empty.title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(NSLocalizedString("echo.history.empty.subtitle", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var echoListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(echoes, id: \.id) { echo in
                    EchoHistoryCard(echo: echo) {
                        selectedEcho = echo
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var summaryHeader: some View {
        HStack(spacing: 10) {
            infoChip(icon: "waveform.path.ecg", text: "\(echoes.count) Echoes")
            infoChip(
                icon: "dot.radiowaves.left.and.right",
                text: "\(activeCount) \(NSLocalizedString("echo.status.active", comment: ""))"
            )
        }
        .padding(.horizontal, 16)
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(in: Capsule())
    }
    
    // MARK: - Data
    
    private func fetchEchoes() {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        listener = echoService.fetchEchoHistory(userId: userId) { fetchedEchoes in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.echoes = fetchedEchoes
                self.isLoading = false
            }
        }
    }
}

private struct EchoHistoryInfoSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .liquidGlass(in: Circle(), interactive: true)
                    }

                    Spacer()
                }

                Text(NSLocalizedString("echo.info.title", comment: ""))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoRow(
                        title: NSLocalizedString("echo.info.what.title", comment: ""),
                        body: NSLocalizedString("echo.info.what.body", comment: "")
                    )
                    infoRow(
                        title: NSLocalizedString("echo.info.how.title", comment: ""),
                        body: NSLocalizedString("echo.info.how.body", comment: "")
                    )
                    infoRow(
                        title: NSLocalizedString("echo.info.privacy.title", comment: ""),
                        body: NSLocalizedString("echo.info.privacy.body", comment: "")
                    )
                    infoRow(
                        title: NSLocalizedString("echo.info.status.title", comment: ""),
                        body: NSLocalizedString("echo.info.status.body", comment: "")
                    )
                    infoRow(
                        title: NSLocalizedString("echo.info.controls.title", comment: ""),
                        body: NSLocalizedString("echo.info.controls.body", comment: "")
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func infoRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(body)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Echo History Card

struct EchoHistoryCard: View {
    let echo: Echo
    let onTap: () -> Void

    private var isIncomplete: Bool {
        echo.expiresAt <= Date() && !echo.hasMinimumMomentParticipants
    }
    
    private var statusColor: Color {
        if isIncomplete { return .orange }
        switch echo.status {
        case .pending: return .orange
        case .active: return .green
        case .expired: return .gray
        case .completed: return .purple
        }
    }
    
    private var statusText: String {
        if isIncomplete { return NSLocalizedString("echo.status.incomplete", comment: "") }
        switch echo.status {
        case .pending: return NSLocalizedString("echo.status.pending", comment: "")
        case .active: return NSLocalizedString("echo.status.active", comment: "")
        case .expired: return NSLocalizedString("echo.status.expired", comment: "")
        case .completed: return NSLocalizedString("echo.status.completed", comment: "")
        }
    }

    private var previewURL: URL? {
        let candidate = echo.moments.last?.thumbnailUrl ?? echo.moments.last?.mediaUrl
        guard let path = candidate else { return nil }
        return URL(string: path)
    }

    private var expiresLabel: String {
        if echo.expiresAt <= Date() {
            return NSLocalizedString("echo.status.expired", comment: "")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: echo.expiresAt, relativeTo: Date())
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Preview de Echo
                ZStack {
                    if let previewURL {
                        KFImage(previewURL)
                            .resizable()
                            .scaledToFill()
                    } else {
                        EchoesIconView(
                            size: EchoesIconMetrics.historyRow,
                            gradient: EchoesIconView.echoesBrandGradientHorizontal
                        )
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    // Ubicación
                    if let location = echo.locationName {
                        Text(location)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Echo")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    // Participantes y fecha
                    HStack(spacing: 8) {
                        let count = echo.participants.count
                        let format = count == 1 ? "echo.participants.singular" : "echo.participants.plural"
                        Text(String(format: NSLocalizedString(format, comment: ""), count))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(expiresLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Estado
                VStack(alignment: .trailing, spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12), in: Capsule())
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EchoHistoryView()
}
