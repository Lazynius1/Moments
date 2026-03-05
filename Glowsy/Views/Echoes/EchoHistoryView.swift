import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

/// Vista que muestra el historial de Echoes del usuario
struct EchoHistoryView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var echoes: [Echo] = []
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?
    @State private var selectedEcho: Echo?
    @State private var showEchoInfoSheet = false
    
    private let echoService = EchoService.shared
    private var activeCount: Int { echoes.filter { $0.status == .active }.count }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(colorScheme == .dark ? .black : .systemBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.orange)
                } else if echoes.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: 12) {
                        summaryHeader
                        echoListView
                    }
                }
            }
            .navigationTitle(NSLocalizedString("echo.history.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.close", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(Color.orange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEchoInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.orange)
                    }
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
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0.5), .purple.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
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
            .padding()
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 10) {
            infoChip(icon: "waveform.path.ecg", text: "\(echoes.count) Echoes")
            infoChip(icon: "dot.radiowaves.left.and.right", text: "\(activeCount) active")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
        .background(.ultraThinMaterial, in: Capsule())
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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(NSLocalizedString("echo.info.title", comment: ""))
                        .font(.system(size: 24, weight: .bold))

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
                        title: NSLocalizedString("echo.info.controls.title", comment: ""),
                        body: NSLocalizedString("echo.info.controls.body", comment: "")
                    )
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Echo History Card

struct EchoHistoryCard: View {
    let echo: Echo
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var statusColor: Color {
        switch echo.status {
        case .pending: return .orange
        case .active: return .green
        case .expired: return .gray
        case .completed: return .purple
        }
    }
    
    private var statusText: String {
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
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                                [Color.white.opacity(0.14), Color.white.opacity(0.06)] :
                                [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EchoHistoryView()
}
