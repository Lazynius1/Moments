import Foundation
import FirebaseAuth
import FirebaseCore

private struct BackendProfileVisitsResponse: Codable {
    let groupedVisits: [BackendGroupedVisitPayload]
    let uniqueVisitorCount: Int
    let source: String
}

private struct BackendGroupedVisitPayload: Codable {
    let visitorId: String
    let visits: [BackendVisitPayload]

    func toVisits() -> [Visit] {
        visits.map {
            Visit(
                visitorId: visitorId,
                timestamp: Date(timeIntervalSince1970: $0.timestamp / 1000)
            )
        }
    }
}

private struct BackendVisitPayload: Codable {
    let id: String?
    let timestamp: Double
}

@MainActor
final class ProfileVisitsService {
    static let shared = ProfileVisitsService()

    private let firestoreService = FirestoreService()

    func fetchGroupedVisits(userId: String, limit: Int = 1000) async -> [GroupedVisit] {
        if let grouped = await fetchFromFunction(limit: limit) {
            return grouped
        }
        return await fetchFromFirestore(userId: userId)
    }

    private func fetchFromFunction(limit: Int) async -> [GroupedVisit]? {
        guard let user = Auth.auth().currentUser else { return nil }

        do {
            let idToken = try await user.getIDToken()
            let projectId = FirebaseApp.app()?.options.projectID ?? ""
            let region = "europe-southwest1"
            let urlString = "https://\(region)-\(projectId).cloudfunctions.net/getProfileVisitsPage"

            guard let url = URL(string: urlString) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["limit": limit])
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoded = try JSONDecoder().decode(BackendProfileVisitsResponse.self, from: data)
            let visits = decoded.groupedVisits.flatMap { $0.toVisits() }
            let grouped = try await buildGroupedVisits(from: visits)

            LogConfig.log(
                "✅ ProfileVisits function: \(decoded.uniqueVisitorCount) visitantes",
                category: "ProfileVisits"
            )
            return grouped
        } catch {
            LogConfig.log("❌ ProfileVisits function error: \(error.localizedDescription)", category: "ProfileVisits")
            return nil
        }
    }

    private func fetchFromFirestore(userId: String) async -> [GroupedVisit] {
        do {
            let visits = try await fetchVisits(userId: userId)
            let grouped = try await buildGroupedVisits(from: visits)
            LogConfig.log("✅ ProfileVisits firestore fallback: \(grouped.count) visitantes", category: "ProfileVisits")
            return grouped
        } catch {
            LogConfig.log("❌ ProfileVisits firestore error: \(error.localizedDescription)", category: "ProfileVisits")
            return []
        }
    }

    private func buildGroupedVisits(from visits: [Visit]) async throws -> [GroupedVisit] {
        let uniqueVisitorIds = VisitGrouping.uniqueVisitorIds(from: visits)
        guard !uniqueVisitorIds.isEmpty else { return [] }

        let users = try await firestoreService.fetchUsersAsync(userIds: uniqueVisitorIds)
        return VisitGrouping.build(visits: visits, users: users)
    }

    private func fetchVisits(userId: String) async throws -> [Visit] {
        try await withCheckedThrowingContinuation { continuation in
            firestoreService.fetchVisits(userId: userId) { result in
                continuation.resume(with: result)
            }
        }
    }
}
