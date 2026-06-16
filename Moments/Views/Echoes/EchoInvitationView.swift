import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth

struct EchoInvitationView: View {
    let echoId: String
    let onDismiss: () -> Void
    var onAccept: ((String) -> Void)? // ✅ Callback para navegar al visor
    
    @State private var echo: Echo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var echoListener: ListenerRegistration?
    @Environment(\.colorScheme) private var colorScheme
    
    private let db = Firestore.firestore()
    private let echoService = EchoService.shared
    
    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            Group {
                if isLoading {
                    loadingCard
                } else if let echo = echo {
                    invitationCard(echo: echo)
                } else if let error = errorMessage {
                    errorCard(error)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .presentationBackground(.clear)
        .onAppear {
            fetchEcho()
        }
        .onDisappear {
            echoListener?.remove()
            echoListener = nil
        }
    }
    
    private func invitationCard(echo: Echo) -> some View {
        VStack(spacing: 24) {
            HStack {
                EchoesIconView(
                    size: EchoesIconMetrics.invitation,
                    gradient: EchoesIconView.echoesBrandGradientHorizontal
                )
                .frame(width: 40, height: 40, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("echo.invitation.sparkDetected", comment: ""))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                    
                    Text(echo.locationName ?? NSLocalizedString("echo.viewer.location.fallback", comment: ""))
                        .font(.system(size: 14))
                        .foregroundStyle(secondaryTextColor)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 34, height: 34)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("echo.invitation.participants", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .textCase(.uppercase)
                
                HStack(spacing: -10) {
                    ForEach(echo.participants) { participant in
                        AsyncProfileImageView(userId: participant.userId)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    }
                    
                    if echo.participants.count > 1 {
                        let count = echo.participants.count
                        let format = count == 1 ? "echo.participants.singular" : "echo.participants.plural"
                        Text(String(format: NSLocalizedString(format, comment: ""), count))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(primaryTextColor)
                            .padding(.leading, 20)
                    }
                }
            }
            .padding(.top, 8)
            
            Text(NSLocalizedString("echo.invitation.description", comment: ""))
                .font(.system(size: 15))
                .foregroundStyle(primaryTextColor)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8)
            
            HStack(spacing: 16) {
                Button(action: declineEcho) {
                    Text(NSLocalizedString("echo.invitation.maybeLater", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                }
                
                Button(action: acceptEcho) {
                    Text(NSLocalizedString("echo.invitation.join", comment: ""))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(joinButtonTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(joinButtonFill)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(24)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58)
    }

    private var joinButtonTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var joinButtonFill: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88))
    }

    private var loadingCard: some View {
        ProgressView()
            .tint(primaryTextColor)
            .padding(40)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func errorCard(_ error: String) -> some View {
        Text(error)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(primaryTextColor)
            .multilineTextAlignment(.center)
            .padding(24)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private func fetchEcho() {
        echoListener?.remove()
        echoListener = db.collection("echoes").document(echoId).addSnapshotListener { snapshot, error in
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
                var decodedEcho = try data.data(as: Echo.self)
                decodedEcho.id = data.documentID
                self.echo = decodedEcho
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
                    onDismiss()
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
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                print("Error declining echo: \(error)")
            }
        }
    }
}
