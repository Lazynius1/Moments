import SwiftUI

// 🔗 ENUM: Configuración específica para continuación de cadenas
enum ChainContinuationSetting: String, CaseIterable {
    case everyone = "everyone"
    case mutuals = "mutuals"
    case bestFriends = "bestFriends"
    case custom = "custom"
    case customList = "customList"
    
    var title: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone")
        case .mutuals: return NSLocalizedString("audience.type.mutuals", comment: "Mutuals")
        case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best Friends")
        case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom")
        case .customList: return NSLocalizedString("audience.type.customList", comment: "Custom List")
        }
    }
    
    var icon: String {
        contentAudience.assetName
    }

    var contentAudience: ContentAudience {
        switch self {
        case .everyone: return .everyone
        case .mutuals: return .mutuals
        case .bestFriends: return .bestFriends
        case .custom: return .custom
        case .customList: return .customList
        }
    }
    
    var description: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.description.everyone", comment: "Everyone description")
        case .mutuals: return NSLocalizedString("audience.description.mutuals", comment: "Mutuals description")
        case .bestFriends: return NSLocalizedString("audience.description.bestFriends", comment: "Best Friends description")
        case .custom: return NSLocalizedString("audience.description.custom", comment: "Custom description")
        case .customList: return NSLocalizedString("audience.description.customList", comment: "Custom List description")
        }
    }
}

struct ChainConfigurationView: View {
    private enum FlowDestination: Equatable {
        case main
        case continuationAudience
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var allowOthersToContinue: Bool
    @Binding var continuationAudience: ChainContinuationSetting
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    let chainTitleSummary: String?
    let isContinuing: Bool // 🔗 NUEVO: Indica si estamos continuando una cadena existente
    var onConfirm: (() -> Void)? // 🔗 NUEVO: Callback para cuando el usuario confirma la publicación
    
    @State private var flowDestination: FlowDestination = .main
    @State private var navigatingForward = true
    @State private var showingTitleValidationAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if case .main = flowDestination {
                    mainContent
                        .transition(flowTransition)
                } else {
                    ChainContinuationSelectorView(
                        selectedAudience: $continuationAudience,
                        selectedListId: $selectedListId,
                        selectedListName: $selectedListName,
                        customSelectedUsers: $customSelectedUsers,
                        embeddedInFlow: true,
                        onBack: {
                            navigate(to: .main, forward: false)
                        },
                        onComplete: {
                            navigate(to: .main, forward: false)
                        }
                    )
                    .transition(flowTransition)
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: flowDestination)
        }
        .alert(NSLocalizedString("storyChains.titleRequired.title", comment: ""), isPresented: $showingTitleValidationAlert) {
            Button(NSLocalizedString("storyChains.ok", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("storyChains.titleRequired.message", comment: ""))
        }
    }

    private var flowTransition: AnyTransition {
        if navigatingForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private var mainContent: some View {
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

                if let chainTitleSummary, !chainTitleSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("storyChains.chainTitle", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(.secondary)

                        Text(chainTitleSummary)
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                
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
                            }
                            
                            Text(NSLocalizedString("storyChains.allowOthersDescription", comment: "Allow others description"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Selector de audiencia (Solo lectura si es continuación)
                    if allowOthersToContinue {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("storyChains.continuationAudience", comment: "Continuation audience"))
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(.primary)
                            
                            Button(action: {
                                if !isContinuing {
                                    navigate(to: .continuationAudience)
                                }
                            }) {
                                HStack {
                                    AudienceIconView(
                                        audience: continuationAudienceForDisplay,
                                        size: AudienceIconMetrics.creatorRow,
                                        tintColor: isContinuing ? .secondary : nil,
                                        colorScheme: colorScheme
                                    )
                                    .frame(width: 28, alignment: .center)
                                    
                                    Text(getAudienceText())
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(isContinuing ? .secondary : .primary)
                                    
                                    Spacer()
                                    
                                    if !isContinuing {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .frame(width: 28, height: 28)
                                            .momentsChromeGlass(in: Circle(), interactive: true)
                                    }
                                }
                                .padding(.vertical, 4)
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
                    if !isContinuing && (chainTitleSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        showingTitleValidationAlert = true
                        return
                    }
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
    }
    
    // MARK: - Helper Functions
    private var continuationAudienceForDisplay: ContentAudience {
        if continuationAudience == .custom && selectedListId != nil {
            return .customList
        }
        return continuationAudience.contentAudience
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
                case .mutuals: return .mutuals
                case .bestFriends: return .bestFriends
                case .custom: return .custom
                case .customList: return .customList
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: continuationAudience = .everyone
                case .mutuals: continuationAudience = .mutuals
                case .bestFriends: continuationAudience = .bestFriends
                case .custom: continuationAudience = .custom
                case .customList: continuationAudience = .custom
                case .onlyMe: continuationAudience = .everyone
                }
            }
        )
    }

    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            flowDestination = destination
        }
    }
}

#Preview {
    ChainConfigurationView(
        allowOthersToContinue: .constant(true),
        continuationAudience: .constant(.everyone),
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        customSelectedUsers: .constant([]),
        chainTitleSummary: NSLocalizedString("storyChains.chain", comment: ""),
        isContinuing: false
    )
}
