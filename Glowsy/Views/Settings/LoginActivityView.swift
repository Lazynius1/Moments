import SwiftUI
import FirebaseAuth
import UIKit

struct LoginActivityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = LoginActivityViewModel()
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if isLoading {
                    ProgressView {
                        Text("loginActivity.loading")
                    }
                        .progressViewStyle(CircularProgressViewStyle())
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text("loginActivity.currentSession")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                CurrentSessionCard(session: viewModel.currentSession)
                            }
                            .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("loginActivity.otherSessions")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Spacer()
                                    
                                    Button(NSLocalizedString("loginActivity.logoutAll", comment: "Logout all sessions")) {
                                        viewModel.showLogoutAllAlert = true
                                    }
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.red)
                                }
                                
                                if viewModel.otherSessions.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "desktopcomputer.and.arrow.down")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        
                                        Text("loginActivity.noOtherSessions")
                                            .font(.custom("Poppins-Regular", size: 16))
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    LazyVStack(spacing: 12) {
                                        ForEach(viewModel.otherSessions) { session in
                                            SessionCard(session: session)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.top)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("loginActivity.navigation.title", comment: "Login activity navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .onAppear {
                viewModel.loadLoginActivity {
                    isLoading = false
                }

                // Safety net to avoid indefinite loading UI if any callback is delayed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if isLoading {
                        isLoading = false
                    }
                }
            }
            .refreshable {
                await viewModel.refreshLoginActivity()
            }
            .alert(NSLocalizedString("loginActivity.logoutAll.title", comment: "Logout all sessions"), isPresented: $viewModel.showLogoutAllAlert) {
                Button(NSLocalizedString("loginActivity.cancel", comment: "Cancel"), role: .cancel) { }
                Button(NSLocalizedString("loginActivity.logoutAll.confirm", comment: "Logout all"), role: .destructive) {
                    viewModel.logoutAllSessions()
                }
            } message: {
                Text("loginActivity.logoutAll.message")
            }
            .alert(NSLocalizedString("loginActivity.error.title", comment: "Error"), isPresented: $viewModel.showError) {
                Button(NSLocalizedString("loginActivity.ok", comment: "OK")) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert(NSLocalizedString("loginActivity.logoutSuccess.title", comment: "Sessions closed"), isPresented: $viewModel.showLogoutSuccess) {
                Button(NSLocalizedString("loginActivity.ok", comment: "OK")) { }
            } message: {
                Text("loginActivity.logoutSuccess.message")
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(Color(hex: "4F46E5"))
                    .font(.system(size: 20))
                
                Text("loginActivity.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Text("loginActivity.description")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "4F46E5").opacity(0.1))
        )
        .padding(.horizontal)
    }
}

struct CurrentSessionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let session: LoginSession?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: session == nil ? "shield.slash.fill" : "checkmark.shield.fill")
                    .foregroundColor(session == nil ? .gray : .green)
                    .font(.system(size: 20))
                
                Text("loginActivity.activeSession")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                if session != nil {
                    Text("loginActivity.current")
                        .font(.custom("Poppins-Bold", size: 10))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.green.opacity(0.2))
                        )
                }
            }
            
            if let session = session {
                SessionDetails(session: session)
            } else {
                Text("loginActivity.noCurrentSession")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct SessionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let session: LoginSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(Color(hex: "4F46E5"))
                    .font(.system(size: 16, weight: .semibold))
                
                Text(session.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.75))
                
                Spacer()
                
                Text("loginActivity.activeSession")
                    .font(.custom("Poppins-Bold", size: 10))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
            }
            
            SessionDetails(session: session)

            if session.isSuspicious {
                SessionSecurityHint(
                    text: NSLocalizedString("loginActivity.sessionAlert.locationChange", comment: "Location changed warning"),
                    color: .orange
                )
            } else if session.isNewDevice {
                SessionSecurityHint(
                    text: NSLocalizedString("loginActivity.sessionAlert.newDevice", comment: "New device warning"),
                    color: Color(hex: "4F46E5")
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct SessionSecurityHint: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)

            Text(text)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(color)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

struct SessionDetails: View {
    let session: LoginSession
    
    var body: some View {
        VStack(spacing: 8) {
            SessionDetailRow(icon: "location", title: NSLocalizedString("loginActivity.session.location", comment: "Location label"), value: session.location)
            SessionDetailRow(icon: "iphone", title: NSLocalizedString("loginActivity.session.device", comment: "Device label"), value: session.device)
            SessionDetailRow(icon: "network", title: NSLocalizedString("loginActivity.session.ip", comment: "IP label"), value: session.ipAddress)
            SessionDetailRow(icon: "clock", title: NSLocalizedString("loginActivity.session.startTime", comment: "Start time label"), value: session.timestamp.formatted(date: .abbreviated, time: .shortened))
        }
    }
}

struct SessionDetailRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .font(.system(size: 12))
                .frame(width: 16)
            
            Text(title)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
        }
    }
}

// MARK: - Models
struct LoginSession: Identifiable {
    let id: String
    let device: String
    let location: String
    let ipAddress: String
    let timestamp: Date
    let isActive: Bool
    let deviceIdentifier: String?
    let isSuspicious: Bool
    let isNewDevice: Bool
    let suspiciousReason: String?
}

// MARK: - ViewModel
class LoginActivityViewModel: ObservableObject {
    @Published var currentSession: LoginSession?
    @Published var otherSessions: [LoginSession] = []
    @Published var showLogoutAllAlert = false
    @Published var showError = false
    @Published var showLogoutSuccess = false
    @Published var errorMessage = ""
    @Published var isLoadingSession = false
    
    private let loginService = RealLoginActivityService.shared
    
    func loadLoginActivity(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("loginActivity.error.notAuthenticated", comment: "User not authenticated error"))
            DispatchQueue.main.async {
                self.isLoadingSession = false
                completion()
            }
            return
        }
        
        isLoadingSession = true

        loginService.fetchActiveSessions(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion()
                    return
                }

                defer {
                    self.isLoadingSession = false
                    completion()
                }

                switch result {
                case .success(let sessions):
                    self.applySessions(current: nil, activeSessions: sessions)
                case .failure(let error):
                    self.applySessions(current: nil, activeSessions: [])
                    self.showErrorAlert("Error al cargar sesiones: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @MainActor
    func refreshLoginActivity() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("loginActivity.error.notAuthenticated", comment: "User not authenticated error"))
            return
        }
        
        return await withCheckedContinuation { continuation in
            loginService.fetchActiveSessions(userId: userId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else {
                        continuation.resume()
                        return
                    }

                    switch result {
                    case .success(let sessions):
                        self.applySessions(current: nil, activeSessions: sessions)
                    case .failure(let error):
                        self.applySessions(current: nil, activeSessions: [])
                        self.showErrorAlert("Error al actualizar sesiones: \(error.localizedDescription)")
                    }

                    continuation.resume()
                }
            }
        }
    }
    
    func logoutAllSessions() {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("loginActivity.error.notAuthenticated", comment: "User not authenticated error"))
            return
        }
        
        loginService.invalidateAllSessions(userId: userId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showErrorAlert("Error al cerrar sesiones: \(error.localizedDescription)")
                } else {
                    self?.showLogoutSuccess = true
                    self?.currentSession = nil
                    self?.otherSessions = []
                }
            }
        }
    }
    
    private func applySessions(current: LoginSession?, activeSessions: [LoginSession]) {
        var resolvedCurrent = current
        var remaining = activeSessions

        if resolvedCurrent == nil,
           let currentDeviceId = UIDevice.current.identifierForVendor?.uuidString,
           let matchedSession = remaining.first(where: { $0.deviceIdentifier == currentDeviceId }) {
            resolvedCurrent = matchedSession
        }

        if let currentId = resolvedCurrent?.id,
           let index = remaining.firstIndex(where: { $0.id == currentId }) {
            remaining.remove(at: index)
        } else if resolvedCurrent == nil, let first = remaining.first {
            resolvedCurrent = first
            remaining.removeFirst()
        }

        if resolvedCurrent == nil {
            resolvedCurrent = makeLocalCurrentSession()
        }

        currentSession = resolvedCurrent
        otherSessions = Array(remaining.prefix(12))
    }

    private func makeLocalCurrentSession() -> LoginSession {
        let deviceName = "\(UIDevice.current.model) - iOS \(UIDevice.current.systemVersion)"
        let location = loginService.getCurrentLocationString()
        let timestamp = Auth.auth().currentUser?.metadata.lastSignInDate ?? Date()
        let deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString

        return LoginSession(
            id: "local_current_session",
            device: deviceName,
            location: location,
            ipAddress: "No disponible",
            timestamp: timestamp,
            isActive: true,
            deviceIdentifier: deviceIdentifier,
            isSuspicious: false,
            isNewDevice: false,
            suspiciousReason: nil
        )
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}
