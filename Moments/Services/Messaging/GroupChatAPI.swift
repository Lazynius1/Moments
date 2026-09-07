import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Group transport only. The shared chat keeps its existing message/attachment schema.
enum GroupChatAPI {
    static func request(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser, let project = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://europe-southwest1-\(project).cloudfunctions.net/\(endpoint)") else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonValue(body) ?? [:])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, Auth.auth().currentUser?.uid == user.uid else {
            throw NSError(domain: "GroupChat", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("groups.manageError", comment: "")])
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func jsonValue(_ value: Any) -> Any? {
        if value is FieldValue { return nil }
        if let bytes = value as? Data { return bytes.base64EncodedString() }
        if let timestamp = value as? Timestamp { return timestamp.dateValue().timeIntervalSince1970 * 1000 }
        if let date = value as? Date { return date.timeIntervalSince1970 * 1000 }
        if let map = value as? [String: Any] { return map.compactMapValues(jsonValue) }
        if let array = value as? [Any] { return array.compactMap(jsonValue) }
        return value
    }
}

extension ChatService {
    func persistChatMessage(_ reference: DocumentReference, data: [String: Any], completion: @escaping (Error?) -> Void) {
        let conversationId = data["conversationId"] as? String ?? reference.parent.parent?.documentID ?? ""
        guard GroupChatScope.isGroup(conversationId) else { reference.setData(data, completion: completion); return }
        Task {
            do {
                _ = try await GroupChatAPI.request("sendGroupMessage", body: ["groupId": conversationId, "messageId": reference.documentID, "message": data])
                completion(nil)
            } catch { completion(error) }
        }
    }
}
