import FirebaseAI

enum NovaToolRegistry {
    static var allDeclarations: [FunctionDeclaration] {
        activityTools + socialTools + profileTools + memoryTools
    }

    static var toolSet: Tool {
        Tool.functionDeclarations(allDeclarations)
    }

    private static var activityTools: [FunctionDeclaration] {
        [
            FunctionDeclaration(
                name: "get_activity_summary",
                description: "Recent activity overview: profile visits and latest story chain.",
                parameters: [:]
            ),
            FunctionDeclaration(
                name: "get_weekly_summary",
                description: "Week-over-week comparison of moments, engagement, visits, and story views.",
                parameters: [:]
            ),
            FunctionDeclaration(
                name: "get_profile_visits",
                description: "Recent profile visits with usernames and timestamps.",
                parameters: [
                    "limit": .integer(description: "Max visits to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_story_chain_info",
                description: "Latest story chain details and optional viewer summary.",
                parameters: [
                    "include_viewers": .boolean(description: "Include recent viewers if true.")
                ],
                optionalParameters: ["include_viewers"]
            )
        ]
    }

    private static var socialTools: [FunctionDeclaration] {
        [
            FunctionDeclaration(
                name: "create_moment",
                description: """
                Publish a moment with the photo attached in this chat message. After success, the upload starts automatically.
                Do not tell the user to confirm in chat — in-app approval is handled separately.
                Moments cannot be text-only — media must be attached via the chat (+ button) before calling.
                audience: everyone | mutuals | bestFriends | onlyMe | custom | customList.
                Call list_audience_lists first if the user refers to a list by vague name.
                """,
                parameters: [
                    "content": .string(description: "Optional caption. Include @username (no space) to mention people; mentions are resolved automatically for linking/notifications and do not change audience."),
                    "audience": .string(description: "Exactly: everyone | mutuals | bestFriends | onlyMe | custom | customList"),
                    "target_username": .string(description: "For audience=custom: username without @."),
                    "custom_list_name": .string(description: "For audience=customList: list name."),
                    "custom_list_id": .string(description: "Optional list id if already known.")
                ],
                optionalParameters: ["content", "target_username", "custom_list_name", "custom_list_id"]
            ),
            FunctionDeclaration(
                name: "list_audience_lists",
                description: "List the user's custom audience lists (id, name, member count) for moment publishing.",
                parameters: [:]
            ),
            FunctionDeclaration(
                name: "get_connection_suggestions",
                description: "Suggested users to connect with based on interests and mutuals.",
                parameters: [
                    "limit": .integer(description: "Max suggestions (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            )
        ]
    }

    private static var profileTools: [FunctionDeclaration] {
        [
            FunctionDeclaration(
                name: "get_my_profile_snapshot",
                description: "Return a neutral JSON snapshot of the current user's profile and settings.",
                parameters: [:]
            ),
            FunctionDeclaration(
                name: "get_followers_summary",
                description: "Return a neutral JSON summary of the current user's recent followers.",
                parameters: [
                    "limit": .integer(description: "Max users to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_following_summary",
                description: "Return a neutral JSON summary of the current user's following list.",
                parameters: [
                    "limit": .integer(description: "Max users to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_mutuals",
                description: "Return mutual followers for the current user in neutral JSON.",
                parameters: [
                    "limit": .integer(description: "Max users to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_shared_interest_users",
                description: "Return users who share interests with the current user in neutral JSON.",
                parameters: [
                    "limit": .integer(description: "Max users to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_recent_moments_summary",
                description: "Return a neutral JSON summary of the current user's most recent moments for analysis and coaching.",
                parameters: [
                    "limit": .integer(description: "Max moments to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_recent_stories_summary",
                description: "Return a neutral JSON summary of the current user's recent stories, including active and archived counts.",
                parameters: [
                    "limit": .integer(description: "Max stories to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            ),
            FunctionDeclaration(
                name: "get_profile_and_content_overview",
                description: "Return a combined neutral JSON overview of the current user's profile, recent moments, and recent stories.",
                parameters: [
                    "moment_limit": .integer(description: "Max moments to include (default 5, max 10)."),
                    "story_limit": .integer(description: "Max stories to include (default 5, max 10).")
                ],
                optionalParameters: ["moment_limit", "story_limit"]
            ),
            FunctionDeclaration(
                name: "find_user_by_username",
                description: "Look up a user profile by username and return a neutral JSON snapshot.",
                parameters: [
                    "username": .string(description: "Username to search, with or without @.")
                ]
            ),
            FunctionDeclaration(
                name: "send_follow_request",
                description: "Send a follow request to a user by username. Requires user confirmation.",
                parameters: [
                    "username": .string(description: "Target username, with or without @.")
                ]
            ),
            FunctionDeclaration(
                name: "get_profile_privacy_settings",
                description: "Return the current user's privacy settings in neutral JSON.",
                parameters: [:]
            ),
            FunctionDeclaration(
                name: "update_profile_privacy_settings",
                description: "Update the current user's privacy settings. Requires user confirmation. Only include keys the user actually wants to change.",
                parameters: [
                    "is_private": .boolean(description: "Whether the account should be private."),
                    "show_mutuals": .boolean(description: "Whether mutuals should be visible."),
                    "show_following": .boolean(description: "Whether following should be visible."),
                    "show_followers": .boolean(description: "Whether followers should be visible.")
                ],
                optionalParameters: ["is_private", "show_mutuals", "show_following", "show_followers"]
            ),
            FunctionDeclaration(
                name: "update_profile_bio",
                description: "Update the current user's profile bio. Requires user confirmation. Use an empty string only if the user explicitly wants to clear it.",
                parameters: [
                    "bio": .string(description: "New bio text.")
                ]
            ),
            FunctionDeclaration(
                name: "update_profile_website",
                description: "Update the current user's profile website. Requires user confirmation. Use an empty string only if the user explicitly wants to clear it.",
                parameters: [
                    "website": .string(description: "New website URL.")
                ]
            ),
            FunctionDeclaration(
                name: "update_active_hours",
                description: "Update or clear the current user's active hours. Requires user confirmation.",
                parameters: [
                    "start_hour": .string(description: "Start hour in HH:mm format."),
                    "end_hour": .string(description: "End hour in HH:mm format."),
                    "clear": .boolean(description: "Set true only when explicitly clearing active hours.")
                ],
                optionalParameters: ["start_hour", "end_hour", "clear"]
            ),
            FunctionDeclaration(
                name: "update_notification_preferences",
                description: "Update one or more notification preferences for the current user. Requires user confirmation.",
                parameters: [
                    "like": .boolean(description: "Enable or disable like notifications."),
                    "reaction": .boolean(description: "Enable or disable reaction notifications."),
                    "comment": .boolean(description: "Enable or disable comment notifications."),
                    "mention": .boolean(description: "Enable or disable mention notifications."),
                    "newFollower": .boolean(description: "Enable or disable new follower notifications."),
                    "followRequest": .boolean(description: "Enable or disable follow request notifications."),
                    "requestAccepted": .boolean(description: "Enable or disable request accepted notifications."),
                    "mutualConnection": .boolean(description: "Enable or disable mutual connection notifications."),
                    "storyReaction": .boolean(description: "Enable or disable story reaction notifications."),
                    "message": .boolean(description: "Enable or disable message notifications."),
                    "photoTag": .boolean(description: "Enable or disable photo tag notifications."),
                    "echoSuggestion": .boolean(description: "Enable or disable Echo suggestion notifications."),
                    "dataExportReady": .boolean(description: "Enable or disable data export ready notifications."),
                    "storyChainContinued": .boolean(description: "Enable or disable story chain notifications."),
                    "mediaModeration": .boolean(description: "Enable or disable moderation notifications."),
                    "gentleReminders": .boolean(description: "Enable or disable gentle reminders."),
                    "commentsMutualsOnly": .boolean(description: "Enable or disable comments from mutuals only."),
                    "muteOldPostReactions": .boolean(description: "Enable or disable old post reaction notifications.")
                ]
                ,
                optionalParameters: [
                    "like",
                    "reaction",
                    "comment",
                    "mention",
                    "newFollower",
                    "followRequest",
                    "requestAccepted",
                    "mutualConnection",
                    "storyReaction",
                    "message",
                    "photoTag",
                    "echoSuggestion",
                    "dataExportReady",
                    "storyChainContinued",
                    "mediaModeration",
                    "gentleReminders",
                    "commentsMutualsOnly",
                    "muteOldPostReactions"
                ]
            ),
            FunctionDeclaration(
                name: "get_user_profile_snapshot",
                description: "Return a neutral JSON profile snapshot. Defaults to the current user if no identifier is supplied.",
                parameters: [
                    "username": .string(description: "Optional username, with or without @."),
                    "user_id": .string(description: "Optional target user id.")
                ],
                optionalParameters: ["username", "user_id"]
            ),
            FunctionDeclaration(
                name: "get_moment_details",
                description: "Return neutral JSON details for a specific moment id if available to the current user.",
                parameters: [
                    "moment_id": .string(description: "Concrete moment id.")
                ]
            ),
            FunctionDeclaration(
                name: "get_echo_history_summary",
                description: "Return a neutral JSON summary of recent Echo history for the current user.",
                parameters: [
                    "limit": .integer(description: "Max echoes to return (default 5, max 10).")
                ],
                optionalParameters: ["limit"]
            )
        ]
    }

    private static var memoryTools: [FunctionDeclaration] {
        [
            FunctionDeclaration(
                name: "remember_fact",
                description: "Persist a durable fact the user explicitly asked to remember. Requires user confirmation. Do NOT use for names (use update_user_preference) or info already in context.",
                parameters: [
                    "content": .string(description: "Fact in the user's language."),
                    "type": .string(
                        description: "One of: preference, personal, professional, interest, general."
                    )
                ],
                optionalParameters: ["type"]
            ),
            FunctionDeclaration(
                name: "update_user_preference",
                description: "Update a user preference. Requires user confirmation. Use key preferred_name for names.",
                parameters: [
                    "key": .string(description: "Preference key, e.g. preferred_name or tone."),
                    "value": .string(description: "Preference value.")
                ]
            )
        ]
    }

    static let confirmationRequiredTools: Set<String> = [
        "create_moment",
        "remember_fact",
        "update_user_preference",
        "send_follow_request",
        "update_profile_privacy_settings",
        "update_profile_bio",
        "update_profile_website",
        "update_active_hours",
        "update_notification_preferences"
    ]
}
