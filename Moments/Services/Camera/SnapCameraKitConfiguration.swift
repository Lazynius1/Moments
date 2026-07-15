import Foundation

enum SnapCameraKitConfiguration {
    /// Flag maestro: desactiva los filtros AR en toda la app mientras solo haya lentes demo.
    /// Cuando haya filtros reales listos, cambiar a `true` para reactivar la selección de lentes.
    static let isFeatureEnabled = false

    private static let loadedValues: (apiToken: String?, clientID: String?, lensGroupID: String?) = {
        let bundleToken = normalized(Bundle.main.object(forInfoDictionaryKey: "SCCameraKitAPIToken") as? String)
        let bundleClientID = normalized(Bundle.main.object(forInfoDictionaryKey: "SCCameraKitClientID") as? String)

        guard let plistURL = Bundle.main.url(forResource: "SnapCameraKit", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return (bundleToken, bundleClientID, nil)
        }

        let groupID = normalized(plist["SnapCameraKitLensGroupID"] as? String)
        return (bundleToken, bundleClientID, groupID)
    }()

    static var apiToken: String? { loadedValues.apiToken }
    static var clientID: String? { loadedValues.clientID }
    static var defaultLensGroupID: String? { loadedValues.lensGroupID }

    static var isConfigured: Bool {
        apiToken != nil && clientID != nil && defaultLensGroupID != nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
