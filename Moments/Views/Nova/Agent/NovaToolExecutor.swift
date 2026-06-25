import Foundation
import FirebaseAI
import UIKit

@MainActor
final class NovaToolExecutor {
    static let maxStepsPerTurn = 15

    private let userId: String
    private let activityTools = NovaActivityTools()
    private let socialTools = NovaSocialTools()
    private let profileTools = NovaProfileTools()
    private let memoryTools: NovaMemoryTools
    private var executedSignatures = Set<String>()

    var attachedImageForTurn: UIImage?
    var onMemoryUpdated: ((NovaMemory) -> Void)?
    var onMomentCreated: (() -> Void)?
    var requestUserConfirmation: ((NovaPendingAction) async -> Bool)?

    init(userId: String, memoryStore: NovaMemoryStore) {
        self.userId = userId
        self.memoryTools = NovaMemoryTools(store: memoryStore)
    }

    convenience init(userId: String) {
        self.init(userId: userId, memoryStore: .shared)
    }

    func resetTurn() {
        executedSignatures.removeAll()
    }

    func execute(_ calls: [FunctionCallPart]) async throws -> [FunctionResponsePart] {
        var responses: [FunctionResponsePart] = []
        for call in calls {
            let signature = "\(call.name):\(call.args.description)"
            if executedSignatures.contains(signature) {
                responses.append(FunctionResponsePart(
                    name: call.name,
                    response: ["error": .string("Duplicate tool call skipped.")]
                ))
                continue
            }
            executedSignatures.insert(signature)

            let payload = await dispatch(name: call.name, args: call.args)
            responses.append(FunctionResponsePart(name: call.name, response: payload))
        }
        return responses
    }

    func executeCreateMoment(args: JSONObject, image: UIImage) async -> JSONObject {
        attachedImageForTurn = image
        let content = stringArg(args["content"]) ?? ""
        let audience = stringArg(args["audience"]) ?? "everyone"
        let targetUsername = stringArg(args["target_username"])
        let customListName = stringArg(args["custom_list_name"])
        let customListId = stringArg(args["custom_list_id"])

        let result = await socialTools.createMoment(
            userId: userId,
            content: content,
            audienceRaw: audience,
            targetUsername: targetUsername,
            customListName: customListName,
            customListId: customListId,
            attachedImage: image
        )
        if case .bool(true) = result["success"] {
            await MainActor.run { onMomentCreated?() }
        }
        return result
    }

    private func dispatch(name: String, args: JSONObject) async -> JSONObject {
        if NovaToolRegistry.confirmationRequiredTools.contains(name) {
            if name == "create_moment", attachedImageForTurn == nil {
                return [
                    "success": .bool(false),
                    "error": .string("missing_media"),
                    "hint": .string("Moments require a photo or video. Ask the user to attach media in the chat (+ button).")
                ]
            }
            guard let action = NovaPendingAction.from(
                toolName: name,
                args: args,
                previewImage: name == "create_moment" ? attachedImageForTurn : nil
            ) else {
                return errorObject("invalid_action_args")
            }
            let approved = await requestUserConfirmation?(action) ?? false
            if !approved {
                return [
                    "success": .bool(false),
                    "status": .string("cancelled_by_user"),
                    "message": .string("The user declined this action in the app.")
                ]
            }
        }

        switch name {
        case "get_activity_summary":
            return (try? await activityTools.activitySummary(userId: userId)) ?? errorObject("activity_summary_failed")
        case "get_weekly_summary":
            return (try? await activityTools.weeklySummary(userId: userId)) ?? errorObject("weekly_summary_failed")
        case "get_profile_visits":
            let limit = intArg(args["limit"]) ?? 5
            return (try? await activityTools.profileVisits(userId: userId, limit: limit)) ?? errorObject("profile_visits_failed")
        case "get_story_chain_info":
            let includeViewers = boolArg(args["include_viewers"]) ?? false
            return (try? await activityTools.storyChainInfo(userId: userId, includeViewers: includeViewers)) ?? errorObject("story_chain_failed")
        case "create_moment":
            guard attachedImageForTurn != nil else {
                return [
                    "success": .bool(false),
                    "error": .string("missing_media"),
                    "hint": .string("Moments require a photo or video. Ask the user to attach media in the chat (+ button).")
                ]
            }
            let content = stringArg(args["content"]) ?? ""
            let audience = stringArg(args["audience"]) ?? "everyone"
            let targetUsername = stringArg(args["target_username"])
            let customListName = stringArg(args["custom_list_name"])
            let customListId = stringArg(args["custom_list_id"])

            let result = await socialTools.createMoment(
                userId: userId,
                content: content,
                audienceRaw: audience,
                targetUsername: targetUsername,
                customListName: customListName,
                customListId: customListId,
                attachedImage: attachedImageForTurn
            )
            if case .bool(true) = result["success"] {
                onMomentCreated?()
            }
            return result
        case "list_audience_lists":
            return await socialTools.listAudienceLists(userId: userId)
        case "get_connection_suggestions":
            let limit = intArg(args["limit"]) ?? 5
            return await socialTools.connectionSuggestions(limit: limit)
        case "get_followers_summary":
            return await profileTools.followersSummary(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "get_following_summary":
            return await profileTools.followingSummary(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "get_my_profile_snapshot":
            return await profileTools.myProfileSnapshot(userId: userId)
        case "get_recent_moments_summary":
            return await profileTools.recentMomentsSummary(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "get_recent_stories_summary":
            return await profileTools.recentStoriesSummary(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "get_profile_and_content_overview":
            return await profileTools.profileAndContentOverview(
                userId: userId,
                momentLimit: intArg(args["moment_limit"]) ?? 5,
                storyLimit: intArg(args["story_limit"]) ?? 5
            )
        case "get_mutuals", "get_mutual_connections":
            return await profileTools.mutuals(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "get_shared_interest_users":
            return await profileTools.sharedInterestUsers(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "find_user_by_username":
            guard let username = stringArg(args["username"]) else {
                return errorObject("missing_username")
            }
            return await profileTools.findUser(username: username)
        case "send_follow_request":
            guard let username = stringArg(args["username"]) else {
                return errorObject("missing_username")
            }
            return await profileTools.sendFollowRequest(currentUserId: userId, username: username)
        case "get_profile_privacy_settings":
            return await profileTools.profilePrivacy(userId: userId)
        case "update_profile_privacy_settings":
            return await profileTools.updatePrivacy(
                userId: userId,
                isPrivate: boolArg(args["is_private"]),
                showMutuals: boolArg(args["show_mutuals"]) ?? boolArg(args["show_mutual_connections"]),
                showFollowing: boolArg(args["show_following"]),
                showFollowers: boolArg(args["show_followers"])
            )
        case "update_profile_bio":
            guard let bio = stringArg(args["bio"]) else {
                return errorObject("missing_bio")
            }
            return await profileTools.updateBio(userId: userId, bio: bio)
        case "update_profile_website":
            guard let website = stringArg(args["website"]) else {
                return errorObject("missing_website")
            }
            return await profileTools.updateWebsite(userId: userId, website: website)
        case "update_active_hours":
            return await profileTools.updateActiveHours(
                userId: userId,
                startHour: stringArg(args["start_hour"]),
                endHour: stringArg(args["end_hour"]),
                clear: boolArg(args["clear"]) ?? false
            )
        case "update_notification_preferences":
            let preferences = boolDictionaryArgs(args)
            guard !preferences.isEmpty else {
                return errorObject("missing_preferences")
            }
            return await profileTools.updateNotificationPreferences(userId: userId, preferences: preferences)
        case "get_user_profile_snapshot":
            return await profileTools.userProfileSnapshot(
                userId: userId,
                username: stringArg(args["username"]),
                targetUserId: stringArg(args["user_id"])
            )
        case "get_moment_details":
            guard let momentId = stringArg(args["moment_id"]), !momentId.isEmpty else {
                return errorObject("missing_moment_id")
            }
            return await profileTools.momentDetails(momentId: momentId, userId: userId)
        case "get_echo_history_summary":
            return await profileTools.echoHistorySummary(userId: userId, limit: intArg(args["limit"]) ?? 5)
        case "remember_fact":
            guard let content = stringArg(args["content"]) else { return errorObject("missing_content") }
            let type = stringArg(args["type"]).flatMap { NovaFactType(rawValue: $0) }
            let result = await memoryTools.rememberFact(userId: userId, content: content, type: type)
            await refreshMemory()
            return result
        case "update_user_preference":
            guard let key = stringArg(args["key"]), let value = stringArg(args["value"]) else {
                return errorObject("missing_key_or_value")
            }
            let result = await memoryTools.updatePreference(userId: userId, key: key, value: value)
            await refreshMemory()
            return result
        default:
            return errorObject("unknown_tool")
        }
    }

    private func refreshMemory() async {
        let memoryStore = NovaMemoryStore.shared
        if let memory = await memoryStore.loadMemory(userId: userId) {
            onMemoryUpdated?(memory)
        }
    }

    private func errorObject(_ code: String) -> JSONObject {
        ["success": .bool(false), "error": .string(code)]
    }

    private func stringArg(_ value: JSONValue?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text
    }

    private func intArg(_ value: JSONValue?) -> Int? {
        switch value {
        case let .number(number):
            return Int(number)
        case let .string(text):
            return Int(text)
        default:
            return nil
        }
    }

    private func boolArg(_ value: JSONValue?) -> Bool? {
        guard case let .bool(flag) = value else { return nil }
        return flag
    }

    private func boolDictionaryArgs(_ args: JSONObject) -> [String: Bool] {
        var preferences: [String: Bool] = [:]
        for (key, value) in args {
            guard case let .bool(flag) = value else { continue }
            preferences[key] = flag
        }
        return preferences
    }

    /// Localized success copy when create_moment succeeded but model follow-up fails (e.g. thought_signature).
    static func momentSuccessMessage(from responses: [FunctionResponsePart]) -> String? {
        for part in responses where part.name == "create_moment" {
            guard case .bool(true) = part.response["success"] else { continue }
            if case .string(let label) = part.response["audience_label"], !label.isEmpty {
                return String(format: NSLocalizedString("nova.moment.published", comment: ""), label)
            }
            return NSLocalizedString("nova.moment.publishedGeneric", comment: "")
        }
        return nil
    }
}
