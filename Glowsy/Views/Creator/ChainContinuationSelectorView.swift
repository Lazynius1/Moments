import SwiftUI
import FirebaseAuth

// MARK: - Custom User Selector View
struct CustomUserSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedUsers: [String]
    
    @State private var selectedUsersForCustom: [AppUser] = []
    
    var body: some View {
        NavigationView {
            CustomAudienceSelector(selectedUsers: $selectedUsersForCustom) {
                selectedUsers = selectedUsersForCustom.map { $0.id }
                dismiss()
            }
            .navigationTitle(NSLocalizedString("audience.actions.selectPeople", comment: "Select people navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("audience.actions.cancel", comment: "Cancel action")) {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            // Cargar usuarios seleccionados actuales
            loadSelectedUsersInfo()
        }
    }
    
    private func loadSelectedUsersInfo() {
        guard !selectedUsers.isEmpty else { return }
        FirestoreService().fetchUsers(userIds: selectedUsers) { result in
            if case .success(let users) = result {
                DispatchQueue.main.async {
                    selectedUsersForCustom = users
                }
            }
        }
    }
}

struct ChainContinuationSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAudience: ChainContinuationSetting
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    
    @State private var showingCustomUserSelector = false
    @State private var showingCustomListSelector = false
    @State private var showingCustomListCreator = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "link")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    
                    Text(NSLocalizedString("storyChains.continuationAudience", comment: "Who can continue this chain?"))
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Lista de opciones
                VStack(spacing: 0) {
                    ForEach(ChainContinuationSetting.allCases, id: \.self) { audience in
                                    Button(action: {
                                        selectedAudience = audience
                                        if audience == .custom {
                                            showingCustomUserSelector = true
                                        } else if audience == .customList {
                                            showingCustomListCreator = true
                                        } else {
                                            dismiss()
                                        }
                                    }) {
                            HStack(spacing: 16) {
                                Image(systemName: audience.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(audience.title)
                                        .font(.custom("Poppins-Medium", size: 16))
                                        .foregroundColor(.primary)
                                    
                                    if audience == .custom && !customSelectedUsers.isEmpty {
                                        Text(String(format: NSLocalizedString("storyEditor.customAudience.multiple", comment: "%d people"), customSelectedUsers.count))
                                            .font(.custom("Poppins-Regular", size: 14))
                                            .foregroundColor(.secondary)
                                    } else if audience == .customList && selectedListName != nil {
                                        Text(selectedListName!)
                                            .font(.custom("Poppins-Regular", size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedAudience == audience {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                selectedAudience == audience ? Color.blue.opacity(0.1) : Color.clear
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if audience != ChainContinuationSetting.allCases.last {
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
                .sheet(isPresented: $showingCustomUserSelector) {
                    CustomUserSelectorView(
                        selectedUsers: $customSelectedUsers
                    )
                }
                .sheet(isPresented: $showingCustomListCreator) {
                    CustomListSelectorView(
                        selectedListId: $selectedListId,
                        selectedListName: $selectedListName,
                        userId: Auth.auth().currentUser?.uid ?? ""
                    )
                }
    }
    
    // MARK: - Helper Functions
    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch selectedAudience {
                case .everyone: return .everyone
                case .connections: return .connections
                case .bestFriends: return .bestFriends
                case .custom: return .custom
                case .customList: return .customList
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: selectedAudience = .everyone
                case .connections: selectedAudience = .connections
                case .bestFriends: selectedAudience = .bestFriends
                case .custom: selectedAudience = .custom
                case .customList: selectedAudience = .customList
                case .onlyMe: selectedAudience = .everyone // Not applicable for continuation
                }
            }
        )
    }
}

#Preview {
    ChainContinuationSelectorView(
        selectedAudience: .constant(.everyone),
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        customSelectedUsers: .constant([])
    )
}
