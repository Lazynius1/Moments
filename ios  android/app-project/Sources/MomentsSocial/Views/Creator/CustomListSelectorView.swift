import SwiftUI

struct CustomListSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    
    @State var customLists: [CustomAudienceList] = []
    @State var isLoading = true
    @State var showingCreateList = false
    
    let userId: String
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(NSLocalizedString("audience.loadingLists", comment: "Loading lists..."))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if customLists.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("audience.noCustomLists.title", comment: "No custom lists"))
                                .font(.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(.primary)
                            
                            Text(NSLocalizedString("audience.noCustomLists.description", comment: "Create your first custom list"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            showingCreateList = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text(NSLocalizedString("audience.createFirstList", comment: "Create first list"))
                                    .font(.custom("Poppins-Medium", size: 16))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(customLists, id: \.id) { list in
                            Button(action: {
                                selectedListId = list.id
                                selectedListName = list.name
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name)
                                            .font(.custom("Poppins-SemiBold", size: 16))
                                            .foregroundColor(.primary)
                                        
                                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                                            .font(.custom("Poppins-Regular", size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedListId == list.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 20))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle(NSLocalizedString("audience.customLists", comment: "Custom Lists"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCreateList = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
        .onAppear {
            loadCustomLists()
        }
        .sheet(isPresented: $showingCreateList) {
            CustomAudienceListsView()
                .onDisappear { 
                    loadCustomLists()
                }
        }
    }
    
    private func loadCustomLists() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        FirestoreService().fetchCustomLists(for: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let lists):
                    self.customLists = lists
                case .failure(let error):
                    print("Error loading custom lists: \(error)")
                    self.customLists = []
                }
                self.isLoading = false
            }
        }
    }
}


#Preview {
    CustomListSelectorView(
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        userId: "test"
    )
}
