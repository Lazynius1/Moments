import Foundation

enum NovaMomentAudience: Equatable {
    case everyone
    case connections
    case bestFriends
    case onlyMe
    case custom(userIds: [String], label: String)
    case customList(listId: String, listName: String)

    var contentAudience: ContentAudience {
        switch self {
        case .everyone: return .everyone
        case .connections: return .connections
        case .bestFriends: return .bestFriends
        case .onlyMe: return .onlyMe
        case .custom: return .custom
        case .customList: return .customList
        }
    }

    var audienceSetting: CaptionAndDetailsView.AudienceSetting {
        switch self {
        case .everyone: return .everyone
        case .connections: return .mutuals
        case .bestFriends: return .bestFriends
        case .onlyMe: return .onlyMe
        case .custom, .customList: return .custom
        }
    }

    var displayLabel: String {
        switch self {
        case .everyone:
            return ContentAudience.everyone.title
        case .connections:
            return ContentAudience.connections.title
        case .bestFriends:
            return ContentAudience.bestFriends.title
        case .onlyMe:
            return ContentAudience.onlyMe.title
        case .custom(_, let label):
            return label
        case .customList(_, let listName):
            return listName
        }
    }

    var customViewers: [String]? {
        if case .custom(let userIds, _) = self { return userIds }
        return nil
    }

    var customListId: String? {
        if case .customList(let listId, _) = self { return listId }
        return nil
    }
}

enum NovaMomentAudienceError: Error {
    case missingTargetUsername
    case missingCustomListName
    case userNotFound
    case listNotFound(available: [String])
    case noCustomLists
    case listLookupFailed
    case unknownAudience

    var code: String {
        switch self {
        case .missingTargetUsername: return "missing_target_username"
        case .missingCustomListName: return "missing_custom_list_name"
        case .userNotFound: return "user_not_found"
        case .listNotFound(let available):
            if available.isEmpty { return "list_not_found" }
            return "list_not_found:available=\(available.joined(separator: ", "))"
        case .noCustomLists: return "no_custom_lists"
        case .listLookupFailed: return "list_lookup_failed"
        case .unknownAudience: return "unknown_audience"
        }
    }
}

enum NovaMomentAudienceResolver {
    /// Canonical tool values only. The LLM maps user language → these before calling tools.
    static func normalizeAudienceRaw(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "best_friends", "bestfriends": return "bestfriends"
        case "only_me", "onlyme": return "onlyme"
        case "custom_list", "customlist": return "customlist"
        default: return key
        }
    }

    static func audienceSummary(
        audienceRaw: String,
        targetUsername: String?,
        customListName: String?
    ) -> String {
        switch normalizeAudienceRaw(audienceRaw) {
        case "everyone", "":
            return ContentAudience.everyone.title
        case "connections":
            return ContentAudience.connections.title
        case "bestfriends":
            return ContentAudience.bestFriends.title
        case "onlyme":
            return ContentAudience.onlyMe.title
        case "custom":
            if let targetUsername, !targetUsername.isEmpty {
                return targetUsername.hasPrefix("@") ? targetUsername : "@\(targetUsername)"
            }
            return ContentAudience.custom.title
        case "customlist":
            if let customListName, !customListName.isEmpty {
                return customListName
            }
            return ContentAudience.customList.title
        default:
            return audienceRaw.isEmpty ? ContentAudience.everyone.title : audienceRaw
        }
    }

    static func resolve(
        userId: String,
        audienceRaw: String,
        targetUsername: String?,
        customListName: String?,
        customListId: String?,
        firestoreService: FirestoreService
    ) async -> Result<NovaMomentAudience, NovaMomentAudienceError> {
        switch normalizeAudienceRaw(audienceRaw) {
        case "everyone", "":
            return .success(NovaMomentAudience.everyone)
        case "connections":
            return .success(NovaMomentAudience.connections)
        case "bestfriends":
            return .success(NovaMomentAudience.bestFriends)
        case "onlyme":
            return .success(NovaMomentAudience.onlyMe)
        case "custom":
            guard let username = targetUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !username.isEmpty else {
                return .failure(.missingTargetUsername)
            }
            return await resolveUsername(username, firestoreService: firestoreService)
        case "customlist":
            if let customListId, !customListId.isEmpty {
                return await resolveListId(customListId, ownerId: userId, firestoreService: firestoreService)
            }
            guard let listName = customListName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !listName.isEmpty else {
                return .failure(.missingCustomListName)
            }
            return await resolveListName(listName, ownerId: userId, firestoreService: firestoreService)
        default:
            return .failure(.unknownAudience)
        }
    }

    private static func resolveUsername(
        _ username: String,
        firestoreService: FirestoreService
    ) async -> Result<NovaMomentAudience, NovaMomentAudienceError> {
        let cleaned = username.hasPrefix("@") ? String(username.dropFirst()) : username
        do {
            let user = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppUser, Error>) in
                firestoreService.fetchUserByUsername(cleaned) { result in
                    continuation.resume(with: result)
                }
            }
            let label = "@\(user.username)"
            return .success(.custom(userIds: [user.id], label: label))
        } catch {
            return .failure(.userNotFound)
        }
    }

    private static func resolveListId(
        _ listId: String,
        ownerId: String,
        firestoreService: FirestoreService
    ) async -> Result<NovaMomentAudience, NovaMomentAudienceError> {
        do {
            let list = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CustomAudienceList, Error>) in
                firestoreService.fetchCustomListDetails(listId: listId, ownerId: ownerId) { result in
                    continuation.resume(with: result)
                }
            }
            guard let id = list.id else { return .failure(.listNotFound(available: [])) }
            return .success(.customList(listId: id, listName: list.name))
        } catch {
            return .failure(.listLookupFailed)
        }
    }

    private static func resolveListName(
        _ listName: String,
        ownerId: String,
        firestoreService: FirestoreService
    ) async -> Result<NovaMomentAudience, NovaMomentAudienceError> {
        do {
            let lists = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CustomAudienceList], Error>) in
                firestoreService.fetchCustomLists(for: ownerId) { result in
                    continuation.resume(with: result)
                }
            }

            let needle = listName.lowercased()
            if let exact = lists.first(where: { $0.name.lowercased() == needle }),
               let id = exact.id {
                return .success(.customList(listId: id, listName: exact.name))
            }
            if let partial = lists.first(where: { $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased()) }),
               let id = partial.id {
                return .success(.customList(listId: id, listName: partial.name))
            }

            let available = lists.map(\.name)
            if available.isEmpty {
                return .failure(.noCustomLists)
            }
            return .failure(.listNotFound(available: available))
        } catch {
            return .failure(.listLookupFailed)
        }
    }
}
