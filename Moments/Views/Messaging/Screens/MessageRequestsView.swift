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
        VStack(spacing: 0) {
            headerView
            
            if messageRequestService.pendingRequests.isEmpty {
                emptyStateView
            } else {
                requestsListView
            }
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
        VStack(spacing: 8) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(adaptiveColors.primary)
                        .frame(width: 38, height: 38)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
                
                Spacer()
                
                Text("messageRequests.title")
                    .font(.system(size: legacyPoppinsSize(22), weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                Color.clear
                    .frame(width: 38, height: 38)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            
            if !messageRequestService.pendingRequests.isEmpty {
                HStack {
                    Spacer()
                    Text(String(format: NSLocalizedString("messageRequests.count", comment: "Request count"), messageRequestService.pendingRequests.count))
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(adaptiveColors.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.clear.momentsChromeGlass(in: Capsule()))
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Actions
    private func acceptRequest(_ request: MessageRequest) {
        messageRequestService.acceptRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Success
                    break
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func rejectRequest(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // success
                    break
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func blockUser(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // User blocked successfully
                    break
                case .failure(_):
                    break
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
            .padding(.horizontal, 14)
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
                } else {
                    Circle()
                        .fill(adaptiveColors.secondary.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                                                    Image(systemName: "person.fill")
                            .foregroundColor(adaptiveColors.secondary)
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(adaptiveColors.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgoString(from date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
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
                    gradient: Gradient(colors: [Color(hex: "007AFF").opacity(0.1), Color(hex: "02C39A").opacity(0.1)]),
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                        MessageTypeIconView(type: request.messageType, tintColor: adaptiveColors.primary)
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
    

    private func timeAgoString(from date: Date) -> String {
        MomentsFormat.relativeTime(from: date, style: .conversational(unitsStyle: .full))
    }
    
    // MARK: - Actions
    private func acceptRequest(_ request: MessageRequest) {
        messageRequestService.acceptRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    dismiss()
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func rejectRequest(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    dismiss()
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func blockUser(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    dismiss()
                case .failure(_):
                    break
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
