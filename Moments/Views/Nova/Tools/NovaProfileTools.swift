import Foundation
import FirebaseFirestore
import FirebaseAI

actor NovaProfileTools {
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService.shared
    private let echoService = EchoService.shared

    func myProfileSnapshot(userId: String) async -> JSONObject {
        do {
            let user = try await fetchUser(userId: userId)
            return profileObject(for: user)
        } catch {
            return ["error": .string(error.localizedDescription)]
        }
    }

    func followersSummary(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let recent = try await firestoreService.fetchFollowersWithTimestamps(userId: userId)
            return [
                "total_count": NovaJSON.int(recent.count),
                "recent_followers": .array(recent.prefix(capped).map { item in
                    .object([
                        "user_id": .string(item.user.id),
                        "username": .string(item.user.username),
                        "bio_preview": .string(String((item.user.bio ?? "").prefix(80))),
                        "timestamp": NovaJSON.iso(item.timestamp)
                    ])
                })
            ]
        } catch {
            return ["error": .string(error.localizedDescription), "total_count": .number(0), "recent_followers": .array([])]
        }
    }

    func followingSummary(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let following: [AppUser] = try await continuationResult { callback in
                firestoreService.fetchFollowing(userId: userId, completion: callback)
            }
            let followingPayload: [JSONValue] = following.prefix(capped).map { user in
                .object([
                    "user_id": .string(user.id),
                    "username": .string(user.username),
                    "bio_preview": .string(String((user.bio ?? "").prefix(80)))
                ])
            }
            return [
                "total_count": NovaJSON.int(following.count),
                "following": .array(followingPayload)
            ]
        } catch {
            return ["error": .string(error.localizedDescription), "total_count": .number(0), "following": .array([])]
        }
    }

    func mutualConnections(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let mutuals: [AppUser] = try await continuationResult { callback in
                firestoreService.fetchMutualConnections(userId: userId, completion: callback)
            }
            let mutualPayload: [JSONValue] = mutuals.prefix(capped).map { user in
                .object([
                    "user_id": .string(user.id),
                    "username": .string(user.username),
                    "bio_preview": .string(String((user.bio ?? "").prefix(80)))
                ])
            }
            return [
                "total_count": NovaJSON.int(mutuals.count),
                "mutual_connections": .array(mutualPayload)
            ]
        } catch {
            return ["error": .string(error.localizedDescription), "total_count": .number(0), "mutual_connections": .array([])]
        }
    }

    func sharedInterestUsers(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let me = try await fetchUser(userId: userId)
            let users: [AppUser] = try await continuationResult { callback in
                firestoreService.fetchUsersWithSharedInterests(interests: me.interests, excludingUserId: userId, completion: callback)
            }
            let userPayload: [JSONValue] = users.prefix(capped).map { user in
                let sharedInterests = user.interests
                    .filter { me.interests.contains($0) }
                    .map(JSONValue.string)

                return .object([
                    "user_id": .string(user.id),
                    "username": .string(user.username),
                    "shared_interests": .array(sharedInterests),
                    "bio_preview": .string(String((user.bio ?? "").prefix(80)))
                ])
            }
            return [
                "total_count": NovaJSON.int(users.count),
                "users": .array(userPayload)
            ]
        } catch {
            return ["error": .string(error.localizedDescription), "total_count": .number(0), "users": .array([])]
        }
    }

    func findUser(username: String) async -> JSONObject {
        let clean = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
        guard !clean.isEmpty else { return ["error": .string("missing_username")] }
        do {
            let user: AppUser = try await continuationResult { callback in
                firestoreService.fetchUserByUsername(clean, completion: callback)
            }
            return profileObject(for: user)
        } catch {
            return ["error": .string(error.localizedDescription)]
        }
    }

    func sendFollowRequest(currentUserId: String, username: String) async -> JSONObject {
        do {
            let cleanedUsername = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
            let user: AppUser = try await continuationResult { callback in
                firestoreService.fetchUserByUsername(cleanedUsername, completion: callback)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                firestoreService.sendFollowRequest(currentUserId: currentUserId, targetUserId: user.id) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return [
                "success": .bool(true),
                "target_user_id": .string(user.id),
                "username": .string(user.username)
            ]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func profilePrivacy(userId: String) async -> JSONObject {
        do {
            let settings = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(isPrivate: Bool, showMutualConnections: Bool, showFollowing: Bool, showAdmirers: Bool), Error>) in
                privacyService.fetchPrivacySettings(userId: userId) { result in
                    continuation.resume(with: result)
                }
            }
            return [
                "is_private": .bool(settings.isPrivate),
                "show_mutual_connections": .bool(settings.showMutualConnections),
                "show_following": .bool(settings.showFollowing),
                "show_admirers": .bool(settings.showAdmirers)
            ]
        } catch {
            return ["error": .string(error.localizedDescription)]
        }
    }

    func updatePrivacy(
        userId: String,
        isPrivate: Bool?,
        showMutualConnections: Bool?,
        showFollowing: Bool?,
        showAdmirers: Bool?
    ) async -> JSONObject {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                privacyService.updatePrivacySettings(
                    userId: userId,
                    isPrivate: isPrivate,
                    showMutualConnections: showMutualConnections,
                    showFollowing: showFollowing,
                    showAdmirers: showAdmirers
                ) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return [
                "success": .bool(true),
                "is_private": isPrivate.map(JSONValue.bool) ?? .null,
                "show_mutual_connections": showMutualConnections.map(JSONValue.bool) ?? .null,
                "show_following": showFollowing.map(JSONValue.bool) ?? .null,
                "show_admirers": showAdmirers.map(JSONValue.bool) ?? .null
            ]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func updateBio(userId: String, bio: String) async -> JSONObject {
        do {
            let me = try await fetchUser(userId: userId)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                firestoreService.updateProfileDetails(
                    userId: userId,
                    oldBio: me.bio,
                    newBio: bio,
                    oldWebsite: nil,
                    newWebsite: nil
                ) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return ["success": .bool(true), "bio": .string(bio)]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func updateWebsite(userId: String, website: String) async -> JSONObject {
        do {
            let me = try await fetchUser(userId: userId)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                firestoreService.updateProfileDetails(
                    userId: userId,
                    oldBio: nil,
                    newBio: nil,
                    oldWebsite: me.websiteUrl,
                    newWebsite: website
                ) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return ["success": .bool(true), "website": .string(website)]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func updateActiveHours(userId: String, startHour: String?, endHour: String?, clear: Bool) async -> JSONObject {
        do {
            if clear {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    firestoreService.clearActiveHours(userId: userId) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                    }
                }
                return ["success": .bool(true), "cleared": .bool(true)]
            }

            guard let startHour, let endHour, !startHour.isEmpty, !endHour.isEmpty else {
                return ["success": .bool(false), "error": .string("missing_hours")]
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                firestoreService.updateActiveHours(userId: userId, startHour: startHour, endHour: endHour) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return ["success": .bool(true), "start_hour": .string(startHour), "end_hour": .string(endHour)]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func updateNotificationPreferences(userId: String, preferences: [String: Bool]) async -> JSONObject {
        do {
            let current = try await fetchUser(userId: userId)
            let merged = (current.notificationPreferences ?? [:]).merging(preferences) { _, new in new }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                firestoreService.updateNotificationPreferences(userId: userId, preferences: merged) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ()) }
                }
            }
            return [
                "success": .bool(true),
                "preferences": .object(Dictionary(uniqueKeysWithValues: merged.map { ($0.key, .bool($0.value)) }))
            ]
        } catch {
            return ["success": .bool(false), "error": .string(error.localizedDescription)]
        }
    }

    func userProfileSnapshot(userId: String, username: String?, targetUserId: String?) async -> JSONObject {
        do {
            let user: AppUser
            if let targetUserId, !targetUserId.isEmpty {
                user = try await fetchUser(userId: targetUserId)
            } else if let username, !username.isEmpty {
                let cleanedUsername = username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ").union(.whitespacesAndNewlines))
                user = try await continuationResult { callback in
                    firestoreService.fetchUserByUsername(cleanedUsername, completion: callback)
                }
            } else {
                user = try await fetchUser(userId: userId)
            }
            return profileObject(for: user)
        } catch {
            return ["error": .string(error.localizedDescription)]
        }
    }

    func recentMomentsSummary(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let moments: [Moment] = try await continuationResult { callback in
                firestoreService.fetchMomentsFromUsers(
                    userIds: [userId],
                    perUserLimit: capped,
                    totalLimit: capped,
                    completion: callback
                )
            }
            let recentPayload: [JSONValue] = moments.prefix(capped).map(momentSummaryObject)
            return [
                "total_count": NovaJSON.int(moments.count),
                "recent_moments": .array(recentPayload)
            ]
        } catch {
            return ["error": .string(error.localizedDescription), "total_count": .number(0), "recent_moments": .array([])]
        }
    }

    func recentStoriesSummary(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        do {
            let stories: [Story] = try await continuationResult { callback in
                firestoreService.fetchAllStories(userId: userId, completion: callback)
            }
            let now = Date()
            let activeCount = stories.filter { $0.expirationDate > now }.count
            let archivedCount = stories.count - activeCount
            let recentPayload: [JSONValue] = stories.prefix(capped).map { story in
                storySummaryObject(story, now: now)
            }
            return [
                "total_count": NovaJSON.int(stories.count),
                "active_count": NovaJSON.int(activeCount),
                "archived_count": NovaJSON.int(archivedCount),
                "recent_stories": .array(recentPayload)
            ]
        } catch {
            return [
                "error": .string(error.localizedDescription),
                "total_count": .number(0),
                "active_count": .number(0),
                "archived_count": .number(0),
                "recent_stories": .array([])
            ]
        }
    }

    func profileAndContentOverview(userId: String, momentLimit: Int = 5, storyLimit: Int = 5) async -> JSONObject {
        async let profile = myProfileSnapshot(userId: userId)
        async let moments = recentMomentsSummary(userId: userId, limit: momentLimit)
        async let stories = recentStoriesSummary(userId: userId, limit: storyLimit)

        return [
            "profile": .object(await profile),
            "moments": .object(await moments),
            "stories": .object(await stories)
        ]
    }

    func momentDetails(momentId: String, userId: String) async -> JSONObject {
        do {
            let moment: Moment = try await continuationResult { callback in
                firestoreService.fetchMoment(momentId: momentId, userId: userId, completion: callback)
            }
            return [
                "moment_id": .string(moment.id ?? momentId),
                "author_id": .string(moment.authorId),
                "username": .string(moment.username),
                "content": .string(moment.content),
                "comment_count": NovaJSON.int(moment.commentCount),
                "created_at": NovaJSON.iso(moment.timestamp),
                "is_archived": .bool(moment.isArchived ?? false),
                "has_location": .bool(moment.locationCoordinate != nil),
                "location_name": .string(moment.location ?? "")
            ]
        } catch {
            return ["error": .string(error.localizedDescription)]
        }
    }

    func echoHistorySummary(userId: String, limit: Int = 5) async -> JSONObject {
        let capped = min(max(limit, 1), 10)
        return await withCheckedContinuation { continuation in
            var registration: ListenerRegistration?
            registration = echoService.fetchEchoHistory(userId: userId) { echoes in
                registration?.remove()
                continuation.resume(returning: [
                    "total_count": NovaJSON.int(echoes.count),
                    "echoes": .array(echoes.prefix(capped).map { echo in
                        .object([
                            "echo_id": .string(echo.id ?? ""),
                            "status": .string(echo.status.rawValue),
                            "participant_count": NovaJSON.int(echo.participants.count),
                            "accepted_count": NovaJSON.int(echo.participants.filter { $0.status == .accepted }.count),
                            "location_name": .string(echo.locationName ?? ""),
                            "created_at": NovaJSON.iso(echo.createdAt),
                            "expires_at": NovaJSON.iso(echo.expiresAt)
                        ])
                    })
                ])
            }
        }
    }

    private func fetchUser(userId: String) async throws -> AppUser {
        try await continuationResult { callback in
            firestoreService.fetchUser(userId: userId, completion: callback)
        }
    }

    private func profileObject(for user: AppUser) -> JSONObject {
        [
            "user_id": .string(user.id),
            "username": .string(user.username),
            "bio": .string(user.bio ?? ""),
            "website": .string(user.websiteUrl ?? ""),
            "is_private": .bool(user.isPrivate),
            "followers_count": NovaJSON.int(user.followersCount),
            "following_count": NovaJSON.int(user.followingCount),
            "moments_count": NovaJSON.int(user.momentsCount),
            "interests": .array(user.interests.map(JSONValue.string)),
            "active_hours": .object([
                "start_hour": .string(user.activeHoursStart ?? ""),
                "end_hour": .string(user.activeHoursEnd ?? "")
            ]),
            "notification_preferences": .object(Dictionary(uniqueKeysWithValues: (user.notificationPreferences ?? [:]).map { ($0.key, .bool($0.value)) }))
        ]
    }

    private func momentSummaryObject(_ moment: Moment) -> JSONValue {
        let visibleMedia = moment.visibleMediaItems
        let primaryMediaType = visibleMedia.first?.type.rawValue
        let mediaTypes = visibleMedia.map { JSONValue.string($0.type.rawValue) }
        return .object([
            "moment_id": .string(moment.id ?? ""),
            "created_at": NovaJSON.iso(moment.timestamp),
            "content": .string(moment.content),
            "audience": .string(moment.audience ?? ""),
            "comment_count": NovaJSON.int(moment.commentCount),
            "reaction_kinds_count": NovaJSON.int(moment.reactions.keys.count),
            "total_reactions_count": NovaJSON.int(moment.reactions.values.reduce(0) { $0 + $1.count }),
            "is_archived": .bool(moment.isArchived ?? false),
            "is_scheduled": .bool(moment.isScheduled),
            "has_location": .bool(moment.locationCoordinate != nil || !(moment.location ?? "").isEmpty),
            "location_name": .string(moment.location ?? ""),
            "media_count": NovaJSON.int(visibleMedia.count),
            "primary_media_type": .string(primaryMediaType ?? ""),
            "media_types": .array(mediaTypes),
            "tagged_users_count": NovaJSON.int(moment.taggedUsers?.count ?? 0),
            "has_hidden_layers": .bool(moment.hasHiddenLayers)
        ])
    }

    private func storySummaryObject(_ story: Story, now: Date) -> JSONValue {
        .object([
            "story_id": .string(story.id ?? ""),
            "created_at": NovaJSON.iso(story.timestamp),
            "expires_at": NovaJSON.iso(story.expirationDate),
            "is_active": .bool(story.expirationDate > now),
            "audience": .string(story.audience ?? ""),
            "text": .string(story.text ?? ""),
            "media_type": .string(story.mediaItem.type.rawValue),
            "aspect_ratio": .string(story.aspectRatio ?? ""),
            "has_stickers": .bool(!(story.stickers ?? []).isEmpty),
            "is_chain_story": .bool(story.chainId != nil),
            "chain_title": .string(story.chainTitle ?? "")
        ])
    }
}

private func continuationResult<T>(
    _ work: (@escaping (Result<T, Error>) -> Void) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        work { result in
            continuation.resume(with: result)
        }
    }
}
