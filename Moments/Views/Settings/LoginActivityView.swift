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
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
                
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
                                
                                CurrentSessionCard(
                                    session: viewModel.currentSession,
                                    onLogout: viewModel.currentSession.map { session in
                                        { viewModel.requestLogout(session: session) }
                                    }
                                )
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
                                            SessionCard(session: session) {
                                                viewModel.requestLogout(session: session)
                                            }
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
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
                Text(viewModel.logoutSuccessMessage)
            }
            .alert(
                NSLocalizedString("loginActivity.logoutSession.title", comment: "Logout session title"),
                isPresented: Binding(
                    get: { viewModel.sessionPendingLogout != nil },
                    set: { if !$0 { viewModel.sessionPendingLogout = nil } }
                )
            ) {
                Button(NSLocalizedString("loginActivity.cancel", comment: "Cancel"), role: .cancel) {
                    viewModel.sessionPendingLogout = nil
                }
                Button(NSLocalizedString("loginActivity.logoutSession.confirm", comment: "Logout session confirm"), role: .destructive) {
                    viewModel.confirmLogoutPendingSession()
                }
            } message: {
                if let session = viewModel.sessionPendingLogout {
                    if viewModel.isCurrentDeviceSession(session) {
                        Text("loginActivity.logoutSession.currentMessage")
                    } else {
                        Text(String(
                            format: NSLocalizedString("loginActivity.logoutSession.message", comment: "Logout session message"),
                            session.device
                        ))
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("loginActivity.title")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text("loginActivity.description")
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
        }
        .padding(.horizontal)
    }
}

struct CurrentSessionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let session: LoginSession?
    var onLogout: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("loginActivity.activeSession")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                if session != nil {
                    Text("loginActivity.current")
                        .font(.custom("Poppins-Bold", size: 11))
                        .foregroundColor(.green)
                }
            }
            
            if let session = session {
                SessionDetails(session: session)

                if let onLogout {
                    SessionLogoutButton(action: onLogout)
                        .padding(.top, 4)
                }
            } else {
                Text("loginActivity.noCurrentSession")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.2)
        }
    }
}

struct SessionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let session: LoginSession
    var onLogout: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.device)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(session.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
            }
            
            SessionDetails(session: session)

            if let onLogout {
                SessionLogoutButton(action: onLogout)
            }

            if session.isSuspicious {
                SessionSecurityHint(
                    text: NSLocalizedString("loginActivity.sessionAlert.locationChange", comment: "Location changed warning"),
                    color: .orange
                )
            } else if session.isNewDevice {
                SessionSecurityHint(
                    text: NSLocalizedString("loginActivity.sessionAlert.newDevice", comment: "New device warning"),
                    color: SettingsProfileColors.accent(colorScheme)
                )
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.16)
        }
    }
}

private struct SessionLogoutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("loginActivity.logoutSession")
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

struct SessionSecurityHint: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(color)
                .lineLimit(2)
        }
        .padding(.top, 2)
    }
}

struct SessionDetails: View {
    let session: LoginSession

    private var visibleLocation: String {
        let trimmed = session.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("loginActivity.location.unavailable", value: "Ubicación no disponible", comment: "") : trimmed
    }

    private var visibleIP: String {
        let trimmed = session.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("loginActivity.ip.unavailable", value: "IP no disponible", comment: "") : trimmed
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(NSLocalizedString("loginActivity.session.location", value: "Ubicación", comment: "Location label"))
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.secondary.opacity(0.95))
                Text(visibleLocation)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(visibleIP)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("•")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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
    @Published var sessionPendingLogout: LoginSession?
    @Published var showError = false
    @Published var showLogoutSuccess = false
    @Published var logoutSuccessMessage = ""
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
    
    func requestLogout(session: LoginSession) {
        sessionPendingLogout = session
    }

    func isCurrentDeviceSession(_ session: LoginSession) -> Bool {
        guard let currentSession else { return false }
        return isSameSession(session, currentSession)
    }

    func confirmLogoutPendingSession() {
        guard let session = sessionPendingLogout else { return }
        sessionPendingLogout = nil
        logoutSession(session)
    }

    func logoutSession(_ session: LoginSession) {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("loginActivity.error.notAuthenticated", comment: "User not authenticated error"))
            return
        }

        let signsOutLocally = isCurrentDeviceSession(session)
        loginService.invalidateSession(
            userId: userId,
            session: session,
            signOutIfCurrentDevice: signsOutLocally
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.showErrorAlert(
                        String(
                            format: NSLocalizedString("loginActivity.logoutSession.error", comment: "Logout session error"),
                            error.localizedDescription
                        )
                    )
                    return
                }

                self.logoutSuccessMessage = NSLocalizedString(
                    "loginActivity.logoutSuccess.single.message",
                    comment: "Single session closed success"
                )
                self.showLogoutSuccess = true

                if signsOutLocally {
                    self.currentSession = nil
                    self.otherSessions = []
                } else {
                    self.otherSessions.removeAll { self.isSameSession($0, session) }
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
                    self?.logoutSuccessMessage = NSLocalizedString(
                        "loginActivity.logoutSuccess.message",
                        comment: "All sessions closed success"
                    )
                    self?.showLogoutSuccess = true
                    self?.currentSession = nil
                    self?.otherSessions = []
                }
            }
        }
    }
    
    private func applySessions(current: LoginSession?, activeSessions: [LoginSession]) {
        let dedupedSessions = dedupeSessions(activeSessions)
        var resolvedCurrent = current
        var remaining = dedupedSessions

        if resolvedCurrent == nil,
           let currentDeviceId = UIDevice.current.identifierForVendor?.uuidString,
           let matchedSession = remaining.first(where: {
               ($0.deviceIdentifier ?? "").lowercased() == currentDeviceId.lowercased()
           }) {
            resolvedCurrent = matchedSession
        }

        if resolvedCurrent == nil, let first = remaining.first {
            resolvedCurrent = first
        }

        if let resolvedCurrent {
            remaining.removeAll { isSameSession($0, resolvedCurrent) }
        }

        if resolvedCurrent == nil {
            resolvedCurrent = makeLocalCurrentSession()
        }

        currentSession = resolvedCurrent
        otherSessions = Array(remaining.prefix(12))
    }

    private func dedupeSessions(_ sessions: [LoginSession]) -> [LoginSession] {
        var byKey: [String: LoginSession] = [:]
        for session in sessions {
            let key = canonicalSessionKey(for: session)
            if let existing = byKey[key], existing.timestamp >= session.timestamp {
                continue
            }
            byKey[key] = session
        }
        return byKey.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func isSameSession(_ lhs: LoginSession, _ rhs: LoginSession) -> Bool {
        canonicalSessionKey(for: lhs) == canonicalSessionKey(for: rhs)
    }

    private func canonicalSessionKey(for session: LoginSession) -> String {
        let fingerprint = (session.deviceIdentifier ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !fingerprint.isEmpty {
            return "fingerprint:\(fingerprint)"
        }

        let device = session.device
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ip = normalizeIP(session.ipAddress)
        if !ip.isEmpty {
            return "device_ip:\(device)|\(ip)"
        }

        let location = normalizeLocation(session.location)
        return "device_location:\(device)|\(location)"
    }

    private func normalizeIP(_ ip: String) -> String {
        let value = ip.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "no disponible" || value == "n/a" || value == "unknown" {
            return ""
        }
        return value
    }

    private func normalizeLocation(_ location: String) -> String {
        let folded = location
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if folded.isEmpty || folded.contains("ubicacion no disponible") || folded.contains("unknown") {
            return "unknown"
        }
        return folded
    }

    private func makeLocalCurrentSession() -> LoginSession {
        let deviceName = loginService.currentDeviceDisplayName()
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
