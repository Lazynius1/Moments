import Foundation
import SwiftUI

struct MentionDraftToken: Equatable {
    let query: String
    let fullRange: Range<String.Index>
}

enum MomentMentionParser {
    static let mentionColor = Color(hex: "007AFF")

    struct Match {
        let range: Range<String.Index>
        let username: String
    }

    // Require a non-word / non-dot boundary before @ so emails like foo@bar.com
    // do not become social mentions.
    private static let mentionPattern = #"(?<![\w.])@(\w+)"#

    static func matches(in content: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: mentionPattern) else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        return regex.matches(in: content, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: content),
                  let usernameRange = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return Match(range: fullRange, username: String(content[usernameRange]))
        }
    }
}

enum MomentMentionLink {
    static func url(for username: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mention"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "value", value: username)]
        return components.url
    }

    static func username(from url: URL) -> String? {
        guard url.scheme == "mention" else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "value" })?.value,
           !value.isEmpty {
            return value
        }

        return url.host
    }
}

enum MentionParsing {
    static func extractUsernames(from text: String) -> [String] {
        MomentMentionParser.matches(in: text)
            .map { $0.username.lowercased() }
            .reduce(into: [String]()) { result, username in
                if !username.isEmpty, !result.contains(username) {
                    result.append(username)
                }
            }
    }

    static func detectActiveToken(in text: String) -> MentionDraftToken? {
        guard !text.isEmpty else { return nil }

        let tokenStart = text.lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        let tokenRange = tokenStart..<text.endIndex
        let token = String(text[tokenRange])
        guard token.hasPrefix("@"), token.count > 1 else { return nil }

        let query = String(token.dropFirst())
        guard query.count <= 30,
              query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }

        return MentionDraftToken(query: query, fullRange: tokenRange)
    }
}

enum MomentMentionNavigation {
    static func openProfile(forUsername username: String) {
        resolveProfile(forUsername: username) { userId in
            LegacyNavigationBridge.profile(userId: userId)
        }
    }

    static func resolveProfile(forUsername username: String, completion: @escaping (String) -> Void) {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        FirestoreService.shared.fetchUserByUsername(clean) { result in
            if case .success(let user) = result {
                completion(user.id)
            }
        }
    }
}

/// Resolves @username tokens in caption text for **mention notifications only**.
/// Must not be written to `Moment.taggedUsers` — that field bypasses audience privacy checks.
enum MomentMentionResolver {
    static func resolveUserIds(from text: String) async -> [String] {
        let usernames = MentionParsing.extractUsernames(from: text)
        guard !usernames.isEmpty else { return [] }

        var resolvedIds: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for username in usernames {
                group.addTask {
                    await resolveUserId(for: username)
                }
            }

            for await userId in group {
                if let userId {
                    resolvedIds.append(userId)
                }
            }
        }

        return Array(Set(resolvedIds))
    }

    private static func resolveUserId(for username: String) async -> String? {
        await withCheckedContinuation { continuation in
            FirestoreService.shared.fetchUserByUsername(username) { result in
                switch result {
                case .success(let user):
                    continuation.resume(returning: user.id)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
