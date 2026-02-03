import SwiftUI

// 🔗 ENUM: Configuración específica para continuación de cadenas
enum ChainContinuationSetting: String, CaseIterable {
    case everyone = "everyone"
    case connections = "connections"
    case bestFriends = "bestFriends"
    case custom = "custom"
    case customList = "customList"
    
    var title: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone")
        case .connections: return NSLocalizedString("audience.type.connections", comment: "Connections")
        case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best Friends")
        case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom")
        case .customList: return NSLocalizedString("audience.type.customList", comment: "Custom List")
        }
    }
    
    var icon: String {
        switch self {
        case .everyone: return "globe"
        case .connections: return "person.2.fill"
        case .bestFriends: return "heart.circle.fill"
        case .custom: return "person.crop.circle.badge.plus"
        case .customList: return "list.bullet.rectangle"
        }
    }
    
    var description: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.description.everyone", comment: "Everyone description")
        case .connections: return NSLocalizedString("audience.description.connections", comment: "Connections description")
        case .bestFriends: return NSLocalizedString("audience.description.bestFriends", comment: "Best Friends description")
        case .custom: return NSLocalizedString("audience.description.custom", comment: "Custom description")
        case .customList: return NSLocalizedString("audience.description.customList", comment: "Custom List description")
        }
    }
}

struct ChainConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var allowOthersToContinue: Bool
    @Binding var continuationAudience: ChainContinuationSetting
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    let isContinuing: Bool // 🔗 NUEVO: Indica si estamos continuando una cadena existente
    var onConfirm: (() -> Void)? // 🔗 NUEVO: Callback para cuando el usuario confirma la publicación
    
    @State private var showingContinuationSelector = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header con información
                VStack(spacing: 16) {
                    Image(systemName: "link")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text(NSLocalizedString("storyChains.configurationTitle", comment: "Chain Configuration"))
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(.primary)
                    
                    // Texto informativo aclarando el origen de la configuración
                    Text(isContinuing ? 
                         NSLocalizedString("storyChains.inheritedSettingsInfo", comment: "The settings for this chain were defined by the original author and cannot be changed.") :
                         NSLocalizedString("storyChains.visibilityInfo", comment: "Visibility info"))
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                
                // Configuración principal
                VStack(spacing: 20) {
                    // Toggle para permitir continuación (Oculto si es continuación)
                    if !isContinuing {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(NSLocalizedString("storyChains.allowOthersToggle", comment: "Allow others toggle"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Toggle("", isOn: $allowOthersToContinue)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            
                            Text(NSLocalizedString("storyChains.allowOthersDescription", comment: "Allow others description"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Selector de audiencia (Solo lectura si es continuación)
                    if allowOthersToContinue {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("storyChains.continuationAudience", comment: "Continuation audience"))
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(.primary)
                            
                            Button(action: {
                                if !isContinuing {
                                    showingContinuationSelector = true
                                }
                            }) {
                                HStack {
                                    Image(systemName: getAudienceIcon())
                                        .foregroundColor(isContinuing ? .secondary : .blue)
                                    
                                    Text(getAudienceText())
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(isContinuing ? .secondary : .primary)
                                    
                                    Spacer()
                                    
                                    if !isContinuing {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isContinuing)
                        }
                    }
                    
                    if isContinuing {
                        // Mensaje de pie para colaboradores
                        Text(NSLocalizedString("storyChains.collaboratorNotice", comment: "Note: Since you are a collaborator, the chain rules established by the author apply."))
                            .font(.custom("Poppins-Italic", size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Botón de compartir
                Button(action: {
                    dismiss()
                    // 🔗 NOTIFICAR CONFIRMACIÓN
                    onConfirm?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        
                        Text(NSLocalizedString("storyChains.shareChain", comment: "Share Chain"))
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            // Fondo glassmorphism con gradiente azul, púrpura y rosa
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            
                            // Efecto glassmorphism
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .opacity(0.3)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("storyChains.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingContinuationSelector) {
            ChainContinuationSelectorView(
                selectedAudience: $continuationAudience,
                selectedListId: $selectedListId,
                selectedListName: $selectedListName,
                customSelectedUsers: $customSelectedUsers
            )
        }
    }
    
    // MARK: - Helper Functions
    private func getAudienceIcon() -> String {
        if continuationAudience == .custom && selectedListId != nil {
            return "list.bullet.rectangle"
        }
        return continuationAudience.icon
    }
    
    private func getAudienceText() -> String {
        if continuationAudience == .custom {
            if let listName = selectedListName {
                return listName
            } else {
                let count = customSelectedUsers.count
                if count == 1 {
                    return String(format: NSLocalizedString("storyEditor.customAudience.single", comment: "1 person"), count)
                } else {
                    return String(format: NSLocalizedString("storyEditor.customAudience.multiple", comment: "%d people"), count)
                }
            }
        }
        return continuationAudience.title
    }
    
    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch continuationAudience {
                case .everyone: return .everyone
                case .connections: return .connections
                case .bestFriends: return .bestFriends
                case .custom: return .custom
                case .customList: return .customList
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: continuationAudience = .everyone
                case .connections: continuationAudience = .connections
                case .bestFriends: continuationAudience = .bestFriends
                case .custom: continuationAudience = .custom
                case .customList: continuationAudience = .custom
                case .onlyMe: continuationAudience = .everyone
                }
            }
        )
    }
}

#Preview {
    ChainConfigurationView(
        allowOthersToContinue: .constant(true),
        continuationAudience: .constant(.everyone),
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        customSelectedUsers: .constant([]),
        isContinuing: false
    )
}

