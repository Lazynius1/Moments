import SwiftUI
import FirebaseAuth
import Kingfisher

struct MessageRequestsView: View {
    @EnvironmentObject var messageRequestService: MessageRequestService
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedRequest: MessageRequest?
    @State private var showingRequestDetail = false
    @State private var showingActionSheet = false
    @State private var actionRequest: MessageRequest?
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background adaptativo como MessagingView
                if colorScheme == .dark {
                    // Negro elegante tipo Instagram - más suave
                    Color(hex: "1A1A1A")
                        .ignoresSafeArea()
                } else {
                    // Modo claro: mantener el diseño original
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "00A896").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    // Floating blobs for depth
                    GeometryReader { geometry in
                        Circle()
                            .fill(Color(hex: "00A896").opacity(0.4))
                            .frame(width: 300, height: 300)
                            .blur(radius: 100)
                            .offset(x: -100, y: -100)
                        
                        Circle()
                            .fill(Color(hex: "02C39A").opacity(0.35))
                            .frame(width: 250, height: 250)
                            .blur(radius: 80)
                            .offset(x: geometry.size.width - 150, y: 200)
                        
                        Circle()
                            .fill(Color(hex: "F0F3BD").opacity(0.4))
                            .frame(width: 200, height: 200)
                            .blur(radius: 60)
                            .offset(x: 50, y: geometry.size.height - 200)
                    }
                }
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Content
                    if messageRequestService.pendingRequests.isEmpty {
                        emptyStateView
                    } else {
                        requestsListView
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if let userId = Auth.auth().currentUser?.uid {
                messageRequestService.listenToPendingRequests(for: userId)
            }
        }
        .onDisappear {
            messageRequestService.removeAllListeners()
        }
        .sheet(isPresented: $showingRequestDetail) {
            if let request = selectedRequest {
                RequestDetailView(request: request)
            }
        }
        .actionSheet(isPresented: $showingActionSheet) {
            if let request = actionRequest {
                ActionSheet(
                    title: Text("messageRequests.request.title"),
                    message: Text("messageRequests.request.message"),
                    buttons: [
                        .default(Text("messageRequests.accept")) {
                            acceptRequest(request)
                        },
                        .destructive(Text("messageRequests.reject")) {
                            rejectRequest(request)
                        },
                        .destructive(Text("messageRequests.blockUser")) {
                            blockUser(request)
                        },
                        .cancel()
                    ]
                )
            } else {
                ActionSheet(title: Text("messageRequests.error"), buttons: [.cancel()])
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(adaptiveColors.primary)
                }
                
                Spacer()
                
                Text("messageRequests.title")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                // Placeholder para mantener centrado el título
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Badge con número de solicitudes
            if !messageRequestService.pendingRequests.isEmpty {
                HStack {
                    Text(String(format: NSLocalizedString("messageRequests.count", comment: "Request count"), messageRequestService.pendingRequests.count))
                        .font(.caption)
                        .foregroundColor(adaptiveColors.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(hex: "FF9500").opacity(0.2))
                        )
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Actions
    private func acceptRequest(_ request: MessageRequest) {
        print("🔄 Botón de aceptar presionado para solicitud: \(request.senderUsername ?? "Unknown")")
        messageRequestService.acceptRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Solicitud aceptada")
                case .failure(let error):
                    print("❌ Error aceptando solicitud: \(error)")
                }
            }
        }
    }
    
    private func rejectRequest(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("❌ Solicitud rechazada")
                case .failure(let error):
                    print("❌ Error rechazando solicitud: \(error)")
                }
            }
        }
    }
    
    private func blockUser(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("🚫 Usuario bloqueado")
                case .failure(let error):
                    print("❌ Error bloqueando usuario: \(error)")
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "message.circle")
                .font(.system(size: 80))
                .foregroundColor(adaptiveColors.secondary.opacity(0.5))
            
                            Text("messageRequests.empty.title")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(adaptiveColors.primary)
            
                            Text("messageRequests.empty.description")
                .font(.body)
                .foregroundColor(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Requests List View
    private var requestsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messageRequestService.pendingRequests) { request in
                    RequestCardView(request: request) {
                        selectedRequest = request
                        showingRequestDetail = true
                    } onAction: {
                        actionRequest = request
                        showingActionSheet = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
}

// MARK: - Request Card View
struct RequestCardView: View {
    let request: MessageRequest
    let onTap: () -> Void
    let onAction: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile Image
                if let profileImagePath = request.senderProfileImagePath {
                    KFImage(URL(string: profileImagePath))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "FF9500"), lineWidth: 2)
                        )
                } else {
                    Circle()
                        .fill(adaptiveColors.secondary.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                                                    Image(systemName: "person.fill")
                            .foregroundColor(adaptiveColors.secondary)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "FF9500"), lineWidth: 2)
                        )
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(request.senderUsername ?? "Usuario")
                            .font(.headline)
                            .foregroundColor(adaptiveColors.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(timeAgoString(from: request.timestamp))
                            .font(.caption)
                            .foregroundColor(adaptiveColors.secondary)
                    }
                    
                    Text(request.messagePreview)
                        .font(.body)
                        .foregroundColor(adaptiveColors.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // Action Button
                Button(action: onAction) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(adaptiveColors.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(adaptiveColors.secondary.opacity(0.1))
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(adaptiveColors.cardBackground)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Request Detail View
struct RequestDetailView: View {
    let request: MessageRequest
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var messageRequestService: MessageRequestService
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "00A896").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // User Info
                    userInfoSection
                    
                    // Message Content
                    messageContentSection
                    
                    Spacer()
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding(20)
            }
            .navigationTitle("Solicitud de mensaje")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var userInfoSection: some View {
        VStack(spacing: 16) {
            // Profile Image
            if let profileImagePath = request.senderProfileImagePath {
                KFImage(URL(string: profileImagePath))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "FF9500"), lineWidth: 3)
                    )
            } else {
                Circle()
                    .fill(adaptiveColors.secondary.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(adaptiveColors.secondary)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "FF9500"), lineWidth: 3)
                    )
            }
            
            // Username
                            Text(request.senderUsername ?? "Usuario")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(adaptiveColors.primary)
            
            // Timestamp
                            Text(String(format: NSLocalizedString("messageRequests.sent", comment: "Sent time"), timeAgoString(from: request.timestamp)))
                .font(.caption)
                .foregroundColor(adaptiveColors.secondary)
        }
        .padding(.top, 20)
    }
    
    private var messageContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                            Text("messageRequests.message")
                .font(.headline)
                .foregroundColor(adaptiveColors.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                switch request.messageType {
                case .text:
                    Text(request.message)
                        .font(.body)
                        .foregroundColor(adaptiveColors.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(adaptiveColors.cardBackground)
                        )
                    
                case .image:
                    if let mediaUrl = request.mediaUrl {
                        KFImage(URL(string: mediaUrl))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                case .video:
                    VStack {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(adaptiveColors.primary)
                        Text("messageRequests.video")
                            .font(.caption)
                            .foregroundColor(adaptiveColors.secondary)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(adaptiveColors.cardBackground)
                    )
                    
                default:
                    HStack {
                        Image(systemName: iconForMessageType(request.messageType))
                            .foregroundColor(adaptiveColors.primary)
                        Text(request.messagePreview)
                            .font(.body)
                            .foregroundColor(adaptiveColors.primary)
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(adaptiveColors.cardBackground)
                    )
                }
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Accept Button
            Button(action: { acceptRequest(request) }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("messageRequests.accept")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "34C759"))
                )
            }
            
            // Reject Button
            Button(action: { rejectRequest(request) }) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("messageRequests.reject")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "FF3B30"))
                )
            }
            
            // Block Button
            Button(action: { blockUser(request) }) {
                HStack {
                    Image(systemName: "slash.circle.fill")
                    Text("messageRequests.blockUser")
                }
                .font(.subheadline)
                .foregroundColor(adaptiveColors.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(adaptiveColors.secondary, lineWidth: 1)
                )
            }
        }
        .padding(.bottom, 20)
    }
    
    private func iconForMessageType(_ type: MessageType) -> String {
        switch type {
        case .text: return "text.bubble"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .gif: return "photo.on.rectangle.angled"
        case .file: return "doc"
        case .location: return "location"
        case .sticker: return "face.smiling"
        case .ephemeral: return "timer"
        case .sharedMoment: return "square.and.arrow.up"
        case .viewOnceImage: return "camera.circle"
        case .viewOnceVideo: return "video.circle"
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Actions
    private func acceptRequest(_ request: MessageRequest) {
        print("🔄 Botón de aceptar presionado para solicitud: \(request.senderUsername ?? "Unknown")")
        messageRequestService.acceptRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ Solicitud aceptada")
                    dismiss()
                case .failure(let error):
                    print("❌ Error aceptando solicitud: \(error)")
                }
            }
        }
    }
    
    private func rejectRequest(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("❌ Solicitud rechazada")
                    dismiss()
                case .failure(let error):
                    print("❌ Error rechazando solicitud: \(error)")
                }
            }
        }
    }
    
    private func blockUser(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("🚫 Usuario bloqueado")
                    dismiss()
                case .failure(let error):
                    print("❌ Error bloqueando usuario: \(error)")
                }
            }
        }
    }
}

#Preview {
    MessageRequestsView()
        .environmentObject(MessageRequestService())
        .environmentObject(AuthService())
}
