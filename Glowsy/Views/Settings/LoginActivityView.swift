import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LoginActivityView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = LoginActivityViewModel()
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            if isLoading {
                ProgressView("Cargando actividad...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Info
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "shield.checkered")
                                    .foregroundColor(Color(hex: "00A896"))
                                    .font(.system(size: 20))
                                
                                Text("Actividad de Inicio de Sesión")
                                    .font(.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            
                            Text("Revisa cuándo y desde dónde has iniciado sesión en tu cuenta")
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "00A896").opacity(0.1))
                        )
                        .padding(.horizontal)
                        
                        // Current Session
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sesión Actual")
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            CurrentSessionCard(session: viewModel.currentSession)
                        }
                        .padding(.horizontal)
                        
                        // Recent Activity
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Actividad Reciente")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                                
                                Button("Cerrar todas las sesiones") {
                                    viewModel.showLogoutAllAlert = true
                                }
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(.red)
                            }
                            
                            if viewModel.loginActivities.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "clock.badge.checkmark")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    
                                    Text("No hay actividad reciente")
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.loginActivities) { activity in
                                        LoginActivityCard(activity: activity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Security Tips
                        SecurityTipsSection()
                            .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.top)
                }
            }
        }
        .navigationTitle("Actividad de Inicio")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.loadLoginActivity {
                isLoading = false
            }
        }
        .refreshable {
            await viewModel.refreshLoginActivity()
        }
        .alert("Cerrar todas las sesiones", isPresented: $viewModel.showLogoutAllAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Cerrar todas", role: .destructive) {
                viewModel.logoutAllSessions()
            }
        } message: {
            Text("Esto cerrará sesión en todos los dispositivos. Tendrás que volver a iniciar sesión.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Sesiones cerradas", isPresented: $viewModel.showLogoutSuccess) {
            Button("OK") { }
        } message: {
            Text("Se han cerrado todas las sesiones activas correctamente.")
        }
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
                
                Text("Sesión Activa")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text("ACTUAL")
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
                VStack(spacing: 8) {
                    SessionDetailRow(icon: "location", title: "Ubicación", value: session.location)
                    SessionDetailRow(icon: "iphone", title: "Dispositivo", value: session.device)
                    SessionDetailRow(icon: "network", title: "IP", value: session.ipAddress)
                    SessionDetailRow(icon: "clock", title: "Inicio", value: session.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Cargando información de sesión...")
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

struct LoginActivityCard: View {
    @Environment(\.colorScheme) var colorScheme
    let activity: LoginActivity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: activity.isSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(activity.isSuccessful ? .green : .red)
                    .font(.system(size: 16))
                
                Text(activity.isSuccessful ? "Inicio exitoso" : "Intento fallido")
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(activity.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
            }
            
            if activity.isSuccessful {
                VStack(spacing: 6) {
                    SessionDetailRow(icon: "location", title: "Ubicación", value: activity.location)
                    SessionDetailRow(icon: "iphone", title: "Dispositivo", value: activity.device)
                    SessionDetailRow(icon: "network", title: "IP", value: activity.ipAddress)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    
                    Text(activity.failureReason ?? "Credenciales incorrectas")
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.orange.opacity(0.1))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(activity.isSuccessful ? Color.gray.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                )
        )
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
            
            Spacer()
        }
    }
}

struct SecurityTipsSection: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(Color(hex: "00A896"))
                
                Text("Consejos de Seguridad")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            VStack(spacing: 12) {
                LoginSecurityTipRow(
                    icon: "checkmark.circle",
                    text: "Revisa regularmente tu actividad de inicio de sesión"
                )
                
                LoginSecurityTipRow(
                    icon: "checkmark.circle",
                    text: "Cierra sesión en dispositivos que no reconozcas"
                )
                
                LoginSecurityTipRow(
                    icon: "checkmark.circle",
                    text: "Usa autenticación en dos pasos para mayor seguridad"
                )
                
                LoginSecurityTipRow(
                    icon: "checkmark.circle",
                    text: "Cambia tu contraseña si detectas actividad sospechosa"
                )
                
                LoginSecurityTipRow(
                    icon: "checkmark.circle",
                    text: "No inicies sesión desde redes WiFi públicas"
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "00A896").opacity(0.1))
        )
    }
}

struct LoginSecurityTipRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "00A896"))
                .font(.system(size: 12))
            
            Text(text)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

// MARK: - Models
struct LoginSession {
    let id: String
    let device: String
    let location: String
    let ipAddress: String
    let timestamp: Date
    let isActive: Bool
}

struct LoginActivity: Identifiable {
    let id: String
    let timestamp: Date
    let device: String
    let location: String
    let ipAddress: String
    let isSuccessful: Bool
    let failureReason: String?
}

// MARK: - ViewModel
class LoginActivityViewModel: ObservableObject {
    @Published var currentSession: LoginSession?
    @Published var loginActivities: [LoginActivity] = []
    @Published var showLogoutAllAlert = false
    @Published var showError = false
    @Published var showLogoutSuccess = false
    @Published var errorMessage = ""
    @Published var isLoadingSession = false
    
    private let loginService = RealLoginActivityService.shared
    
    func loadLoginActivity(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert("Usuario no autenticado")
            completion()
            return
        }
        
        isLoadingSession = true
        
        // Load current session
        loginService.getCurrentSession(userId: userId) { [weak self] session in
            DispatchQueue.main.async {
                self?.currentSession = session
                self?.isLoadingSession = false
            }
        }
        
        // Load login activity history
        loginService.fetchLoginActivity(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let activities):
                    self?.loginActivities = activities
                case .failure(let error):
                    self?.showErrorAlert("Error al cargar actividad: \(error.localizedDescription)")
                }
                completion()
            }
        }
    }
    
    @MainActor
    func refreshLoginActivity() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert("Usuario no autenticado")
            return
        }
        
        return await withCheckedContinuation { continuation in
            // Refresh current session
            loginService.getCurrentSession(userId: userId) { [weak self] session in
                DispatchQueue.main.async {
                    self?.currentSession = session
                }
            }
            
            // Refresh login activity
            loginService.fetchLoginActivity(userId: userId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let activities):
                        self?.loginActivities = activities
                    case .failure(let error):
                        self?.showErrorAlert("Error al actualizar: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    func logoutAllSessions() {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert("Usuario no autenticado")
            return
        }
        
        loginService.invalidateAllSessions(userId: userId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showErrorAlert("Error al cerrar sesiones: \(error.localizedDescription)")
                } else {
                    self?.showLogoutSuccess = true
                    // Clear current data since user will be logged out
                    self?.currentSession = nil
                    self?.loginActivities = []
                }
            }
        }
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Extensions
extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
