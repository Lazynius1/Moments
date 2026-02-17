import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct EchoInvitationView: View {
    let echoId: String
    @Binding var isPresented: Bool
    var onAccept: ((String) -> Void)? // ✅ Callback para navegar al visor
    
    @State private var echo: Echo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let db = Firestore.firestore()
    private let echoService = EchoService.shared
    
    var body: some View {
        ZStack {
            // Fondo con desenfoque
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            
            VStack {
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else if let echo = echo {
                    invitationCard(echo: echo)
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            fetchEcho()
        }
    }
    
    private func invitationCard(echo: Echo) -> some View {
        VStack(spacing: 24) {
            // Header: Nova Spark Vibe
            HStack {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("echo.invitation.sparkDetected", comment: ""))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(echo.locationName ?? NSLocalizedString("echo.viewer.location.fallback", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            
            // Participants Grid
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("echo.invitation.participants", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                
                HStack(spacing: -10) {
                    ForEach(echo.participants) { participant in
                        AsyncProfileImageView(userId: participant.userId)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                            .overlay(statusIndicator(status: participant.status), alignment: .bottomTrailing)
                    }
                    
                    if echo.participants.count > 1 {
                        let count = echo.participants.count
                        let format = count == 1 ? "echo.participants.singular" : "echo.participants.plural"
                        Text(String(format: NSLocalizedString(format, comment: ""), count))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.leading, 20)
                    }
                }
            }
            .padding(.top, 8)
            
            // Descripción IA
            Text(NSLocalizedString("echo.invitation.description", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
            
            // Botones de acción
            HStack(spacing: 16) {
                Button(action: declineEcho) {
                    Text(NSLocalizedString("echo.invitation.maybeLater", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                Button(action: acceptEcho) {
                    Text(NSLocalizedString("echo.invitation.join", comment: ""))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .orange.opacity(0.4), radius: 10, y: 5)
                }
            }
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    private func statusIndicator(status: EchoParticipantStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
    }
    
    private func statusColor(_ status: EchoParticipantStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .declined: return .red
        case .pending: return .orange
        }
    }
    
    private func fetchEcho() {
        db.collection("echoes").document(echoId).addSnapshotListener { snapshot, error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            
            guard let data = snapshot, data.exists else {
                self.errorMessage = NSLocalizedString("echo.invitation.unavailable", comment: "")
                self.isLoading = false
                return
            }
            
            do {
                self.echo = try data.data(as: Echo.self)
                self.isLoading = false
            } catch {
                self.errorMessage = NSLocalizedString("echo.invitation.error.decoding", comment: "")
                self.isLoading = false
            }
        }
    }
    
    private func acceptEcho() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                try await echoService.acceptEcho(echoId: echoId, userId: userId)
                await MainActor.run {
                    isPresented = false
                    // ✅ Navegar al visor del Echo
                    onAccept?(echoId)
                }
            } catch {
                print("Error accepting echo: \(error)")
            }
        }
    }
    
    private func declineEcho() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                try await echoService.declineEcho(echoId: echoId, userId: userId)
                isPresented = false
            } catch {
                print("Error declining echo: \(error)")
            }
        }
    }
}
