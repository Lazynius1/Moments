import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Photos
import PhotosUI
import UIKit
import Foundation
import AVKit

// MARK: - ✅ Modern Share Bottom Sheet (Rediseñado)
struct ModernShareBottomSheet: View {
    let moment: Moment
    @Binding var isPresented: Bool
    @State private var showMainShare = false
    @State private var showStoryCreator = false
    @State private var showCollectionPicker = false
    
    var body: some View {
        ZStack {
            // ✅ FIX: El fondo de la vista principal ahora es transparente para no interferir
            // con el fondo de la vista que la presenta (ContextMenuOverlay).
            Color.clear
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isPresented = false
                    }
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // ✅ Handle mejorado
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    
                    // ✅ Header con info del momento
                    HStack(spacing: 12) {
                        AsyncProfileImageView(userId: moment.authorId)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("share.moment.title")
                                .font(.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(.white)
                            
                            Text(String(format: NSLocalizedString("share.moment.from", comment: "From user"), moment.username))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    
                    // ✅ Acciones principales con estilo del context menu
                    VStack(spacing: 8) {
                        // Acción principal - Enviar mensaje
                        ShareActionButton(
                            icon: "paperplane.fill",
                            title: "Enviar mensaje",
                            subtitle: "Comparte con tus contactos",
                            iconColor: Color(hex: "00A896"),
                            isPrimary: true
                        ) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showMainShare = true
                            }
                        }
                        
                        // Acciones secundarias
                        ShareActionButton(
                            icon: "plus.circle.fill",
                            title: "Agregar a historia",
                            subtitle: "Compartir en tu historia",
                            iconColor: .blue,
                            isPrimary: false
                        ) {
                            showStoryCreator = true
                        }
                        
                        ShareActionButton(
                            icon: "bookmark.fill",
                            title: "Guardar en colección",
                            subtitle: "Guardar para más tarde",
                            iconColor: .orange,
                            isPrimary: false
                        ) {
                            showCollectionPicker = true
                        }
                        
                        ShareActionButton(
                            icon: "square.and.arrow.up",
                            title: "Compartir fuera de la app",
                            subtitle: "Enviar enlace externo",
                            iconColor: .purple,
                            isPrimary: false
                        ) {
                            shareExternally()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    
                    // ✅ Botón cancelar consistente
                    Button(NSLocalizedString("share.cancel", comment: "Cancel")) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                // ✅ FIX: El panel de contenido SÍ lleva el fondo de material para darle el efecto de cristal.
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial) // Correcto
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color(hex: "00A896").opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
            
            // ✅ Share sheet como overlay directo (dentro del mismo ZStack)
            if showMainShare {
                ModernShareSheet(moment: moment, isPresented: $showMainShare)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(9999) // ✅ Z-index muy alto para estar encima de todo
            }
        }
        .sheet(isPresented: $showStoryCreator) {
            AddToStoryView(moment: moment)
        }
        .sheet(isPresented: $showCollectionPicker) {
            CollectionPickerView(moment: moment)
        }
    }
    
    private func shareExternally() {
        guard let momentId = moment.id else { return }
        
        let shareText = "Mira este momento de \(moment.username) en Moments"
        let shareUrl = URL(string: "https://moments.app/moment/\(momentId)")!
        
        let activityController = UIActivityViewController(
            activityItems: [shareText, shareUrl],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            window.rootViewController?.present(activityController, animated: true)
        }
        
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
    }
}

// MARK: - ✅ Share Action Button (Rediseñado como Context Menu)
struct ShareActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let isPrimary: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isPrimary ? 0.2 : 0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(
                                    isPrimary ? iconColor.opacity(0.4) : Color.clear,
                                    lineWidth: isPrimary ? 1 : 0
                                )
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isPrimary ?
                        iconColor.opacity(isPressed ? 0.1 : 0.05) :
                        Color.white.opacity(isPressed ? 0.1 : 0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isPrimary ?
                                iconColor.opacity(0.2) :
                                Color.white.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - ✅ Modern Share Sheet (Overlay Style)
struct ModernShareSheet: View {
    let moment: Moment
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedUsers: Set<String> = []
    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @StateObject private var chatService = ChatService()
    
    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.otherParticipantUsername?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
    
    var body: some View {
        ZStack {
            // ✅ Fondo completamente transparente como el context menu
            Color.clear
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isPresented = false
                    }
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // ✅ Handle superior
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    
                    // ✅ Header con info del momento
                    HStack(spacing: 12) {
                        AsyncProfileImageView(userId: moment.authorId)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("share.sendTo")
                                .font(.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(.white)
                            
                            Text(String(format: NSLocalizedString("share.moment.by", comment: "Moment by user"), moment.username))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        // ✅ Botón cancelar en header
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    // ✅ Search bar con glassmorphism
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 16))
                        
                        TextField("Buscar contactos...", text: $searchText)
                            .foregroundColor(.white)
                            .font(.custom("Poppins-Regular", size: 16))
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // ✅ Quick actions si hay conversaciones
                    if !conversations.isEmpty && !isLoading {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                QuickActionButton(
                                    icon: "star.circle.fill",
                                    title: "Favoritos",
                                    iconColor: Color(hex: "00A896"),
                                    isSelected: false
                                ) {
                                    // Handle favorites
                                }
                                
                                QuickActionButton(
                                    icon: "clock.circle.fill",
                                    title: "Recientes",
                                    iconColor: .blue,
                                    isSelected: false
                                ) {
                                    // Handle recents
                                }
                                
                                QuickActionButton(
                                    icon: "person.2.circle.fill",
                                    title: "Grupos",
                                    iconColor: .purple,
                                    isSelected: false
                                ) {
                                    // Handle groups
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 16)
                    }
                    
                    // ✅ People grid con altura limitada
                    ScrollView {
                        if isLoading {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 20) {
                                ForEach(0..<8, id: \.self) { _ in
                                    PersonSkeletonCell()
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        } else if filteredConversations.isEmpty {
                            EmptyStateView(
                                icon: "person.3",
                                title: searchText.isEmpty ? "No tienes conversaciones" : "No se encontraron contactos",
                                subtitle: searchText.isEmpty ? "Conecta con personas para compartir momentos" : "Intenta con otro nombre"
                            )
                            .padding(.top, 20)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 20) {
                                ForEach(filteredConversations.indices, id: \.self) { index in
                                    let conversation = filteredConversations[index]
                                    
                                    PersonCell(
                                        conversation: conversation,
                                        isSelected: selectedUsers.contains(conversation.otherParticipantId ?? ""),
                                        animationDelay: Double(index) * 0.05
                                    ) {
                                        toggleUserSelection(conversation.otherParticipantId ?? "")
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                    }
                    .frame(maxHeight: 320) // ✅ Altura máxima para el scroll
                    
                    // ✅ Bottom send button
                    VStack(spacing: 0) {
                        // ✅ Gradient divider
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.1), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1)
                        
                        Button(action: sendToSelectedUsers) {
                            HStack(spacing: 12) {
                                if selectedUsers.isEmpty {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    Text("share.selectContacts")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    Text(String(format: NSLocalizedString("share.sendToCount", comment: "Send to count"), selectedUsers.count))
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 27)
                                    .fill(
                                        selectedUsers.isEmpty ?
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.1)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ) :
                                        LinearGradient(
                                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 27)
                                            .stroke(
                                                selectedUsers.isEmpty ?
                                                Color.white.opacity(0.2) :
                                                Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(
                                color: selectedUsers.isEmpty ? Color.clear : Color(hex: "00A896").opacity(0.3),
                                radius: selectedUsers.isEmpty ? 0 : 8,
                                x: 0,
                                y: selectedUsers.isEmpty ? 0 : 4
                            )
                            .disabled(selectedUsers.isEmpty)
                        }
                        .animation(.easeInOut(duration: 0.2), value: selectedUsers.isEmpty)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(.ultraThinMaterial)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color(hex: "00A896").opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.bottom, 50) // ✅ Safe area bottom
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadData()
        }
    }
    
    // MARK: - Actions
    private func loadData() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        chatService.fetchConversations(for: currentUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedConversations):
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.conversations = fetchedConversations
                        self.isLoading = false
                    }
                case .failure(let error):
                    print("Error loading conversations: \(error)")
                    self.isLoading = false
                }
            }
        }
    }
    
    private func toggleUserSelection(_ userId: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if selectedUsers.contains(userId) {
                selectedUsers.remove(userId)
            } else {
                selectedUsers.insert(userId)
            }
        }
        
        // ✅ Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func sendToSelectedUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        let shareText = "🔗 \(moment.username) compartió un momento"
        let momentUrl = "https://moments.app/moment/\(momentId)"
        
        for userId in selectedUsers {
            if let conversation = conversations.first(where: { $0.otherParticipantId == userId }),
               let conversationId = conversation.id {
                
                chatService.sendSharedMomentMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    moment: moment,
                    shareText: shareText,
                    momentUrl: momentUrl
                ) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            print("Moment shared successfully to \(userId)")
                        case .failure(let error):
                            print("Error sharing moment: \(error)")
                        }
                    }
                }
            }
        }
        
        // ✅ Success haptic feedback
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
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
                .foregroundColor(.white.opacity(0.9))
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
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "0A0A0F"),
                        Color(hex: "1A1A2E")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(hex: "00A896"))
                    
                    VStack(spacing: 12) {
                        Text("share.comingSoon")
                            .font(.custom("Poppins-SemiBold", size: 24))
                            .foregroundColor(.white)
                        
                        Text("share.comingSoon.description")
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("share.addToStory")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("share.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.custom("Poppins-Medium", size: 16))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Collection Picker View
struct CollectionPickerView: View {
    let moment: Moment
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "0A0A0F"),
                        Color(hex: "1A1A2E")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "bookmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 12) {
                        Text("share.comingSoon")
                            .font(.custom("Poppins-SemiBold", size: 24))
                            .foregroundColor(.white)
                        
                        Text("share.comingSoon.description")
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("share.saveToCollection")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("share.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.custom("Poppins-Medium", size: 16))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - ✅ Shared Moment Message Bubble (Actualizado)
struct SharedMomentMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onTap: () -> Void
    
    @State private var canViewMoment: Bool? = nil
    @State private var isLoading: Bool = true
    
    var body: some View {
        Group {
            if isLoading {
                // Loader mientras se valida
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    Text("share.loading")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
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
                // Tarjeta bloqueada si no tiene acceso
                BlockedMomentBubble()
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
        
        // Obtener el authorId del momento compartido o usar el senderId como fallback
        let authorId = sharedMomentData["momentAuthorId"] ?? message.senderId
        
        // Si es el mismo usuario, siempre puede verlo
        if authorId == currentUserId {
            self.canViewMoment = true
            self.isLoading = false
            return
        }
        
        // Buscar el momento en Firestore y validar acceso
        let db = Firestore.firestore()
        db.collection("users").document(authorId).collection("moments").document(momentId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let data = snapshot?.data() {
                    let audience = data["audience"] as? String ?? "everyone"
                    
                    // Validación simplificada basada en audiencia
                    switch audience {
                    case "everyone":
                        // Para audiencia everyone, verificar si el perfil es público
                        self.checkPublicProfileAccess(authorId: authorId, viewerId: currentUserId) { canView in
                            self.canViewMoment = canView
                            self.isLoading = false
                        }
                        
                    case "connections":
                        // Para conexiones, verificar seguimiento mutuo
                        self.checkMutualConnection(authorId: authorId, viewerId: currentUserId) { canView in
                            self.canViewMoment = canView
                            self.isLoading = false
                        }
                        
                    case "bestFriends":
                        // Para mejores amigos, verificar si está en la lista
                        self.checkBestFriendAccess(authorId: authorId, viewerId: currentUserId) { canView in
                            self.canViewMoment = canView
                            self.isLoading = false
                        }
                        
                    case "custom", "customList":
                        // Para audiencias personalizadas, denegar por defecto
                        self.canViewMoment = false
                        self.isLoading = false
                        
                    case "onlyMe":
                        // Solo el autor puede verlo
                        self.canViewMoment = false
                        self.isLoading = false
                        
                    default:
                        self.canViewMoment = false
                        self.isLoading = false
                    }
                } else {
                    self.canViewMoment = false
                    self.isLoading = false
                }
            }
        }
    }
    
    // Función auxiliar para verificar acceso a perfil público
    private func checkPublicProfileAccess(authorId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("users").document(authorId).getDocument { snapshot, error in
            if let data = snapshot?.data() {
                let isPrivate = data["isPrivate"] as? Bool ?? false
                completion(!isPrivate) // Si no es privado, puede ver
            } else {
                completion(false)
            }
        }
    }
    
    // Función auxiliar para verificar conexión mutua
    private func checkMutualConnection(authorId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var authorFollowsViewer = false
        var viewerFollowsAuthor = false
        
        group.enter()
        db.collection("users").document(authorId).collection("following").document(viewerId).getDocument { snapshot, _ in
            authorFollowsViewer = snapshot?.exists ?? false
            group.leave()
        }
        
        group.enter()
        db.collection("users").document(viewerId).collection("following").document(authorId).getDocument { snapshot, _ in
            viewerFollowsAuthor = snapshot?.exists ?? false
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(authorFollowsViewer && viewerFollowsAuthor)
        }
    }
    
    // Función auxiliar para verificar acceso de mejor amigo
    private func checkBestFriendAccess(authorId: String, viewerId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("users").document(authorId).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let bestFriends = data["bestFriends"] as? [String] {
                completion(bestFriends.contains(viewerId))
            } else {
                completion(false)
            }
        }
    }
}

// Tarjeta bloqueada 
struct BlockedMomentBubble: View {
    var body: some View {
        HStack(spacing: 12) {
            // Icono de candado
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Texto de restricción
            VStack(alignment: .leading, spacing: 2) {
                Text("share.momentUnavailable")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.white)
                
                Text("share.noPermission")
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ✅ Moment Bubble Content (Actualizado)
struct MomentBubbleContent: View {
    let content: String?
    let sharedMomentData: [String: String]
    let isCurrentUser: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let content = content, !content.isEmpty {
                Text(content)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 4)
            }
            
            MomentPreviewCard(sharedMomentData: sharedMomentData)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    isCurrentUser ?
                    LinearGradient(
                        colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - ✅ Moment Preview Card (Actualizado)
struct MomentPreviewCard: View {
    let sharedMomentData: [String: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ✅ NUEVO: Header con perfil y username (como Instagram)
            if let author = sharedMomentData["momentAuthor"] {
                HStack(spacing: 8) {
                    // ✅ NUEVO: Perfil real del usuario
                    if let authorId = sharedMomentData["momentAuthorId"] {
                        AsyncProfileImageView(userId: authorId)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    } else {
                        // ✅ Fallback si no hay authorId
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            )
                    }
                    
                    // ✅ Username con verificado
                    HStack(spacing: 4) {
                        Text(author)
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // ✅ Ícono de verificado
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            // ✅ Video o imagen embebido directamente
            MomentThumbnailAndInfo(sharedMomentData: sharedMomentData)
            
            // ✅ Botón de acción
            MomentActionButton()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ✅ Moment Thumbnail and Info (Actualizado)
struct MomentThumbnailAndInfo: View {
    let sharedMomentData: [String: String]
    
    var body: some View {
        HStack(spacing: 10) {
            // ✅ MEJORADO: Manejo de imagen o video
            if let videoUrl = sharedMomentData["momentVideoUrl"], !videoUrl.isEmpty {
                // ✅ NUEVO: Thumbnail de video con indicador de play (formato reels) - EMBEBIDO
                VideoThumbnailView(videoUrl: videoUrl, sharedMomentData: sharedMomentData)
            } else if let imageUrl = sharedMomentData["momentImageUrl"],
                      !imageUrl.isEmpty,
                      let url = URL(string: imageUrl) {
                // ✅ EXISTENTE: Imagen normal (puede ser thumbnail de video o imagen)
                ZStack {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                    
                    // ✅ NUEVO: Indicador de video si hay momentVideoUrl
                    if let videoUrl = sharedMomentData["momentVideoUrl"], !videoUrl.isEmpty {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: 1, y: 0)
                            )
                    }
                }
            } else {
                // ✅ FALLBACK: Placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 20))
                    )
            }
            
            // ✅ SOLO contenido (username ya está en el header)
            VStack(alignment: .leading, spacing: 4) {
                if let content = sharedMomentData["momentContent"], !content.isEmpty {
                    Text(content)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else if let videoUrl = sharedMomentData["momentVideoUrl"], !videoUrl.isEmpty {
                    // ✅ Si es video sin contenido, mostrar "Video"
                    Text("share.video")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("share.moment")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ Moment Action Button (Actualizado)
struct MomentActionButton: View {
    var body: some View {
        HStack {
            Image(systemName: "eye.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "00A896"))
            
                            Text("share.viewMoment")
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(Color(hex: "00A896"))
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 4)
    }
}

// ✅ NUEVO: Componente para mostrar thumbnail de video con indicador de play
struct VideoThumbnailView: View {
    let videoUrl: String
    let sharedMomentData: [String: String] // ✅ NUEVO: Para obtener el username
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            // ✅ Fondo del thumbnail (formato reels 9:16)
            if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 106) // ✅ Formato reels 9:16 (60 * 16/9 ≈ 106)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                // ✅ Placeholder con formato reels
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 106) // ✅ Formato reels 9:16
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "video")
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.system(size: 20))
                            }
                        }
                    )
            }
            
            // ✅ Overlay con elementos de Instagram
            VStack {
                Spacer()
                
                // ✅ Botón de play en el centro
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 1, y: 0)
                    )
                
                Spacer()
                
                // ✅ Ícono de video abajo a la izquierda
                HStack {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                    
                    Spacer()
                }
                .padding(.bottom, 4)
                .padding(.leading, 4)
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
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 213) // ✅ 2x para retina, formato reels
        
        // Generar thumbnail en el primer segundo
        let time = CMTime(seconds: 0.5, preferredTimescale: 1)
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let cgImage = cgImage {
                    self.thumbnailImage = UIImage(cgImage: cgImage)
                } else {
                    print("❌ Error generando thumbnail: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
}
