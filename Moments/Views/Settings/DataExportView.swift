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
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 50))
                            .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                        
                        Text(NSLocalizedString("dataExport.title", comment: "Data export title"))
                            .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        
                        Text(NSLocalizedString("dataExport.subtitle", comment: "Data export subtitle"))
                            .font(.system(size: legacyPoppinsSize(16)))
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                            
                            Text(NSLocalizedString("dataExport.whatIncludes.title", comment: "What includes download title"))
                                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
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
                            .fill(SettingsProfileColors.accent(colorScheme).opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    // Export Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("dataExport.options.title", comment: "Export options title"))
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        
                        VStack(spacing: 12) {
                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.complete.title", comment: "Complete export title"),
                                description: NSLocalizedString("dataExport.complete.description", comment: "Complete export description"),
                                icon: "doc.fill.badge.plus",
                                estimatedSize: NSLocalizedString("dataExport.complete.size", comment: "Complete export estimated size"),
                                isSelected: viewModel.selectedExportType == .complete,
                                onTap: { viewModel.selectedExportType = .complete }
                            )

                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.textOnly.title", comment: "Text only export title"),
                                description: NSLocalizedString("dataExport.textOnly.description", comment: "Text only export description"),
                                icon: "doc.text.fill",
                                estimatedSize: NSLocalizedString("dataExport.textOnly.size", comment: "Text only export estimated size"),
                                isSelected: viewModel.selectedExportType == .textOnly,
                                onTap: { viewModel.selectedExportType = .textOnly }
                            )

                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.mediaOnly.title", comment: "Media only export title"),
                                description: NSLocalizedString("dataExport.mediaOnly.description", comment: "Media only export description"),
                                icon: "photo.fill.on.rectangle.fill",
                                estimatedSize: NSLocalizedString("dataExport.mediaOnly.size", comment: "Media only export estimated size"),
                                isSelected: viewModel.selectedExportType == .mediaOnly,
                                onTap: { viewModel.selectedExportType = .mediaOnly }
                            )

                            ExportOptionCard(
                                title: NSLocalizedString("dataExport.conversationsOnly.title", comment: "Conversations only export title"),
                                description: NSLocalizedString("dataExport.conversationsOnly.description", comment: "Conversations only export description"),
                                icon: "lock.message.fill",
                                estimatedSize: NSLocalizedString("dataExport.conversationsOnly.size", comment: "Conversations only export estimated size"),
                                isSelected: viewModel.selectedExportType == .conversationsOnly,
                                onTap: { viewModel.selectedExportType = .conversationsOnly }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Format Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("dataExport.format.title", comment: "Data format title"))
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("dataExport.pin.title", comment: "Recovery PIN prompt title"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        Text(NSLocalizedString("dataExport.pin.description", comment: "Recovery PIN prompt description"))
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(.gray)

                        SecureField(
                            NSLocalizedString("dataExport.pin.placeholder", comment: "Recovery PIN placeholder"),
                            text: $viewModel.recoveryPIN
                        )
                        .keyboardType(.numberPad)
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                        )
                        .onChange(of: viewModel.recoveryPIN) { _, newValue in
                            viewModel.recoveryPIN = String(newValue.filter(\.isNumber).prefix(6))
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(SettingsProfileColors.accent(colorScheme).opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    // Privacy Notice
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shield.checkerboard")
                                .foregroundStyle(.orange)
                            
                            Text(NSLocalizedString("dataExport.privacy.title", comment: "Privacy notice title"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("dataExport.privacy.bullet1", comment: "Privacy bullet 1"))
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet2", comment: "Privacy bullet 2"))
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet3", comment: "Privacy bullet 3"))
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.gray)
                            
                            Text(NSLocalizedString("dataExport.privacy.bullet4", comment: "Privacy bullet 4"))
                                .font(.system(size: legacyPoppinsSize(14)))
                                .foregroundStyle(.gray)
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
                                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        }
                        .foregroundStyle(
                            viewModel.canRequestExport
                                ? SettingsProfileColors.accentContrastingText(colorScheme)
                                : .white
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.canRequestExport ? SettingsProfileColors.accent(colorScheme) : Color.gray)
                        )
                    }
                    .disabled(!viewModel.canRequestExport || viewModel.isProcessing)
                    .padding(.horizontal)
                    
                    if !viewModel.canRequestExport && viewModel.currentRequest == nil {
                        Text(String(format: NSLocalizedString("dataExport.alreadyRequested", comment: "Already requested message"), "\(viewModel.daysUntilNextRequest)"))
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundStyle(.orange)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
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

struct DataIncludeRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                .font(.system(size: 16))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(.gray)
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
                        .foregroundStyle(isSelected ? SettingsProfileColors.accent(colorScheme) : .gray)
                        .font(.system(size: 20))
                    
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                            .font(.system(size: 20))
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.gray)
                            .font(.system(size: 20))
                    }
                }
                
                Text(description)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text("dataExport.estimatedSize")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
                    
                    Text(estimatedSize)
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(SettingsProfileColors.accent(colorScheme))
                    
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? SettingsProfileColors.accent(colorScheme) : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(isSelected ? SettingsProfileColors.accentContrastingText(colorScheme) : (colorScheme == .dark ? .white : .black))

                Text(description)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(isSelected ? SettingsProfileColors.accentContrastingText(colorScheme).opacity(0.8) : .gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? SettingsProfileColors.accent(colorScheme) : Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? SettingsProfileColors.accent(colorScheme) : Color.gray.opacity(0.3), lineWidth: 1)
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
                    .foregroundStyle(.blue)
                
                                        Text(NSLocalizedString("dataExport.requestInProgress.title", comment: "Request in progress title"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("dataExport.status")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.gray)
                    
                    Text(request.status.displayName)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(request.status.color)
                }
                
                HStack {
                    Text("dataExport.requestedAt")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.gray)
                    
                    Text(MomentsFormat.smartDate(from: request.requestDate, context: .mediumDateTime))
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
                
                if let completionDate = request.estimatedCompletion {
                    HStack {
                        Text("dataExport.estimatedCompletion")
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundStyle(.gray)
                        
                        Text(MomentsFormat.smartDate(from: completionDate, context: .mediumDateTime))
                            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                                            Text(NSLocalizedString("dataExport.progress", comment: "Progress text"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
                    
                    Spacer()
                    
                    Text("\(Int(request.progress * 100))%")
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(.blue)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        
                        Rectangle()
                            .fill(.blue)
                            .frame(width: geometry.size.width * request.progress, height: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: request.progress), value: request.progress)
                    }
                }
                .frame(height: 6)
            }

            if case .ready = request.status, !request.downloadURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(request.downloadURLs.enumerated()), id: \.offset) { index, urlString in
                        Button(action: {
                            guard let url = URL(string: urlString) else { return }
                            UIApplication.shared.open(url)
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text(
                                    request.downloadURLs.count > 1
                                        ? String(format: NSLocalizedString("dataExport.downloadPart", comment: "Download part N of total"), index + 1, request.downloadURLs.count)
                                        : NSLocalizedString("dataExport.download", comment: "Download button")
                                )
                                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.top, 4)
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
    case conversationsOnly
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
    var downloadURLs: [String] = []
}

// MARK: - ViewModel
class DataExportViewModel: ObservableObject {
    @Published var selectedExportType: ExportType = .complete
    @Published var selectedFormat: ExportFormat = .json
    @Published var recoveryPIN: String = ""
    @Published var currentRequest: DataExportRequest?
    @Published var isProcessing = false
    @Published var showSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var canRequestExport = true
    @Published var daysUntilNextRequest = 0
    
    private let db = Firestore.firestore()
    private var currentRequestListener: ListenerRegistration?
    
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
                    if error != nil {
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
                                    self?.observeRequestProgress(requestId: document.documentID, userId: userId)
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
        case "uploading": status = .processing
        case "ready": status = .ready
        case "completed": status = .completed
        case "failed": status = .failed
        default: status = .pending
        }
        
        let progress = data["progress"] as? Double ?? 0.0
        let estimatedCompletion = (data["estimatedCompletion"] as? Timestamp)?.dateValue()
        let downloadURLs = (data["downloadParts"] as? [[String: Any]])?.compactMap { $0["downloadURL"] as? String } ?? []

        currentRequest = DataExportRequest(
            id: documentId,
            requestDate: requestDate,
            estimatedCompletion: estimatedCompletion,
            status: status,
            progress: progress,
            exportType: selectedExportType,
            format: selectedFormat,
            downloadURLs: downloadURLs
        )
    }
    
    func requestDataExport() {
        guard let userId = Auth.auth().currentUser?.uid else {
            showErrorAlert(NSLocalizedString("dataExport.userNotAuthenticated", comment: "User not authenticated error"))
            return
        }

        let trimmedPIN = recoveryPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedExportType == .conversationsOnly && trimmedPIN.isEmpty {
            showErrorAlert(NSLocalizedString("dataExport.conversationsOnly.pinRequired", comment: "PIN required for conversations-only export error"))
            return
        }

        isProcessing = true
        recoveryPIN = ""

        Task { @MainActor in
            if !trimmedPIN.isEmpty {
                let isValid = await EncryptionService.shared.verifyRecoveryPIN(trimmedPIN)
                guard isValid else {
                    self.isProcessing = false
                    self.showErrorAlert(NSLocalizedString("dataExport.pin.incorrect", comment: "Incorrect recovery PIN error"))
                    return
                }
            }
            self.submitExportRequest(userId: userId, pin: trimmedPIN.isEmpty ? nil : trimmedPIN)
        }
    }

    private func submitExportRequest(userId: String, pin: String?) {
        let requestId = UUID().uuidString
        let requestDate = Date()
        let estimatedCompletion = Calendar.current.date(byAdding: .day, value: 2, to: requestDate)

        var requestData: [String: Any] = [
            "id": requestId,
            "requestDate": Timestamp(date: requestDate),
            "estimatedCompletion": estimatedCompletion != nil ? Timestamp(date: estimatedCompletion!) : NSNull(),
            "status": "pending",
            "progress": 0.0,
            "exportType": exportTypeString(selectedExportType),
            "format": formatString(selectedFormat),
            "userEmail": Auth.auth().currentUser?.email ?? ""
        ]

        if let pin {
            requestData["pin"] = pin
        }

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
                        self?.observeRequestProgress(requestId: requestId, userId: userId)
                        
                        // El procesamiento se hace server-side con Cloud Functions
                        // al crear dataExportRequests/{requestId}.
                    }
                }
            }
    }

    deinit {
        currentRequestListener?.remove()
    }

    private func observeRequestProgress(requestId: String, userId: String) {
        currentRequestListener?.remove()
        currentRequestListener = db.collection("users")
            .document(userId)
            .collection("dataExportRequests")
            .document(requestId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self, let data = snapshot?.data() else { return }
                DispatchQueue.main.async {
                    self.loadCurrentRequest(from: data, documentId: requestId)
                    if let statusString = data["status"] as? String {
                        if statusString == "ready" || statusString == "completed" || statusString == "failed" {
                            self.currentRequestListener?.remove()
                            self.currentRequestListener = nil
                        }
                    }
                }
            }
    }
    
    private func exportTypeString(_ type: ExportType) -> String {
        switch type {
        case .complete: return "complete"
        case .textOnly: return "textOnly"
        case .mediaOnly: return "mediaOnly"
        case .conversationsOnly: return "conversationsOnly"
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
