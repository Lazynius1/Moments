import SwiftUI

struct LiveUsernameContent<Content: View>: View {
    let userId: String
    let fallbackUsername: String
    let content: (String) -> Content

    @State private var liveUsername: String = ""

    var body: some View {
        content(resolvedUsername)
            .onAppear {
                refreshUsername()
            }
            .onChange(of: userId) { _, _ in
                refreshUsername()
            }
            .onChange(of: fallbackUsername) { _, _ in
                if liveUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    refreshUsername()
                }
            }
    }

    private var resolvedUsername: String {
        let live = liveUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return fallback.isEmpty ? "Usuario" : fallback
    }

    private func refreshUsername() {
        let trimmedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserId.isEmpty else {
            liveUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: trimmedUserId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.userId.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedUserId else { return }
                self.liveUsername = fetchedUsername
            }
        }
    }
}

struct LiveUsernameText: View {
    let userId: String
    let fallbackUsername: String
    var prefix: String = ""

    var body: some View {
        LiveUsernameContent(userId: userId, fallbackUsername: fallbackUsername) { username in
            Text("\(prefix)\(username)")
        }
    }
}

