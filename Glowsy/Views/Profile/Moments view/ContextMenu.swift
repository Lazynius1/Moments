import SwiftUI
import FirebaseAuth

// MARK: - ✅ Menú Contextual Moderno (Botón de entrada)
struct ModernMomentContextMenu: View {
    let moment: Moment
    @State private var showActionSheet = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    var body: some View {
        ZStack {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showActionSheet = true
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.gray.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .sheet(isPresented: $showEditSheet) {
                EditMomentView(
                    moment: moment,
                    editedContent: $editedContent,
                    onSave: { newContent in
                        updateMoment(newContent: newContent)
                    }
                )
            }
            .alert(NSLocalizedString("contextMenu.delete.title", comment: "Delete moment alert title"), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("contextMenu.delete.cancel", comment: "Cancel button"), role: .cancel) { }
                Button(NSLocalizedString("contextMenu.delete.confirm", comment: "Delete button"), role: .destructive) {
                    deleteMoment()
                }
            } message: {
                Text(NSLocalizedString("contextMenu.delete.message", comment: "Delete moment confirmation message"))
            }
            .sheet(isPresented: $showReportSheet) {
                ReportBottomSheet(moment: moment)
            }
            
            // ✅ Overlay del menú contextual con animación
            if showActionSheet {
                ModernContextMenuOverlay(
                    moment: moment,
                    isPresented: $showActionSheet,
                    showShareSheet: $showShareSheet,
                    onEdit: {
                        editedContent = moment.content
                        showEditSheet = true
                    },
                    onDelete: {
                        showDeleteAlert = true
                    },
                    onShare: {
                        if privacyService.canShareMoment(moment) {
                            showShareSheet = true
                        }
                    },
                    onReport: {
                        showReportSheet = true
                    },
                    onCopyLink: {
                        if let momentId = moment.id {
                            UIPasteboard.general.string = "https://moments.app/moment/\(momentId)"
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1000) // ✅ Asegurar que aparezca encima de todo
            }
            
            // ✅ NUEVO: Share sheet como overlay directo
            if showShareSheet {
                ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1001)
            }
        }
    }
    
    private func updateMoment(newContent: String) {
        guard let momentId = moment.id else { return }
        
        firestoreService.updateMoment(
            userId: moment.authorId,
            momentId: momentId,
            content: newContent
        ) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    private func deleteMoment() {
        guard let momentId = moment.id else { return }
        
        isDeleting = true
        
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { [self] error in
            DispatchQueue.main.async {
                self.isDeleting = false
                
                if let error = error {
                } else {
                }
            }
        }
    }
}

// MARK: - ✅ Overlay del Menú Contextual Moderno
struct ModernContextMenuOverlay: View {
    let moment: Moment
    @Binding var isPresented: Bool
    @Binding var showShareSheet: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void
    let onCopyLink: () -> Void
    
    private let privacyService = PrivacyService()
    
    private var isMyMoment: Bool {
        moment.authorId == Auth.auth().currentUser?.uid
    }
    
    private var canShare: Bool {
        privacyService.canShareMoment(moment)
    }
    
    var body: some View {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                
                VStack {
                    Spacer()
                    ModernContextMenuContent(
                        moment: moment,
                        isMyMoment: isMyMoment,
                        canShare: canShare,
                        onEdit: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onEdit()
                        },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onDelete()
                        },
                        onShare: {
                            if privacyService.canShareMoment(moment) {
                                showShareSheet = true
                            }
                        },
                        onReport: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onReport()
                        },
                        onCopyLink: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                            onCopyLink()
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        },
                        onCancel: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isPresented = false
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
        }
    }

// MARK: - ✅ Contenido del Menú Contextual
struct ModernContextMenuContent: View {
    let moment: Moment
    let isMyMoment: Bool
    let canShare: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void
    let onCopyLink: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Handle superior
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            // ✅ Título con info del usuario
            HStack(spacing: 12) {
                AsyncProfileImageView(userId: moment.authorId)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.username)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                    
                    Text("Momento • \(formatRelativeTime(moment.timestamp))")
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // ✅ Indicador de privacidad
                PrivacyIndicator(audience: moment.audience ?? "everyone")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            
            // ✅ Acciones principales
            VStack(spacing: 8) {
                // ✅ Acciones del propietario
                if isMyMoment {
                    ContextMenuButton(
                        icon: "pencil",
                        title: NSLocalizedString("contextMenu.editMoment", comment: "Edit moment button"),
                        subtitle: NSLocalizedString("contextMenu.editMoment.subtitle", comment: "Edit moment subtitle"),
                        iconColor: .blue,
                        action: onEdit
                    )
                    
                    ContextMenuButton(
                        icon: "trash",
                        title: NSLocalizedString("contextMenu.deleteMoment", comment: "Delete moment button"),
                        subtitle: NSLocalizedString("contextMenu.deleteMoment.subtitle", comment: "Delete moment subtitle"),
                        iconColor: .red,
                        action: onDelete
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 8)
                }
                
                // ✅ Compartir (solo si audiencia es "everyone")
                if canShare {
                    ContextMenuButton(
                        icon: "paperplane.fill",
                        title: NSLocalizedString("contextMenu.shareMoment", comment: "Share moment button"),
                        subtitle: NSLocalizedString("contextMenu.shareMoment.subtitle", comment: "Share moment subtitle"),
                        iconColor: .green,
                        action: onShare
                    )
                } else {
                    ContextMenuButtonDisabled(
                        icon: "paperplane.fill",
                        title: NSLocalizedString("contextMenu.shareMoment", comment: "Share moment button"),
                        subtitle: NSLocalizedString("contextMenu.shareMoment.disabled", comment: "Share moment disabled subtitle"),
                        iconColor: .gray
                    )
                }
                
                ContextMenuButton(
                    icon: "link",
                    title: NSLocalizedString("contextMenu.copyLink", comment: "Copy link button"),
                    subtitle: NSLocalizedString("contextMenu.copyLink.subtitle", comment: "Copy link subtitle"),
                    iconColor: .orange,
                    action: onCopyLink
                )
                
                // ✅ Reportar (solo si no es mi momento)
                if !isMyMoment {
                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 8)
                    
                    ContextMenuButton(
                        icon: "flag",
                        title: NSLocalizedString("contextMenu.reportMoment", comment: "Report moment button"),
                        subtitle: NSLocalizedString("contextMenu.reportMoment.subtitle", comment: "Report moment subtitle"),
                        iconColor: .red,
                        action: onReport
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40) // ✅ Más padding para que no esté pegado al borde
            
            // ✅ Botón cancelar
            Button(NSLocalizedString("contextMenu.cancel", comment: "Cancel button")) {
                onCancel()
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
            .padding(.bottom, 30) // ✅ Safe area bottom + padding extra
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
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ Botón de acción del menú contextual
struct ContextMenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
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
                    .fill(isPressed ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
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

// MARK: - ✅ Botón deshabilitado con explicación
struct ContextMenuButtonDisabled: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(0.6))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white.opacity(0.5))
                
                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ✅ Indicador de privacidad
struct PrivacyIndicator: View {
    let audience: String
    
    private var audienceInfo: (icon: String, color: Color, text: String) {
        switch audience {
        case "everyone":
            return ("globe", .green, NSLocalizedString("privacyIndicator.public", comment: "Public privacy level"))
        case "connections":
            return ("person.2", .blue, NSLocalizedString("privacyIndicator.connections", comment: "Connections privacy level"))
        case "bestFriends":
            return ("star.fill", .yellow, NSLocalizedString("privacyIndicator.bestFriends", comment: "Best friends privacy level"))
        case "custom":
            return ("person.3", .purple, NSLocalizedString("privacyIndicator.custom", comment: "Custom privacy level"))
        case "customList":
            return ("list.bullet", .orange, NSLocalizedString("privacyIndicator.customList", comment: "Custom list privacy level"))
        default:
            return ("globe", .green, NSLocalizedString("privacyIndicator.public", comment: "Public privacy level"))
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: audienceInfo.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(audienceInfo.color)
            
            Text(audienceInfo.text)
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(audienceInfo.color.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(audienceInfo.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
