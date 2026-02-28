import SwiftUI
import FirebaseAuth

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
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "4F46E5").opacity(0.3), Color(hex: "4F46E5").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "4F46E5"))
                        }
                    }
                }
            }
            .onAppear {
                viewModel.loadLoginActivity {
                    isLoading = false
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
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                
                Text("loginActivity.activeSession")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
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
            
            if let session = session {
                SessionDetails(session: session)
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("loginActivity.loading")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                }
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
            completion()
            return
        }
        
        isLoadingSession = true
        
        let group = DispatchGroup()
        var fetchedCurrent: LoginSession?
        var fetchedActiveSessions: [LoginSession] = []
        
        group.enter()
        loginService.getCurrentSession(userId: userId) { session in
            fetchedCurrent = session
            group.leave()
        }
        
        group.enter()
        loginService.fetchActiveSessions(userId: userId) { [weak self] result in
            switch result {
            case .success(let sessions):
                fetchedActiveSessions = sessions
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.showErrorAlert("Error al cargar sesiones: \(error.localizedDescription)")
                }
            }
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.applySessions(current: fetchedCurrent, activeSessions: fetchedActiveSessions)
            self?.isLoadingSession = false
            completion()
        }
    }
    
    @MainActor
    func refreshLoginActivity() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("loginActivity.error.notAuthenticated", comment: "User not authenticated error"))
            return
        }
        
        return await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            var fetchedCurrent: LoginSession?
            var fetchedActiveSessions: [LoginSession] = []
            
            group.enter()
            loginService.getCurrentSession(userId: userId) { session in
                fetchedCurrent = session
                group.leave()
            }
            
            group.enter()
            loginService.fetchActiveSessions(userId: userId) { [weak self] result in
                switch result {
                case .success(let sessions):
                    fetchedActiveSessions = sessions
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.showErrorAlert("Error al actualizar sesiones: \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
            
            group.notify(queue: .main) { [weak self] in
                self?.applySessions(current: fetchedCurrent, activeSessions: fetchedActiveSessions)
                continuation.resume()
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
        
        if let currentId = resolvedCurrent?.id,
           let index = remaining.firstIndex(where: { $0.id == currentId }) {
            remaining.remove(at: index)
        } else if resolvedCurrent == nil, let first = remaining.first {
            resolvedCurrent = first
            remaining.removeFirst()
        }
        
        currentSession = resolvedCurrent
        otherSessions = Array(remaining.prefix(12))
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}
