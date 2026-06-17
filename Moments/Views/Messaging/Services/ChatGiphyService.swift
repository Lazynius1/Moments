import Foundation
import FirebaseAuth
import FirebaseCore

/// Servicio compartido para consultar GIFs/stickers de Giphy vía Cloud Functions proxy.
/// Reutilizado por `ChatGiphyPickerSheet` (GIFs) y `ChatStickerPickerSheet` (stickers).
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
        limit: Int = 24
    ) async throws -> [GiphyGif] {
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
        return decoded.data
    }
}
