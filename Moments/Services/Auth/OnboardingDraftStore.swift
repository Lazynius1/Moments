import Foundation
import UIKit

enum OnboardingDraftContext: String, Codable {
    case apple
    case email
}

struct OnboardingDraft: Codable, Equatable {
    var context: OnboardingDraftContext
    var firebaseUID: String?
    var step: Int
    var username: String
    var email: String
    var selectedInterests: [String]
    var privacyPolicyAccepted: Bool
    var profileImageFilename: String?
    var pendingAppleEmail: String?
    var startedAt: Date
    var updatedAt: Date
}

enum OnboardingDraftStore {
    private static let storageKey = "pendingOnboardingDraft"
    private static let ttl: TimeInterval = 30 * 24 * 60 * 60
    private static let draftsDirectoryName = "OnboardingDrafts"

    static func load() -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    static func save(_ draft: OnboardingDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        if let draft = load() {
            removeProfileImage(filename: draft.profileImageFilename)
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: draftsDirectoryURL)
    }

    static func clearPersistedData() {
        if let draft = load() {
            removeProfileImage(filename: draft.profileImageFilename)
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: draftsDirectoryURL)
    }

    static func isExpired(_ draft: OnboardingDraft) -> Bool {
        Date().timeIntervalSince(draft.updatedAt) > ttl
    }

    static func markStarted(context: OnboardingDraftContext, firebaseUID: String? = nil, pendingAppleEmail: String? = nil) {
        var draft = load() ?? OnboardingDraft(
            context: context,
            firebaseUID: firebaseUID,
            step: 1,
            username: "",
            email: "",
            selectedInterests: [],
            privacyPolicyAccepted: false,
            profileImageFilename: nil,
            pendingAppleEmail: pendingAppleEmail,
            startedAt: Date(),
            updatedAt: Date()
        )

        draft.context = context
        if let firebaseUID {
            draft.firebaseUID = firebaseUID
        }
        if let pendingAppleEmail {
            draft.pendingAppleEmail = pendingAppleEmail
        }
        draft.updatedAt = Date()
        save(draft)
    }

    static func updateUID(_ uid: String) {
        guard var draft = load() else { return }
        draft.firebaseUID = uid
        draft.updatedAt = Date()
        save(draft)
    }

    static func update(
        step: Int? = nil,
        username: String? = nil,
        email: String? = nil,
        selectedInterests: [String]? = nil,
        privacyPolicyAccepted: Bool? = nil,
        profileImage: UIImage? = nil,
        firebaseUID: String? = nil,
        pendingAppleEmail: String? = nil
    ) {
        guard var draft = load() else { return }

        if let step { draft.step = min(max(step, 1), 3) }
        if let username { draft.username = username }
        if let email { draft.email = email }
        if let selectedInterests { draft.selectedInterests = selectedInterests }
        if let privacyPolicyAccepted { draft.privacyPolicyAccepted = privacyPolicyAccepted }
        if let firebaseUID { draft.firebaseUID = firebaseUID }
        if let pendingAppleEmail { draft.pendingAppleEmail = pendingAppleEmail }

        if let profileImage {
            if let previous = draft.profileImageFilename {
                removeProfileImage(filename: previous)
            }
            draft.profileImageFilename = saveProfileImage(profileImage)
        }

        draft.updatedAt = Date()
        save(draft)
    }

    static func profileImage(from draft: OnboardingDraft) -> UIImage? {
        guard let filename = draft.profileImageFilename else { return nil }
        let url = draftsDirectoryURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static var draftsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent(draftsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func saveProfileImage(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let filename = "profile-\(UUID().uuidString).jpg"
        let url = draftsDirectoryURL.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    private static func removeProfileImage(filename: String?) {
        guard let filename else { return }
        let url = draftsDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
