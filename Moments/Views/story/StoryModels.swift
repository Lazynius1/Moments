import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Story Models
struct StoryReaction: Identifiable {
    let id: String
    let userId: String
    let reaction: String
    let timestamp: Date
}

extension Array where Element == StoryReaction {
    /// Una reacción por persona: la más reciente sobrescribe las anteriores.
    func latestPerUser() -> [StoryReaction] {
        var latestByUser: [String: StoryReaction] = [:]

        for reaction in self {
            if let existing = latestByUser[reaction.userId] {
                if reaction.timestamp > existing.timestamp {
                    latestByUser[reaction.userId] = reaction
                }
            } else {
                latestByUser[reaction.userId] = reaction
            }
        }

        return latestByUser.values.sorted { $0.timestamp > $1.timestamp }
    }
}

struct StoryViewer: Identifiable {
    let id: String
    let userId: String
    let username: String?
    let profileImagePath: String?
    let timestamp: Date
    let viewCount: Int
    let firstViewedAt: Date?
    let lastViewedAt: Date?

    init(
        id: String,
        userId: String,
        username: String?,
        profileImagePath: String?,
        timestamp: Date,
        viewCount: Int = 1,
        firstViewedAt: Date? = nil,
        lastViewedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.username = username
        self.profileImagePath = profileImagePath
        self.timestamp = timestamp
        self.viewCount = max(viewCount, 1)
        self.firstViewedAt = firstViewedAt
        self.lastViewedAt = lastViewedAt
    }

    var rewatchBadgeText: String? {
        guard viewCount > 1 else { return nil }
        return "x\(viewCount)"
    }

    static func from(documentId: String, data: [String: Any]) -> StoryViewer? {
        guard let userId = data["userId"] as? String else {
            return nil
        }

        let lastViewedAt = (data["lastViewedAt"] as? Timestamp)?.dateValue()
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()
            ?? lastViewedAt
            ?? (data["firstViewedAt"] as? Timestamp)?.dateValue()
        guard let timestamp else {
            return nil
        }

        let firstViewedAt = (data["firstViewedAt"] as? Timestamp)?.dateValue()
        let rawViewCount = data["viewCount"] as? Int ?? 1

        return StoryViewer(
            id: documentId,
            userId: userId,
            username: data["username"] as? String,
            profileImagePath: data["profileImagePath"] as? String,
            timestamp: timestamp,
            viewCount: rawViewCount,
            firstViewedAt: firstViewedAt,
            lastViewedAt: lastViewedAt ?? timestamp
        )
    }
}

// MARK: - Story Ring Component
struct StoryRing: View {
    let hasStory: Bool
    let hasUnseenStory: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: hasStory ? 2.5 : 0
            )
            .frame(width: size, height: size)
            .opacity(hasStory ? 1.0 : 0.3)
    }

    private var gradientColors: [Color] {
        if hasUnseenStory {
            return [.pink, .orange, .yellow]
        } else if hasStory {
            return [.gray.opacity(0.5), .gray.opacity(0.7)]
        }
        return [.clear]
    }
}

// MARK: - Verified Badge View
struct VerifiedBadgeView: View {
    let userId: String
    let size: CGFloat
    @State private var isVerified: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                // Placeholder mientras carga
                Color.clear
                    .frame(width: size, height: size)
            } else if isVerified {
                VerifiedBadge(size: size)
            } else {
                // No mostrar nada si no está verificado
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            checkVerificationStatus()
        }
    }

    private func checkVerificationStatus() {
        Firestore.firestore().collection("users").document(userId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let data = snapshot?.data() {
                        isVerified = data["isVerified"] as? Bool ?? false
                    }
                }
            }
    }
}

// MARK: - Current User Verified Badge
struct CurrentUserVerifiedBadge: View {
    let size: CGFloat
    @State private var isVerified: Bool = false
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if isLoading {
                // Placeholder mientras carga
                Color.clear
                    .frame(width: size, height: size)
            } else if isVerified {
                VerifiedBadge(size: size)
            } else {
                // No mostrar nada si no está verificado
                Color.clear
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            checkCurrentUserVerificationStatus()
        }
    }

    private func checkCurrentUserVerificationStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        Firestore.firestore().collection("users").document(currentUserId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let data = snapshot?.data() {
                        isVerified = data["isVerified"] as? Bool ?? false
                    }
                }
            }
    }
}
