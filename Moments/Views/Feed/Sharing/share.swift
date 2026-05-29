import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Photos
import PhotosUI
import UIKit
import Foundation
import AVKit

private func buildMomentShareURLString(_ moment: Moment) -> String {
    guard let momentId = moment.id else {
        return "https://momentsapp.app/moment"
    }
    
    var components = URLComponents(string: "https://momentsapp.app/moment/\(momentId)")
    if !moment.authorId.isEmpty {
        components?.queryItems = [URLQueryItem(name: "a", value: moment.authorId)]
    }
    
    return components?.url?.absoluteString ?? "https://momentsapp.app/moment/\(momentId)"
}

// MARK: - ✅ Modern Share Bottom Sheet (Rediseñado)
enum ShareSheetViewState {
    case main
    case messaging
}

struct ModernShareBottomSheet: View {
    let moment: Moment
    @Binding var isPresented: Bool
    @State private var viewState: ShareSheetViewState = .main
    @State private var showStoryCreator = false
    
    var body: some View {
        ZStack {
            // Fondo transparente para cerrar
            Color.clear
                .ignoresSafeArea()
                .onTapGesture {
                    if viewState == .main {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewState = .main
                        }
                    }
                }
            
            VStack {
                Spacer()
                
                ZStack {
                    if viewState == .main {
                        MainActionsView(
                            moment: moment,
                            onClose: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            },
                            onSendMessage: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .messaging
                                }
                            },
                            onAddToStory: { showStoryCreator = true },
                            onExternalShare: { shareExternally() }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                    } else {
                        ModernShareSheet(
                            moment: moment,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .main
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .background(
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .fullScreenCover(isPresented: $showStoryCreator) {
            AddToStoryView(moment: moment)
        }
    }
    
    private func shareExternally() {
        guard moment.id != nil else { return }
        let freshUsername = UserCacheService.shared.getCachedUser(userId: moment.authorId)?.username ?? moment.username
        let shareText = String(format: NSLocalizedString("share.moment.by", comment: ""), freshUsername)
        let shareUrl = URL(string: buildMomentShareURLString(moment))!
        
        let activityController = UIActivityViewController(
            activityItems: [shareText, shareUrl],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let presenter = topViewController(from: window.rootViewController) {
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(activityController, animated: true)
        }
        
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}


// MARK: - Main Actions View
struct MainActionsView: View {
    let moment: Moment
    let onClose: () -> Void
    let onSendMessage: () -> Void
    let onAddToStory: () -> Void
    let onExternalShare: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                StoryRingAvatarView(
                    userId: moment.authorId,
                    size: 44,
                    lineWidth: 2.4
                )
                .onTapGesture {
                    guard !moment.authorId.isEmpty else { return }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToProfile"),
                        object: moment.authorId
                    )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("share.moment.title")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.primary)
                    
                    LiveUsernameContent(userId: moment.authorId, fallbackUsername: moment.username) { username in
                        Text(String(format: NSLocalizedString("share.moment.from", comment: ""), username))
                    }
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Actions
            VStack(spacing: 8) {
                ShareActionButton(
                    icon: "paperplane.fill",
                    title: NSLocalizedString("messaging.sendMessage", comment: ""),
                    subtitle: NSLocalizedString("contextMenu.shareMoment.subtitle", comment: ""),
                    iconColor: .primary,
                    isPrimary: false,
                    action: onSendMessage
                )
                
                ShareActionButton(
                    icon: "plus.circle.fill",
                    title: NSLocalizedString("share.addToStory", comment: ""),
                    subtitle: NSLocalizedString("creator.story.subtitle", comment: ""),
                    iconColor: .blue,
                    usesStoryRingIcon: true,
                    isPrimary: false,
                    action: onAddToStory
                )
                
                ShareActionButton(
                    icon: "square.and.arrow.up",
                    title: NSLocalizedString("contextMenu.copyLink", comment: ""),
                    subtitle: NSLocalizedString("contextMenu.copyLink.subtitle", comment: ""),
                    iconColor: .purple,
                    isPrimary: false,
                    action: onExternalShare
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
}


// MARK: - ✅ Share Action Button (Rediseñado como Context Menu)
struct ShareActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    var usesStoryRingIcon: Bool = false
    let isPrimary: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        MomentRowButton(action: action) {
            HStack(spacing: 16) {
                Group {
                    if usesStoryRingIcon {
                        StoryAddGlyph(size: 24)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
    }
}

private struct StoryAddGlyph: View {
    let size: CGFloat
    private let lineWidth: CGFloat = 2.1
    private let gapAngle: Double = 16
    private let privacyService = PrivacyService()

    @State private var snapshot = StoryRingSnapshot(
        hasStory: false,
        hasUnseenStory: false,
        storyCount: 0,
        storyViewedStatus: [],
        storyAudiences: []
    )

    private var displayedSegmentCount: Int {
        max(snapshot.storyCount + 1, 1)
    }

    var body: some View {
        ZStack {
            if displayedSegmentCount == 1 {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            } else {
                ForEach(0..<displayedSegmentCount, id: \.self) { index in
                    StoryAddGlyphSegment(
                        index: index,
                        totalSegments: displayedSegmentCount,
                        gapAngle: gapAngle,
                        lineWidth: lineWidth
                    )
                }
            }

            Circle()
                .fill(Color(.systemBackground).opacity(0.9))
                .frame(width: size * 0.44, height: size * 0.44)

            Image(systemName: "plus")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-90))
        .onAppear {
            resolveOwnStorySnapshot()
        }
    }

    private func resolveOwnStorySnapshot() {
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            snapshot = StoryRingSnapshot(
                hasStory: false,
                hasUnseenStory: false,
                storyCount: 0,
                storyViewedStatus: [],
                storyAudiences: []
            )
            return
        }

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: currentUserId,
            privacyService: privacyService
        ) { resolvedSnapshot in
            self.snapshot = resolvedSnapshot
        }
    }
}

private struct StoryAddGlyphSegment: View {
    let index: Int
    let totalSegments: Int
    let gapAngle: Double
    let lineWidth: CGFloat

    private var startTrim: CGFloat {
        let segmentAngle = 360.0 / Double(totalSegments)
        return CGFloat((Double(index) * segmentAngle + gapAngle / 2) / 360.0)
    }

    private var endTrim: CGFloat {
        let segmentAngle = 360.0 / Double(totalSegments)
        let visibleAngle = max(segmentAngle - gapAngle, 1)
        return CGFloat((Double(index) * segmentAngle + gapAngle / 2 + visibleAngle) / 360.0)
    }

    var body: some View {
        Circle()
            .trim(from: startTrim, to: endTrim)
            .stroke(
                LinearGradient(
                    colors: [Color.blue, Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
    }
}

// MARK: - ✅ Modern Share Sheet (Overlay Style)
struct ModernShareSheet: View {
    let moment: Moment
    let onBack: () -> Void
    let onDismiss: () -> Void
    
    @State private var searchText = ""
    @State private var selectedUsers: Set<String> = []
    @State private var conversations: [Conversation] = []
    @State private var globalSearchResults: [AppUser] = []
    @State private var isLoading = true
    @State private var isSearchingGlobal = false
    @State private var activeFilter: FilterType = .none
    
    enum FilterType {
        case none, favorites, recents
    }
    
    @StateObject private var chatService = ChatService.shared
    
    var filteredConversations: [Conversation] {
        var base = conversations
        
        switch activeFilter {
        case .favorites:
            base = conversations.filter { $0.isPinned == true }
        case .recents:
            base = conversations // Show all, but the UI might prioritize them
        case .none:
            break
        }
        
        if searchText.isEmpty {
            return base
        }
        return base.filter { 
            $0.otherParticipantUsername?.localizedCaseInsensitiveContains(searchText) ?? false 
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("share.sendTo")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.primary)
                    
                    LiveUsernameContent(userId: moment.authorId, fallbackUsername: moment.username) { username in
                        Text(String(format: NSLocalizedString("share.moment.by", comment: ""), username))
                    }
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField(NSLocalizedString("share.search.placeholder", comment: ""), text: $searchText)
                    .foregroundColor(.primary)
                    .font(.custom("Poppins-Regular", size: 16))
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        performGlobalSearch(query: newValue)
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .liquidGlass(in: Capsule(), interactive: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    FilterChip(
                        icon: "star.fill",
                        title: NSLocalizedString("share.favorites", comment: ""),
                        color: Color(hex: "00A896"),
                        isSelected: activeFilter == .favorites
                    ) {
                        withAnimation(.spring()) {
                            activeFilter = activeFilter == .favorites ? .none : .favorites
                        }
                    }
                    
                    FilterChip(
                        icon: "clock.fill",
                        title: NSLocalizedString("share.recents", comment: ""),
                        color: .blue,
                        isSelected: activeFilter == .recents
                    ) {
                        withAnimation(.spring()) {
                            activeFilter = activeFilter == .recents ? .none : .recents
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        PeopleSkeletonGrid()
                    } else {
                        // Local results
                        if !filteredConversations.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                                ForEach(filteredConversations.indices, id: \.self) { index in
                                    let conversation = filteredConversations[index]
                                    PersonCell(
                                        conversation: conversation,
                                        isSelected: selectedUsers.contains(conversation.otherParticipantId),
                                        animationDelay: Double(index) * 0.05,
                                        onTap: { toggleUserSelection(conversation.otherParticipantId) }
                                    )
                                }
                            }
                        }
                        
                        // Global results
                        if !globalSearchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("share.search.globalResults")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                                    ForEach(globalSearchResults) { user in
                                        GlobalUserCell(
                                            user: user,
                                            isSelected: selectedUsers.contains(user.id),
                                            onTap: { toggleUserSelection(user.id) }
                                        )
                                    }
                                }
                            }
                        }
                        
                        if filteredConversations.isEmpty && globalSearchResults.isEmpty && !searchText.isEmpty {
                            EmptySearchState()
                        }
                        
                        if filteredConversations.isEmpty && searchText.isEmpty && activeFilter == .favorites {
                            VStack(spacing: 12) {
                                Image(systemName: "star.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("share.favorites.empty")
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .frame(maxHeight: 350)
            
            // Bottom Send
            SendActionBottomBar(
                selectedCount: selectedUsers.count,
                onSend: sendToSelectedUsers
            )
        }
        .onAppear(perform: loadConversations)
    }
    
    private func loadConversations() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        chatService.fetchConversations(for: currentUserId) { result in
            DispatchQueue.main.async {
                if case .success(let fetched) = result {
                    withAnimation(.easeInOut) {
                        self.conversations = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func performGlobalSearch(query: String) {
        guard query.count >= 3 else {
            self.globalSearchResults = []
            return
        }
        
        isSearchingGlobal = true
        FirestoreService.shared.searchUsers(query: query) { result in
            DispatchQueue.main.async {
                self.isSearchingGlobal = false
                if case .success(let users) = result {
                    // Filter out already shown in conversations
                    let localIds = Set(conversations.map { $0.otherParticipantId })
                    self.globalSearchResults = users.filter { !localIds.contains($0.id) }
                }
            }
        }
    }
    
    private func toggleUserSelection(_ userId: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedUsers.contains(userId) {
                selectedUsers.remove(userId)
            } else {
                selectedUsers.insert(userId)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func sendToSelectedUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              moment.id != nil else { return }
        
        let freshUsername = UserCacheService.shared.getCachedUser(userId: moment.authorId)?.username ?? moment.username
        let shareText = String(format: NSLocalizedString("share.moment.by", comment: ""), freshUsername)
        let momentUrl = buildMomentShareURLString(moment)
        
        for userId in selectedUsers {
            let existingConv = conversations.first(where: { $0.otherParticipantId == userId })
            
            chatService.sendSharedMomentMessage(
                conversationId: existingConv?.id ?? "", 
                senderId: currentUserId,
                moment: moment,
                shareText: shareText,
                momentUrl: momentUrl
            ) { _ in }
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }
}



// MARK: - ✅ Quick Action Button (Rediseñado)
struct QuickActionButton: View {
    let icon: String
    let title: String
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ?
                                    iconColor.opacity(0.6) :
                                    Color.white.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
            }
            
            Text(title)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(width: 80)
    }
}

// MARK: - ✅ Person Cell (Mejorado)
struct PersonCell: View {
    let conversation: Conversation
    let isSelected: Bool
    let animationDelay: Double
    let onTap: () -> Void
    
    @State private var isVisible = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: onTap) {
                ZStack {
                    // ✅ Profile image mejorada
                    if let profileImagePath = conversation.otherParticipantProfileImagePath,
                       let url = URL(string: profileImagePath) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ?
                                        LinearGradient(
                                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isSelected ? 3 : 1
                                    )
                            )
                            .shadow(
                                color: isSelected ? Color(hex: "00A896").opacity(0.3) : Color.black.opacity(0.2),
                                radius: isSelected ? 8 : 4,
                                x: 0,
                                y: isSelected ? 4 : 2
                            )
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 68, height: 68)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    // ✅ Checkmark animado mejorado
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: Color(hex: "00A896").opacity(0.4), radius: 4, x: 0, y: 2)
                            .offset(x: 24, y: -24)
                            .scaleEffect(isSelected ? 1.0 : 0.1)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSelected)
                    }
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
            
            Text(conversation.otherParticipantUsername ?? "Usuario")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0)
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8)
            .delay(animationDelay),
            value: isVisible
        )
        .onAppear {
            isVisible = true
        }
    }
}

// MARK: - ✅ Person Skeleton Cell (Loading)
struct PersonSkeletonCell: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 68, height: 68)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shimmer(isAnimating: isAnimating)
            
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .frame(width: 60, height: 12)
                .shimmer(isAnimating: isAnimating)
        }
        .onAppear {
            isAnimating = true
        }
    }
}
// MARK: - ✅ Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "00A896").opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color(hex: "00A896"))
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
    }
}


// MARK: - ✅ Supporting Views (Mantener las existentes)

// MARK: - Add to Story View
struct AddToStoryView: View {
    let moment: Moment
    @Environment(\.dismiss) var dismiss
    @State private var showCreatorView = false
    @State private var createdSticker: StickerItem?
    @State private var backgroundMedia: [CreatorMedia]? = nil
    @State private var isPreparing = true
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            let _ = print("🔄 AddToStoryView Body Update - Sticker: \(createdSticker?.id ?? "nil"), Show: \(showCreatorView)")
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let error = errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    
                    Text(error)
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("share.cancel") {
                        dismiss()
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text("share.preparing") // Assume this exists or add to Localizable
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                }
            }
        }
        .fullScreenCover(isPresented: $showCreatorView, onDismiss: { dismiss() }) {
            if let sticker = createdSticker {
                CreatorView(
                    isCreatingStory: .constant(true),
                    showCreatorView: $showCreatorView,
                    initialSticker: sticker,
                    initialMedia: backgroundMedia,
                    openInStoryMode: false
                )
                .id(sticker.id) // ✅ Force recreation when sticker changes
            } else {
                Color.black.ignoresSafeArea()
                    .onAppear {
                        print("❌ CreatorView presented but createdSticker is nil")
                    }
            }
        }
        .onAppear {
            preFetchAndRender()
        }
    }
    
    private func preFetchAndRender() {
        guard let imageUrlString = moment.imagePath ?? moment.videoUrl,
              let contentUrl = URL(string: imageUrlString) else {
            errorMessage = "No se pudo obtener la imagen del momento"
            return
        }
        
        // 1. Obtener la ruta de la foto de perfil desde Firestore
        let db = Firestore.firestore()
        db.collection("users").document(moment.authorId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching profile path: \(error.localizedDescription)")
                // Continuamos aunque falle la de perfil, usará placeholder
                renderSticker(urls: [contentUrl])
                return
            }
            
            var urlsToPrefetch = [contentUrl]
            if let data = snapshot?.data(), let profilePath = data["profileImagePath"] as? String, let profileUrl = URL(string: profilePath) {
                urlsToPrefetch.append(profileUrl)
            }
            
            renderSticker(urls: urlsToPrefetch)
        }
    }
    
    private func retrieveImageAsync(url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value.image)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func renderSticker(urls: [URL]) {
        // 2. Pre-fetch todas las imágenes para tenerlas en caché
        ImagePrefetchManager.shared.prefetch(urls: urls)
        
        // 3. Obtener las imágenes reales de Kingfisher caché
        Task { @MainActor in
            var profileImg: UIImage? = nil
            var contentImg: UIImage? = nil
            
            if urls.count > 1 {
                profileImg = await retrieveImageAsync(url: urls[1])
            }
            contentImg = await retrieveImageAsync(url: urls[0])
            
            self.performFinalRender(profile: profileImg, content: contentImg)
        }
    }
    
    private func performFinalRender(profile: UIImage?, content: UIImage?) {
        let stickerView = ShareMomentSticker(moment: moment, profileImage: profile, contentImage: content, renderClean: true)
            .environment(\.colorScheme, .dark)
            .frame(width: 260)
        
        let renderer = ImageRenderer(content: stickerView)
        renderer.scale = UIScreen.main.scale
        
        if let uiImage = renderer.uiImage {
            let position = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            
            let interactionData = StickerItem.StickerInteractionData(
                username: moment.username,
                userId: moment.authorId,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                caption: moment.content.isEmpty ? nil : moment.content,
                profileImagePath: moment.profileImagePath, // ✅ NUEVO: Pasamos path para reconstrucción
                momentId: moment.id, // ✅ NUEVO: Para navegación al detalle
                mediaCount: moment.mediaItems?.count ?? 1
            )
            
            let sticker = StickerItem(
                image: uiImage,
                position: position,
                type: .shareMoment, // ✅ NUEVO: Tipo específico para renderizado correcto
                interactionData: interactionData,
                videoURL: moment.videoUrl != nil ? URL(string: moment.videoUrl!) : nil
            )
            
            print("🎨 Sticker created: \(sticker.id), Image size: \(sticker.image.size), Video: \(String(describing: sticker.videoURL))")
            self.createdSticker = sticker
            
            // ✅ FIX: No ponemos el media del momento como fondo.
            // Al dejar backgroundMedia = nil, CreatorView generará el degradado elegante
            // que el usuario prefiere, manteniendo el contenido solo dentro del sticker.
            self.backgroundMedia = nil
            print("🎨 Moment background cleared to use default gradient")
            self.isPreparing = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showCreatorView = true
            }
        } else {
            errorMessage = "Error al generar el sticker"
        }
    }
}



// MARK: - Shared DM preview card (historia + momento)

enum SharedDMMediaCardMetrics {
    static let width: CGFloat = 200
    static let height: CGFloat = 280
    static let cornerRadius: CGFloat = 18
}

private struct SharedDMPreviewCardStroke: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: SharedDMMediaCardMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SharedDMMediaCardMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

extension View {
    func sharedDMPreviewCardChrome() -> some View {
        modifier(SharedDMPreviewCardStroke())
    }
}

struct SharedDMPreviewCardSkeleton: View {
  var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SharedDMMediaCardMetrics.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 88, height: 12)
                    Spacer()
                }
                .padding(12)
            }

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.85)))
                .scaleEffect(1.05)
        }
        .frame(width: SharedDMMediaCardMetrics.width, height: SharedDMMediaCardMetrics.height)
        .sharedDMPreviewCardChrome()
    }
}

struct SharedDMPreviewAuthorRow: View {
    let authorId: String?
    let authorName: String?
    var useStoryRing: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if let authorId {
                if useStoryRing {
                    StoryRingAvatarView(
                        userId: authorId,
                        size: 24,
                        lineWidth: 1.8,
                        showBaseStroke: true,
                        baseStrokeColor: .white,
                        baseStrokeWidth: 1.5
                    )
                    .shadow(radius: 2)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                }
            }

            if let authorName, !authorName.isEmpty {
                Text(authorName)
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }

            Spacer(minLength: 0)
        }
    }
}

struct SharedDMPreviewBottomGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.8), .black.opacity(0.4), .clear],
            startPoint: .bottom,
            endPoint: .center
        )
    }
}

struct SharedDMCenteredPlayOverlay: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: 2)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

struct SharedDMUnavailablePreviewCard: View {
    let titleKey: String
    let messageKey: String
    let iconName: String
    let previewImageURL: String?
    let authorId: String?
    let authorName: String?
    var useStoryRing: Bool = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let previewImageURL,
                   !previewImageURL.isEmpty,
                   let url = URL(string: previewImageURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .frame(width: SharedDMMediaCardMetrics.width, height: SharedDMMediaCardMetrics.height)
            .clipped()
            .blur(radius: previewImageURL == nil ? 0 : 22)
            .saturation(previewImageURL == nil ? 1 : 0.35)

            Color.black.opacity(0.58)

            VStack(spacing: 10) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Text(LocalizedStringKey(titleKey))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(LocalizedStringKey(messageKey))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 16)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SharedDMPreviewBottomGradient()

            SharedDMPreviewAuthorRow(
                authorId: authorId,
                authorName: authorName,
                useStoryRing: useStoryRing
            )
            .padding(12)
            .opacity(0.85)
        }
        .frame(width: SharedDMMediaCardMetrics.width, height: SharedDMMediaCardMetrics.height)
        .sharedDMPreviewCardChrome()
    }
}

// MARK: - ✅ Shared Moment Message Bubble (Actualizado)
struct SharedMomentMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onTap: () -> Void
    
    private let privacyService = PrivacyService.shared
    @State private var canViewMoment: Bool? = nil
    @State private var isLoading: Bool = true
    
    var body: some View {
        Group {
            if isLoading {
                SharedDMPreviewCardSkeleton()
                    .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
                    .padding(.vertical, 4)
            } else if canViewMoment == true, let sharedMomentData = message.sharedMomentData {
                // Tarjeta con preview si tiene acceso
                Button(action: onTap) {
                    MomentBubbleContent(
                        content: nil,
                        sharedMomentData: sharedMomentData,
                        isCurrentUser: isCurrentUser
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                BlockedMomentBubble(sharedMomentData: message.sharedMomentData)
                    .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
                    .padding(.vertical, 4)
            }
        }
        .onAppear {
            validateAccess()
        }
    }
    
    private func validateAccess() {
        guard let sharedMomentData = message.sharedMomentData,
              let momentId = sharedMomentData["momentId"],
              let currentUserId = Auth.auth().currentUser?.uid else {
            self.canViewMoment = false
            self.isLoading = false
            return
        }
        
        let authorId = sharedMomentData["momentAuthorId"] ?? message.senderId
        
        if authorId == currentUserId {
            self.canViewMoment = true
            self.isLoading = false
            return
        }
        
        FirestoreService.shared.fetchMoment(momentId: momentId, userId: authorId) { result in
            guard case .success(let moment) = result else {
                DispatchQueue.main.async {
                    self.canViewMoment = false
                    self.isLoading = false
                }
                return
            }

            self.privacyService.canUserViewMomentEnhanced(moment, viewerId: currentUserId) { canView in
                DispatchQueue.main.async {
                    self.canViewMoment = canView
                    self.isLoading = false
                }
            }
        }
    }
}

struct BlockedMomentBubble: View {
    let sharedMomentData: [String: String]?

    var body: some View {
        SharedDMUnavailablePreviewCard(
            titleKey: "share.momentUnavailable",
            messageKey: "share.noPermission",
            iconName: "lock.fill",
            previewImageURL: sharedMomentData?["momentImageUrl"],
            authorId: sharedMomentData?["momentAuthorId"],
            authorName: sharedMomentData?["momentAuthor"],
            useStoryRing: false
        )
    }
}

// MARK: - ✅ Moment Bubble Content (Actualizado)
struct MomentBubbleContent: View {
    let content: String?
    let sharedMomentData: [String: String]
    let isCurrentUser: Bool
    
    var body: some View {
        // Minimalist Design: No background bubble
        VStack(alignment: .leading, spacing: 8) {
            if let content = content, !content.isEmpty {
                Text(content)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.primary) // Adaptive text color
                    .padding(.bottom, 4)
            }
            
            MomentPreviewCard(sharedMomentData: sharedMomentData)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
    }
}

// MARK: - ✅ Moment Preview Card (Actualizado)
// MARK: - ✅ Moment Preview Card (Actualizado Premium)
struct MomentPreviewCard: View {
    let sharedMomentData: [String: String]

    private var isVideo: Bool {
        if let videoUrl = sharedMomentData["momentVideoUrl"], !videoUrl.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            MomentVisualContent(sharedMomentData: sharedMomentData)

            if isVideo {
                SharedDMCenteredPlayOverlay()
            }

            SharedDMPreviewBottomGradient()

            VStack(alignment: .leading, spacing: 6) {
                SharedDMPreviewAuthorRow(
                    authorId: sharedMomentData["momentAuthorId"],
                    authorName: sharedMomentData["momentAuthor"],
                    useStoryRing: false
                )

                if let content = sharedMomentData["momentContent"], !content.isEmpty {
                    Text(content)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12)
        }
        .frame(width: SharedDMMediaCardMetrics.width, height: SharedDMMediaCardMetrics.height)
        .background(Color.black.opacity(0.2))
        .sharedDMPreviewCardChrome()
    }
}

// MARK: - ✅ Moment Visual Content
struct MomentVisualContent: View {
    let sharedMomentData: [String: String]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black // Base background
            // ✅ NUEVO: Priorizar la imagen de miniatura (si existe) sobre la generación al vuelo
            if let imageUrl = sharedMomentData["momentImageUrl"],
                      !imageUrl.isEmpty,
                      let url = URL(string: imageUrl) {
                KFImage(url)
                    .resizable()
                    .placeholder {
                        ZStack {
                            Color.gray.opacity(0.2)
                            ProgressView().tint(.white)
                        }
                    }
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else if let videoUrl = sharedMomentData["momentVideoUrl"], !videoUrl.isEmpty {
                // Si no hay imagen pero hay video (legacy), generar al vuelo
                VideoThumbnailView(videoUrl: videoUrl)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                     // Beautiful Gradient Placeholder
                     LinearGradient(
                        colors: [Color(hex: "00A896"), Color(hex: "02C39A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                     )
                     .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.5))
                     )
                }
                
            }
        }
    }
}

// MARK: - ✅ Video Thumbnail View (Flexible)
struct VideoThumbnailView: View {
    let videoUrl: String
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard let url = URL(string: videoUrl) else {
            isLoading = false
            return
        }
        
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 710) // High res vertical
        
        // Generate near start
        let time = CMTime(seconds: 0.5, preferredTimescale: 60)
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let cgImage = cgImage {
                    self.thumbnailImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
// MARK: - Filter Chip
struct FilterChip: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.custom("Poppins-Medium", size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.3) : Color.white.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? color : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(isSelected ? color : .primary)
        }
    }
}

// MARK: - Send Action Bottom Bar
struct SendActionBottomBar: View {
    let selectedCount: Int
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSend) {
                HStack(spacing: 12) {
                    Image(systemName: selectedCount > 0 ? "paperplane.fill" : "paperplane")
                    Text(selectedCount > 0 ? 
                         String(format: NSLocalizedString("share.sendToCount", comment: ""), selectedCount) : 
                         NSLocalizedString("share.selectContacts", comment: ""))
                }
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(selectedCount > 0 ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 27)
                        .fill(selectedCount > 0 ? 
                              LinearGradient(colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                              LinearGradient(colors: [Color.primary.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .disabled(selectedCount == 0)
        }
    }
}

// MARK: - Global User Cell
struct GlobalUserCell: View {
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) {
                ZStack {
                    if let profileUrl = user.profileImagePath, let url = URL(string: profileUrl) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.6)))
                    }
                    
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "00A896"))
                            .frame(width: 20, height: 20)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                            .offset(x: 20, y: -20)
                    }
                }
                .overlay(Circle().stroke(isSelected ? Color(hex: "00A896") : Color.white.opacity(0.1), lineWidth: 2))
            }
            
            Text(user.username)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - People Skeleton Grid
struct PeopleSkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 10)
                }
            }
        }
    }
}

// MARK: - Empty Search State
struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("share.search.noResults", comment: ""))
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - ✅ Preparing Story Overlay (Shared)
struct PreparingStoryOverlay: View {
    let errorMessage: String?
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 20) {
                if let error = errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                    
                    Text(error)
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(NSLocalizedString("common.cancel", comment: "Cancel"), action: {
                        onCancel()
                    })
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text(NSLocalizedString("share.preparing", comment: "Preparing story..."))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32)) // ✅ Fix: Liquid Glass corners
    }
}
