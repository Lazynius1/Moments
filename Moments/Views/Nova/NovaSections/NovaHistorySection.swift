import SwiftUI

// MARK: - Componentes UI Originales
struct ConversationHistoryOverlay: View {
    @ObservedObject var viewModel: NovaAgent
    @Binding var showConversationHistory: Bool
    @Binding var showSuggestedOptions: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Fondo adaptativo
            Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    showConversationHistory = false
                }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Header del historial
                    HStack {
                        Text("nova.recentConversations")
                            .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                            .foregroundColor(NovaColors.textPrimary)

                        Spacer()

                        Button(action: {
                            showConversationHistory = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(NovaColors.textPrimary)
                                .frame(width: 36, height: 36)
                                .background {
                                    Color.clear
                                        .momentsChromeGlass(in: Circle(), interactive: true)
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    // Lista de conversaciones
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if viewModel.conversationTitles.isEmpty {
                                VStack(spacing: 16) {
                                    AttachmentIconView(icon: .comments, preset: .emptyStateHero, tintColor: NovaColors.textSecondary)

                                    Text("nova.noConversations")
                                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                                        .foregroundColor(NovaColors.textSecondary)

                                    Text("nova.startNewConversation")
                                        .font(.system(size: legacyPoppinsSize(14)))
                                        .foregroundColor(NovaColors.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.vertical, 40)
                            } else {
                                // Botón para nueva conversación
                                Button(action: {
                                    viewModel.startNewConversation()
                                    showConversationHistory = false
                                    showSuggestedOptions = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(NovaColors.textPrimary)
                                            .frame(width: 28, height: 28)
                                            .background {
                                                Color.clear
                                                    .momentsChromeGlass(in: Circle(), interactive: true)
                                            }

                                        Text("nova.newConversation")
                                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                                            .foregroundColor(NovaColors.textPrimary)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(NovaColors.textSecondary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background {
                                        Color.clear
                                            .momentsChromeGlass(in: Capsule(), interactive: true)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                                // Conversaciones guardadas
                                ForEach(viewModel.conversationTitles.reversed()) { conversation in
                                    ConversationHistoryItem(
                                        conversation: conversation,
                                        viewModel: viewModel,
                                        onSelect: {
                                            Task {
                                                await viewModel.loadConversation(conversation.id)
                                                showConversationHistory = false
                                                showSuggestedOptions = false
                                            }
                                        },
                                        onDelete: {
                                            Task {
                                                await viewModel.deleteConversation(conversation.id)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ConversationHistoryItem: View {
    let conversation: ConversationTitle
    @ObservedObject var viewModel: NovaAgent
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteAlert = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {

            Task {
                await viewModel.loadConversation(conversation.id)
                onSelect()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(NovaColors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(conversation.lastUpdated.timeAgoDisplay())
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundColor(NovaColors.textSecondary)

                    if conversation.messageCount > 0 {
                        Text("\(conversation.messageCount) \(NSLocalizedString("nova.messages", comment: "Messages count"))")
                            .font(.system(size: legacyPoppinsSize(11)))
                            .foregroundColor(NovaColors.textTertiary)
                    }
                }

                Spacer()

                Menu {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        Label(NSLocalizedString("nova.actions.delete", comment: "Delete action"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(NovaColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Color.clear
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            }
        }
        .alert(NSLocalizedString("nova.actions.deleteConversation.title", comment: "Delete conversation alert title"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("nova.actions.cancel", comment: "Cancel action"), role: .cancel) { }
            Button(NSLocalizedString("nova.actions.delete", comment: "Delete action"), role: .destructive, action: onDelete)
        } message: {
                Text("nova.deleteConversation.confirm")
        }
    }
}
