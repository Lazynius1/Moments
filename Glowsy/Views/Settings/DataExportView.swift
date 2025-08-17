import SwiftUI
import FirebaseAuth
import MessageUI
import FirebaseFirestore

struct DataExportView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = DataExportViewModel()
    @State private var showMailComposer = false
    
    var body: some View {
        NavigationView {
            ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 50))
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text(NSLocalizedString("dataExport.title", comment: "Data export title"))
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(NSLocalizedString("dataExport.subtitle", comment: "Data export subtitle"))
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(Color(hex: "00A896"))
                            
                            Text(NSLocalizedString("dataExport.whatIncludes.title", comment: "What includes download title"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        
                        VStack(spacing: 12) {
                            DataIncludeRow(icon: "person.fill", title: NSLocalizedString("dataExport.profileInfo.title", comment: "Profile info title"), description: NSLocalizedString("dataExport.profileInfo.description", comment: "Profile info description"))
                            DataIncludeRow(icon: "square.grid.3x3.fill", title: NSLocalizedString("dataExport.posts.title", comment: "Posts title"), description: NSLocalizedString("dataExport.posts.description", comment: "Posts description"))
                            DataIncludeRow(icon: "circle.dashed", title: NSLocalizedString("dataExport.stories.title", comment: "Stories title"), description: NSLocalizedString("dataExport.stories.description", comment: "Stories description"))
                            DataIncludeRow(icon: "message.fill", title: NSLocalizedString("dataExport.messages.title", comment: "Messages title"), description: NSLocalizedString("dataExport.messages.description", comment: "Messages description"))
                            DataIncludeRow(icon: "heart.fill", title: NSLocalizedString("dataExport.interactions.title", comment: "Interactions title"), description: NSLocalizedString("dataExport.interactions.description", comment: "Interactions description"))
                            DataIncludeRow(icon: "person.2.fill", title: NSLocalizedString("dataExport.connections.title", comment: "Connections title"), description: NSLocalizedString("dataExport.connections.description", comment: "Connections description"))
                            DataIncludeRow(icon: "clock.fill", title: NSLocalizedString("dataExport.activity.title", comment: "Activity title"), description: NSLocalizedString("dataExport.activity.description", comment: "Activity description"))
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "00A896").opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    // Export Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("dataExport.options.title", comment: "Export options title"))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        VStack(spacing: 12) {
                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.complete.title", comment: "Complete export title"),
                                description: NSLocalizedString("dataExport.complete.description", comment: "Complete export description"),
                                icon: "doc.fill.badge.plus",
                                estimatedSize: "50-200 MB",
                                isSelected: viewModel.selectedExportType == .complete,
                                onTap: { viewModel.selectedExportType = .complete }
                            )
                            
                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.textOnly.title", comment: "Text only export title"),
                                description: NSLocalizedString("dataExport.textOnly.description", comment: "Text only export description"),
                                icon: "doc.text.fill",
                                estimatedSize: "1-5 MB",
                                isSelected: viewModel.selectedExportType == .textOnly,
                                onTap: { viewModel.selectedExportType = .textOnly }
                            )
                            
                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.mediaOnly.title", comment: "Media only export title"),
                                description: NSLocalizedString("dataExport.mediaOnly.description", comment: "Media only export description"),
                                icon: "photo.fill.on.rectangle.fill",
                                estimatedSize: "10-150 MB",
                                isSelected: viewModel.selectedExportType == .mediaOnly,
                                onTap: { viewModel.selectedExportType = .mediaOnly }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Format Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("dataExport.format.title", comment: "Data format title"))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        HStack(spacing: 12) {
                            FormatButton(
                                title: NSLocalizedString("dataExport.format.json.title", comment: "JSON format title"),
                                description: NSLocalizedString("dataExport.format.json.description", comment: "JSON format description"),
                                isSelected: viewModel.selectedFormat == .json,
                                onTap: { viewModel.selectedFormat = .json }
                            )
                            
                            FormatButton(
                                title: NSLocalizedString("dataExport.format.csv.title", comment: "CSV format title"),
                                description: NSLocalizedString("dataExport.format.csv.description", comment: "CSV format description"),
                                isSelected: viewModel.selectedFormat == .csv,
                                onTap: { viewModel.selectedFormat = .csv }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Current Request Status
                    if let currentRequest = viewModel.currentRequest {
                        CurrentRequestSection(request: currentRequest)
                            .padding(.horizontal)
                    }
                    
                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shield.checkerboard")
                                .foregroundColor(.orange)
                            
                            Text(NSLocalizedString("dataExport.privacy.title", comment: "Privacy notice title"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("dataExport.privacy.bullet1", comment: "Privacy bullet 1"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet2", comment: "Privacy bullet 2"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet3", comment: "Privacy bullet 3"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet4", comment: "Privacy bullet 4"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal)
                    
                    // Request Button
                    Button(action: {
                        if viewModel.canRequestExport {
                            viewModel.requestDataExport()
                        }
                    }) {
                        HStack {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            
                            Text(viewModel.isProcessing ? NSLocalizedString("dataExport.processing", comment: "Processing text") : NSLocalizedString("dataExport.requestDownload", comment: "Request download text"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.canRequestExport ? Color(hex: "00A896") : Color.gray)
                        )
                    }
                    .disabled(!viewModel.canRequestExport || viewModel.isProcessing)
                    .padding(.horizontal)
                    
                    if !viewModel.canRequestExport && viewModel.currentRequest == nil {
                        Text(String(format: NSLocalizedString("dataExport.alreadyRequested", comment: "Already requested message"), "\(viewModel.daysUntilNextRequest)"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top)
            }
        }
        .navigationTitle(NSLocalizedString("dataExport.navigation.title", comment: "Download data navigation title"))
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
                                            colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                }
            }
        }
        .onAppear {
            viewModel.checkExistingRequests()
        }
        .alert(NSLocalizedString("dataExport.success.title", comment: "Success alert title"), isPresented: $viewModel.showSuccess) {
            Button(NSLocalizedString("dataExport.ok", comment: "OK button")) { }
        } message: {
            Text(NSLocalizedString("dataExport.success.message", comment: "Success message"))
        }
        .alert(NSLocalizedString("dataExport.error.title", comment: "Error alert title"), isPresented: $viewModel.showError) {
            Button(NSLocalizedString("dataExport.ok", comment: "OK button")) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        }
    }
}

struct DataIncludeRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "00A896"))
                .font(.system(size: 16))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

struct ExportOptionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let description: String
    let icon: String
    let estimatedSize: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(isSelected ? Color(hex: "00A896") : .gray)
                        .font(.system(size: 20))
                    
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "00A896"))
                            .font(.system(size: 20))
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.system(size: 20))
                    }
                }
                
                Text(description)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text("Tamaño estimado:")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                    
                    Text(estimatedSize)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(Color(hex: "00A896"))
                    
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color(hex: "00A896") : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FormatButton: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let description: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                
                Text(description)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "00A896") : Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color(hex: "00A896") : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CurrentRequestSection: View {
    @Environment(\.colorScheme) var colorScheme
    let request: DataExportRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                
                                        Text(NSLocalizedString("dataExport.requestInProgress.title", comment: "Request in progress title"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Estado:")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    Text(request.status.displayName)
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(request.status.color)
                }
                
                HStack {
                    Text("Solicitado:")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    Text(request.requestDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                if let completionDate = request.estimatedCompletion {
                    HStack {
                        Text("Estimado:")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                        
                        Text(completionDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                                            Text(NSLocalizedString("dataExport.progress", comment: "Progress text"))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("\(Int(request.progress * 100))%")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.blue)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        Rectangle()
                            .fill(.blue)
                            .frame(width: geometry.size.width * request.progress, height: 6)
                            .cornerRadius(3)
                            .animation(.easeInOut(duration: 0.3), value: request.progress)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Models
enum ExportType {
    case complete
    case textOnly
    case mediaOnly
}

enum ExportFormat {
    case json
    case csv
}

enum ExportStatus {
    case pending
    case processing
    case ready
    case completed
    case failed
    
    var displayName: String {
        switch self {
        case .pending: return NSLocalizedString("dataExport.status.pending", comment: "Pending status")
        case .processing: return NSLocalizedString("dataExport.status.processing", comment: "Processing status")
        case .ready: return NSLocalizedString("dataExport.status.ready", comment: "Ready status")
        case .completed: return NSLocalizedString("dataExport.status.completed", comment: "Completed status")
        case .failed: return NSLocalizedString("dataExport.status.failed", comment: "Failed status")
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .orange
        case .processing: return .blue
        case .ready: return .green
        case .completed: return .gray
        case .failed: return .red
        }
    }
}

struct DataExportRequest {
    let id: String
    let requestDate: Date
    let estimatedCompletion: Date?
    let status: ExportStatus
    let progress: Double
    let exportType: ExportType
    let format: ExportFormat
}

// MARK: - ViewModel
class DataExportViewModel: ObservableObject {
    @Published var selectedExportType: ExportType = .complete
    @Published var selectedFormat: ExportFormat = .json
    @Published var currentRequest: DataExportRequest?
    @Published var isProcessing = false
    @Published var showSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var canRequestExport = true
    @Published var daysUntilNextRequest = 0
    
    private let db = Firestore.firestore()
    private let exportService = DataExportService()
    private let backgroundManager = BackgroundExportManager.shared
    
    func checkExistingRequests() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Check for existing requests in the last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        db.collection("users").document(userId).collection("dataExportRequests")
            .whereField("requestDate", isGreaterThan: thirtyDaysAgo)
            .order(by: "requestDate", descending: true)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error checking existing requests: \(error)")
                        return
                    }
                    
                    if let document = snapshot?.documents.first {
                        let data = document.data()
                        if let requestDate = (data["requestDate"] as? Timestamp)?.dateValue() {
                            let daysSinceRequest = Calendar.current.dateComponents([.day], from: requestDate, to: Date()).day ?? 0
                            
                            if daysSinceRequest < 30 {
                                self?.canRequestExport = false
                                self?.daysUntilNextRequest = 30 - daysSinceRequest
                                
                                // If request is still in progress, show current request
                                if let statusString = data["status"] as? String,
                                   statusString != "completed" && statusString != "failed" {
                                    self?.loadCurrentRequest(from: data, documentId: document.documentID)
                                }
                            }
                        }
                    }
                }
            }
    }
    
    private func loadCurrentRequest(from data: [String: Any], documentId: String) {
        guard let requestDate = (data["requestDate"] as? Timestamp)?.dateValue(),
              let statusString = data["status"] as? String else { return }
        
        let status: ExportStatus
        switch statusString {
        case "pending": status = .pending
        case "processing": status = .processing
        case "ready": status = .ready
        case "completed": status = .completed
        case "failed": status = .failed
        default: status = .pending
        }
        
        let progress = data["progress"] as? Double ?? 0.0
        let estimatedCompletion = (data["estimatedCompletion"] as? Timestamp)?.dateValue()
        
        currentRequest = DataExportRequest(
            id: documentId,
            requestDate: requestDate,
            estimatedCompletion: estimatedCompletion,
            status: status,
            progress: progress,
            exportType: selectedExportType,
            format: selectedFormat
        )
    }
    
    func requestDataExport() {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("dataExport.userNotAuthenticated", comment: "User not authenticated error"))
            return
        }
        
        isProcessing = true
        
        let requestId = UUID().uuidString
        let requestDate = Date()
        let estimatedCompletion = Calendar.current.date(byAdding: .day, value: 2, to: requestDate)
        
        let requestData: [String: Any] = [
            "id": requestId,
            "requestDate": Timestamp(date: requestDate),
            "estimatedCompletion": estimatedCompletion != nil ? Timestamp(date: estimatedCompletion!) : NSNull(),
            "status": "pending",
            "progress": 0.0,
            "exportType": exportTypeString(selectedExportType),
            "format": formatString(selectedFormat),
            "userEmail": Auth.auth().currentUser?.email ?? ""
        ]
        
        db.collection("users").document(userId).collection("dataExportRequests").document(requestId)
            .setData(requestData) { [weak self] error in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    
                    if let error = error {
                        self?.showErrorAlert("Error al enviar solicitud: \(error.localizedDescription)")
                    } else {
                        self?.showSuccess = true
                        self?.canRequestExport = false
                        self?.daysUntilNextRequest = 30
                        
                        // Create current request object
                        self?.currentRequest = DataExportRequest(
                            id: requestId,
                            requestDate: requestDate,
                            estimatedCompletion: estimatedCompletion,
                            status: .pending,
                            progress: 0.0,
                            exportType: self?.selectedExportType ?? .complete,
                            format: self?.selectedFormat ?? .json
                        )
                        
                        // Start background processing
                        self?.backgroundManager.processExportRequest(
                            requestId: requestId,
                            userId: userId,
                            exportType: self?.selectedExportType ?? .complete,
                            format: self?.selectedFormat ?? .json
                        )
                    }
                }
            }
    }
    
    private func exportTypeString(_ type: ExportType) -> String {
        switch type {
        case .complete: return "complete"
        case .textOnly: return "textOnly"
        case .mediaOnly: return "mediaOnly"
        }
    }
    
    private func formatString(_ format: ExportFormat) -> String {
        switch format {
        case .json: return "json"
        case .csv: return "csv"
        }
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
}
