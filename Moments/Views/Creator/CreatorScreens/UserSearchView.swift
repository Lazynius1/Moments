// MARK: - User Search Implementation

import SwiftUI

struct UserSearchView: View {
    @Binding var selectedUsers: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var selectedUserIds = Set<String>()

    private let firestoreService = FirestoreService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.gray)

                    TextField(NSLocalizedString("creator.tag.search", comment: ""), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundStyle(.white)
                        .onChange(of: searchText) { _, newValue in
                            searchUsers(query: newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding()

                // Selected users
                if !selectedUserIds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(selectedUserIds), id: \.self) { userId in
                                if let user = searchResults.first(where: { $0.id == userId }) {
                                    SelectedUserChip(user: user) {
                                        selectedUserIds.remove(userId)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 10)
                }

                // Search results
                if isSearching {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("creator.searching")
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { user in
                                UserSearchRow(
                                    user: user,
                                    isSelected: selectedUserIds.contains(user.id)
                                ) {
                                    toggleUserSelection(user)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .background(Color.black)
            .navigationTitle("creator.tagPeople")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("creator.tag.done", comment: "")) {
                        selectedUsers = Array(selectedUserIds)
                        dismiss()
                    }
                    .foregroundStyle(.blue)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            // Load initial suggestions
            loadSuggestions()
        }
    }

    private func searchUsers(query: String) {
        guard !query.isEmpty else {
            loadSuggestions()
            return
        }

        isSearching = true

        firestoreService.searchUsers(query: query, limit: 10) { result in
            DispatchQueue.main.async {
                self.isSearching = false

                switch result {
                case .success(let users):
                    self.searchResults = users
                case .failure(_):
                    self.searchResults = []
                }
            }
        }
    }

    private func loadSuggestions() {
        // Load suggested users
        searchResults = []
    }

    private func toggleUserSelection(_ user: AppUser) {
        if selectedUserIds.contains(user.id) {
            selectedUserIds.remove(user.id)
        } else {
            selectedUserIds.insert(user.id)
        }
    }
}

struct UserSearchRow: View {
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile image
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)

                    if user.profileImagePath != nil {
                        // AsyncImage for profile
                        Image(systemName: "person.fill")
                            .foregroundStyle(.gray)
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.gray)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .gray)
                    .font(.title2)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct SelectedUserChip: View {
    let user: AppUser
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(user.username)
                .font(.caption)
                .foregroundStyle(.white)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue)
        .clipShape(Capsule())
    }
}
