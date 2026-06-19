import Foundation
import FirebaseAuth
import FirebaseCore

struct ChatGiphyPage {
    let items: [GiphyGif]
    let hasMore: Bool
    let nextOffset: Int
}

/// Servicio compartido para consultar GIFs/stickers de Giphy vía Cloud Functions proxy.
/// Reutilizado por `ChatGiphyPickerContent` (GIFs y stickers).
@MainActor
final class ChatGiphyService {
    static let shared = ChatGiphyService()

    enum FunctionName: String {
        case gifs = "proxyGiphyGifs"
        case stickers = "proxyGiphyStickers"
    }

    enum Mode: String {
        case trending
        case search
    }

    private let functionsRegion = "europe-southwest1"

    private init() {}

    private func proxyURL(for function: FunctionName) -> URL? {
        guard let projectID = FirebaseApp.app()?.options.projectID else { return nil }
        return URL(string: "https://\(functionsRegion)-\(projectID).cloudfunctions.net/\(function.rawValue)")
    }

    func fetch(
        function: FunctionName,
        mode: Mode,
        query: String? = nil,
        offset: Int = 0,
        limit: Int = 24
    ) async throws -> ChatGiphyPage {
        guard let url = proxyURL(for: function) else {
            throw NSError(domain: "ChatGiphyService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid proxy URL"])
        }
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "ChatGiphyService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let token = try await user.getIDTokenResult(forcingRefresh: false).token

        var body: [String: Any] = [
            "mode": mode.rawValue,
            "limit": limit,
            "offset": max(0, offset),
            "rating": "pg"
        ]
        if let query, !query.isEmpty {
            body["query"] = query
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20.0

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(GiphyResponse.self, from: data)

        let pageOffset = decoded.pagination?.offset ?? offset
        let pageCount = decoded.pagination?.count ?? decoded.data.count
        let totalCount = decoded.pagination?.total_count
        let hasMore: Bool
        if let totalCount {
            hasMore = pageOffset + pageCount < totalCount
        } else {
            hasMore = decoded.data.count >= limit
        }

        return ChatGiphyPage(
            items: decoded.data,
            hasMore: hasMore,
            nextOffset: pageOffset + pageCount
        )
    }
}
