import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Foundation
import MessageUI
import UIKit
import Compression
import ZIPFoundation

class DataExportService: ObservableObject {
    private let db = Firestore.firestore()
    
    func generateRealDataExport(
        userId: String,
        exportType: ExportType,
        format: ExportFormat,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !userId.isEmpty else {
            completion(.failure(NSError(domain: "DataExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no válido"])))
            return
        }
        
        // Start the export process
        fetchAllUserData(userId: userId, exportType: exportType) { [weak self] result in
            switch result {
            case .success(let userData):
                self?.createExportFile(userData: userData, format: format, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func fetchAllUserData(
        userId: String,
        exportType: ExportType,
        completion: @escaping (Result<UserExportData, Error>) -> Void
    ) {
        let group = DispatchGroup()
        var exportData = UserExportData()
        var fetchError: Error?
        
        // Fetch user profile
        group.enter()
        db.collection("users").document(userId).getDocument { snapshot, error in
            defer { group.leave() }
            if let error = error {
                fetchError = error
                return
            }
            if let data = snapshot?.data() {
                exportData.profile = data
            }
        }
        
        // Fetch moments (if not media-only export)
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "moments") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.moments = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch stories (if not media-only export)
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "stories") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.stories = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch following
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "following") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.following = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }

        // Fetch mutuals
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "mutuals") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.mutuals = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch followers
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "followers") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.followers = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch conversations (if not media-only)
        if exportType != .mediaOnly {
            group.enter()
            fetchUserConversations(userId: userId) { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.conversations = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch notifications
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "notifications") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.notifications = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch activity data
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "dailyStats") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.activityStats = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch login activity
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "loginActivity") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.loginActivity = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch saved moments
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "savedMoments") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.savedMoments = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch visits and visit summaries
        if exportType != .mediaOnly {
            group.enter()
            fetchCollection(userId: userId, collection: "visits") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.visits = data
                case .failure(let error):
                    fetchError = error
                }
            }
            
            group.enter()
            fetchCollection(userId: userId, collection: "visitSummaries") { result in
                defer { group.leave() }
                switch result {
                case .success(let data):
                    exportData.visitSummaries = data
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        // Fetch media URLs (if not text-only export)
        if exportType != .textOnly {
            group.enter()
            fetchMediaUrls(userId: userId) { result in
                defer { group.leave() }
                switch result {
                case .success(let urls):
                    exportData.mediaUrls = urls
                case .failure(let error):
                    fetchError = error
                }
            }
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
            } else {
                completion(.success(exportData))
            }
        }
    }
    
    private func fetchCollection(
        userId: String,
        collection: String,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        db.collection("users").document(userId).collection(collection)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let documents: [[String: Any]] = snapshot?.documents.compactMap { doc in
                    var data = doc.data()
                    data["documentId"] = doc.documentID
                    return data
                } ?? []
                completion(.success(documents))
            }
    }
    
    private func fetchUserConversations(
        userId: String,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let self = self else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                    return
                }
                
                let conversations = snapshot?.documents ?? []
                let group = DispatchGroup()
                var allConversationData: [[String: Any]] = []
                var fetchError: Error?
                
                for conversation in conversations {
                    group.enter()
                    let conversationId = conversation.documentID
                    var conversationData = conversation.data()
                    conversationData["conversationId"] = conversationId
                    
                    // Fetch messages for this conversation
                    self.db.collection("conversations").document(conversationId).collection("messages")
                        .order(by: "timestamp")
                        .getDocuments { snapshot, error in
                            defer { group.leave() }
                            
                            if let error = error {
                                fetchError = error
                                return
                            }
                            
                            let messages = snapshot?.documents.map { doc in
                                var messageData = doc.data()
                                messageData["messageId"] = doc.documentID
                                return messageData
                            } ?? []
                            conversationData["messages"] = messages
                            allConversationData.append(conversationData)
                        }
                }
                
                group.notify(queue: .main) {
                    if let error = fetchError {
                        completion(.failure(error))
                    } else {
                        completion(.success(allConversationData))
                    }
                }
            }
    }
    
    private func fetchMediaUrls(
        userId: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        var mediaUrls: [String] = []
        let group = DispatchGroup()
        var fetchError: Error?
        
        // Get media from moments
        group.enter()
        db.collection("users").document(userId).collection("moments")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    fetchError = error
                    return
                }
                
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    if let imagePath = data["imagePath"] as? String, !imagePath.isEmpty {
                        mediaUrls.append(imagePath)
                    }
                    if let videoUrl = data["videoUrl"] as? String, !videoUrl.isEmpty {
                        mediaUrls.append(videoUrl)
                    }
                    // Handle mediaItems array
                    if let mediaItems = data["mediaItems"] as? [[String: Any]] {
                        mediaItems.forEach { item in
                            if let url = item["url"] as? String, !url.isEmpty {
                                mediaUrls.append(url)
                            }
                        }
                    }
                }
            }
        
        // Get media from stories
        group.enter()
        db.collection("users").document(userId).collection("stories")
            .getDocuments { snapshot, error in
                defer { group.leave() }
                
                if let error = error {
                    fetchError = error
                    return
                }
                
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    if let mediaItem = data["mediaItem"] as? [String: Any],
                       let url = mediaItem["url"] as? String, !url.isEmpty {
                        mediaUrls.append(url)
                    }
                }
            }
        
        // Get profile image
        group.enter()
        db.collection("users").document(userId).getDocument { snapshot, error in
            defer { group.leave() }
            
            if let error = error {
                fetchError = error
                return
            }
            
            if let data = snapshot?.data(),
               let profileImagePath = data["profileImagePath"] as? String, !profileImagePath.isEmpty {
                mediaUrls.append(profileImagePath)
            }
        }
        
        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
            } else {
                completion(.success(Array(Set(mediaUrls)))) // Remove duplicates
            }
        }
    }
    
    private func createExportFile(
        userData: UserExportData,
        format: ExportFormat,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = dateFormatter.string(from: Date())
                let fileName = "moments_export_\(timestamp)"
                
                let fileURL: URL
                
                switch format {
                case .json:
                    fileURL = documentsPath.appendingPathComponent("\(fileName).json")
                    try self.createJSONExport(userData: userData, fileURL: fileURL)
                    
                case .csv:
                    // Create a ZIP file with multiple CSV files
                    fileURL = documentsPath.appendingPathComponent("\(fileName).zip")
                    try self.createCSVExportWithZIP(userData: userData, fileURL: fileURL)
                }
                
                DispatchQueue.main.async {
                    completion(.success(fileURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func createJSONExport(userData: UserExportData, fileURL: URL) throws {
        let exportDict: [String: Any] = [
            "exportInfo": [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "version": "1.0",
                "platform": "iOS"
            ],
            "profile": userData.profile ?? [:],
            "moments": userData.moments ?? [],
            "stories": userData.stories ?? [],
            "following": userData.following ?? [],
            "mutuals": userData.mutuals ?? [],
            "followers": userData.followers ?? [],
            "conversations": userData.conversations ?? [],
            "notifications": userData.notifications ?? [],
            "activityStats": userData.activityStats ?? [],
            "loginActivity": userData.loginActivity ?? [],
            "savedMoments": userData.savedMoments ?? [],
            "visits": userData.visits ?? [],
            "visitSummaries": userData.visitSummaries ?? [],
            "mediaUrls": userData.mediaUrls ?? []
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
        try jsonData.write(to: fileURL)
    }
    
    private func createCSVExportWithZIP(userData: UserExportData, fileURL: URL) throws {
        // For CSV, we'll create multiple files in a ZIP
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create individual CSV files
        if let profile = userData.profile {
            try createProfileCSV(profile: profile, directory: tempDir)
        }
        
        if let moments = userData.moments {
            try createMomentsCSV(moments: moments, directory: tempDir)
        }
        
        if let stories = userData.stories {
            try createStoriesCSV(stories: stories, directory: tempDir)
        }
        
        if let following = userData.following {
            try createSocialListCSV(rows: following, filename: "following.csv", directory: tempDir)
        }

        if let mutuals = userData.mutuals {
            try createSocialListCSV(rows: mutuals, filename: "mutuals.csv", directory: tempDir)
        }
        
        if let followers = userData.followers {
            try createFollowersCSV(followers: followers, directory: tempDir)
        }
        
        if let conversations = userData.conversations {
            try createConversationsCSV(conversations: conversations, directory: tempDir)
        }
        
        if let activityStats = userData.activityStats {
            try createActivityStatsCSV(activityStats: activityStats, directory: tempDir)
        }
        
        if let loginActivity = userData.loginActivity {
            try createLoginActivityCSV(loginActivity: loginActivity, directory: tempDir)
        }
        
        if let mediaUrls = userData.mediaUrls {
            try createMediaUrlsCSV(mediaUrls: mediaUrls, directory: tempDir)
        }

        // ✅ Export detallado
        // 1) Conversaciones completas en JSON por conversación
        // 2) Descarga de multimedia al ZIP (best effort)
        try createDetailedConversationsExport(conversations: userData.conversations ?? [], directory: tempDir)
        let allMediaUrls = collectAllMediaUrls(userData: userData)
        try createDownloadedMediaExport(mediaUrls: allMediaUrls, directory: tempDir)
        
        // Create README file
        try createReadmeFile(directory: tempDir)
        
        // Create ZIP file with iOS-compatible method
        try createZIPWithFoundation(sourceDirectory: tempDir, destinationURL: fileURL)
        
        // Cleanup temp directory
        try FileManager.default.removeItem(at: tempDir)
    }
    
    private func createProfileCSV(profile: [String: Any], directory: URL) throws {
        var csvContent = "Field,Value\n"
        
        for (key, value) in profile.sorted(by: { $0.key < $1.key }) {
            let valueString = "\(value)".replacingOccurrences(of: "\"", with: "\"\"")
            csvContent += "\"\(key)\",\"\(valueString)\"\n"
        }
        
        let fileURL = directory.appendingPathComponent("profile.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createMomentsCSV(moments: [[String: Any]], directory: URL) throws {
        var csvContent = "DocumentID,AuthorID,Username,Content,Timestamp,ImagePath,VideoURL,CommentCount,ReactionCount\n"
        
        for moment in moments {
            let documentId = moment["documentId"] as? String ?? ""
            let authorId = moment["authorId"] as? String ?? ""
            let username = moment["username"] as? String ?? ""
            let content = (moment["content"] as? String ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let timestamp = formatTimestamp(moment["timestamp"])
            let imagePath = moment["imagePath"] as? String ?? ""
            let videoUrl = moment["videoUrl"] as? String ?? ""
            let commentCount = moment["commentCount"] as? Int ?? 0
            
            // Count reactions
            var reactionCount = 0
            if let reactions = moment["reactions"] as? [String: [String]] {
                reactionCount = reactions.values.reduce(0) { $0 + $1.count }
            }
            
            csvContent += "\"\(documentId)\",\"\(authorId)\",\"\(username)\",\"\(content)\",\"\(timestamp)\",\"\(imagePath)\",\"\(videoUrl)\",\(commentCount),\(reactionCount)\n"
        }
        
        let fileURL = directory.appendingPathComponent("moments.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createStoriesCSV(stories: [[String: Any]], directory: URL) throws {
        var csvContent = "DocumentID,AuthorID,Username,MediaType,MediaURL,Timestamp,ExpirationDate,ExpirationHours,Duration\n"
        
        for story in stories {
            let documentId = story["documentId"] as? String ?? ""
            let authorId = story["authorId"] as? String ?? ""
            let username = story["username"] as? String ?? ""
            let timestamp = formatTimestamp(story["timestamp"])
            let expirationDate = formatTimestamp(story["expirationDate"])
            let expirationHours = story["expirationHours"] as? Int ?? (story["chainId"] != nil ? 48 : 24)
            let duration = story["duration"] as? Double ?? 0.0
            
            var mediaType = ""
            var mediaURL = ""
            if let mediaItem = story["mediaItem"] as? [String: Any] {
                mediaType = mediaItem["type"] as? String ?? ""
                mediaURL = mediaItem["url"] as? String ?? ""
            }
            
            csvContent += "\"\(documentId)\",\"\(authorId)\",\"\(username)\",\"\(mediaType)\",\"\(mediaURL)\",\"\(timestamp)\",\"\(expirationDate)\",\(expirationHours),\(duration)\n"
        }
        
        let fileURL = directory.appendingPathComponent("stories.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createSocialListCSV(rows: [[String: Any]], filename: String, directory: URL) throws {
        var csvContent = "UserID,Timestamp\n"

        for row in rows {
            let userId = row["userId"] as? String ?? ""
            let timestamp = formatTimestamp(row["timestamp"])
            csvContent += "\"\(userId)\",\"\(timestamp)\"\n"
        }

        let fileURL = directory.appendingPathComponent(filename)
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func createConnectionsCSV(connections: [[String: Any]], directory: URL) throws {
        try createSocialListCSV(rows: connections, filename: "connections.csv", directory: directory)
    }
    
    private func createFollowersCSV(followers: [[String: Any]], directory: URL) throws {
        var csvContent = "UserID,Timestamp\n"
        
        for follower in followers {
            let userId = follower["userId"] as? String ?? ""
            let timestamp = formatTimestamp(follower["timestamp"])
            csvContent += "\"\(userId)\",\"\(timestamp)\"\n"
        }
        
        let fileURL = directory.appendingPathComponent("followers.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createConversationsCSV(conversations: [[String: Any]], directory: URL) throws {
        var csvContent = "ConversationID,Participants,LastMessage,MessageCount\n"
        
        for conversation in conversations {
            let conversationId = conversation["conversationId"] as? String ?? ""
            let participants = (conversation["participants"] as? [String] ?? []).joined(separator: ";")
            let messages = conversation["messages"] as? [[String: Any]] ?? []
            let messageCount = messages.count
            let lastMessage = messages.last?["content"] as? String ?? ""
            
            csvContent += "\"\(conversationId)\",\"\(participants)\",\"\(lastMessage.replacingOccurrences(of: "\"", with: "\"\""))\",\(messageCount)\n"
        }
        
        let fileURL = directory.appendingPathComponent("conversations.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createActivityStatsCSV(activityStats: [[String: Any]], directory: URL) throws {
        var csvContent = "Date,TimeSpent,InteractionCount,SessionCount\n"
        
        for stat in activityStats {
            let date = stat["date"] as? String ?? ""
            let timeSpent = stat["timeSpent"] as? Double ?? 0.0
            let interactionCount = stat["interactionCount"] as? Int ?? 0
            let sessionCount = stat["sessionCount"] as? Int ?? 0
            
            csvContent += "\"\(date)\",\(timeSpent),\(interactionCount),\(sessionCount)\n"
        }
        
        let fileURL = directory.appendingPathComponent("activity_stats.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createLoginActivityCSV(loginActivity: [[String: Any]], directory: URL) throws {
        var csvContent = "Timestamp,Device,Location,IPAddress,IsSuccessful,FailureReason\n"
        
        for activity in loginActivity {
            let timestamp = formatTimestamp(activity["timestamp"])
            let device = activity["device"] as? String ?? ""
            let location = activity["location"] as? String ?? ""
            let ipAddress = activity["ipAddress"] as? String ?? ""
            let isSuccessful = activity["isSuccessful"] as? Bool ?? false
            let failureReason = activity["failureReason"] as? String ?? ""
            
            csvContent += "\"\(timestamp)\",\"\(device)\",\"\(location)\",\"\(ipAddress)\",\(isSuccessful),\"\(failureReason)\"\n"
        }
        
        let fileURL = directory.appendingPathComponent("login_activity.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createMediaUrlsCSV(mediaUrls: [String], directory: URL) throws {
        var csvContent = "MediaURL,Type\n"
        
        for url in mediaUrls {
            let type = url.contains(".jpg") || url.contains(".png") || url.contains(".jpeg") ? "Image" :
                      url.contains(".mp4") || url.contains(".mov") ? "Video" : "Unknown"
            csvContent += "\"\(url)\",\"\(type)\"\n"
        }
        
        let fileURL = directory.appendingPathComponent("media_urls.csv")
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func createReadmeFile(directory: URL) throws {
        let readmeContent = """
        # Exportación de Datos de Moments
        
        Este archivo contiene todos tus datos exportados de la aplicación Moments.
        
        ## Archivos incluidos:
        
        - **profile.csv**: Información de tu perfil
        - **moments.csv**: Todas tus publicaciones
        - **stories.csv**: Tus historias
        - **following.csv**: Personas que sigues
        - **mutuals.csv**: Personas con las que tienes relación mutua
        - **followers.csv**: Personas que te siguen
        - **conversations.csv**: Resumen de tus conversaciones
        - **conversations/**: Conversaciones completas en JSON (mensajes y metadatos)
        - **activity_stats.csv**: Estadísticas de uso de la app
        - **login_activity.csv**: Historial de inicios de sesión
        - **media_urls.csv**: URLs de todos tus archivos multimedia
        - **media/**: Archivos multimedia descargados (si disponibles)
        
        ## Formato de fechas:
        Todas las fechas están en formato ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
        
        ## Privacidad:
        Este archivo contiene información personal. Manéjalo con cuidado.
        
        Exportado el: \(ISO8601DateFormatter().string(from: Date()))
        Versión: 1.0
        """
        
        let fileURL = directory.appendingPathComponent("README.txt")
        try readmeContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - iOS Compatible ZIP Creation
    private func createZIPWithFoundation(sourceDirectory: URL, destinationURL: URL) throws {
        let archive = try Archive(url: destinationURL, accessMode: .create)
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            
            let relativePath = fileURL.path.replacingOccurrences(of: sourceDirectory.path + "/", with: "")
            try archive.addEntry(with: relativePath, relativeTo: sourceDirectory, compressionMethod: .deflate)
        }
    }

    // MARK: - Detailed Conversations & Media Export
    private func createDetailedConversationsExport(conversations: [[String: Any]], directory: URL) throws {
        let conversationsDir = directory.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
        
        for originalConversation in conversations {
            var conversation = originalConversation
            let conversationId = (conversation["conversationId"] as? String) ?? UUID().uuidString

            // ✅ Conversaciones cifradas: exportamos SIEMPRE payload original
            // y, cuando este dispositivo tiene la clave, añadimos contentDecrypted.
            if var messages = conversation["messages"] as? [[String: Any]] {
                for index in messages.indices {
                    if let encryptedContent = messages[index]["content"] as? String,
                       !encryptedContent.isEmpty {
                        messages[index]["contentDecrypted"] = decryptMessageContentSync(
                            encryptedContent,
                            conversationId: conversationId
                        ) as Any
                    }
                }
                conversation["messages"] = messages
            }

            let safeId = sanitizeFileName(conversationId)
            let fileURL = conversationsDir.appendingPathComponent("\(safeId).json")
            
            let jsonData = try JSONSerialization.data(
                withJSONObject: makeJSONObjectSerializable(conversation),
                options: [.prettyPrinted]
            )
            try jsonData.write(to: fileURL)
        }
    }
    
    private func createDownloadedMediaExport(mediaUrls: [String], directory: URL) throws {
        guard !mediaUrls.isEmpty else { return }
        
        let mediaDir = directory.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        var index = 0
        for rawUrl in mediaUrls {
            guard let remoteURL = URL(string: rawUrl), !rawUrl.isEmpty else { continue }
            
            // Best effort: si falla una URL, seguimos con el resto.
            if let data = try? Data(contentsOf: remoteURL), !data.isEmpty {
                let ext = inferFileExtension(from: remoteURL, data: data)
                let fileName = String(format: "media_%04d.%@", index, ext)
                let destination = mediaDir.appendingPathComponent(fileName)
                try? data.write(to: destination)
                index += 1
            }
        }
    }
    
    private func collectAllMediaUrls(userData: UserExportData) -> [String] {
        var urls = Set(userData.mediaUrls ?? [])
        
        for conversation in userData.conversations ?? [] {
            let messages = conversation["messages"] as? [[String: Any]] ?? []
            for message in messages {
                if let mediaUrl = message["mediaUrl"] as? String, !mediaUrl.isEmpty {
                    urls.insert(mediaUrl)
                }
                if let thumbnailUrl = message["thumbnailUrl"] as? String, !thumbnailUrl.isEmpty {
                    urls.insert(thumbnailUrl)
                }
            }
        }
        
        return Array(urls)
    }
    
    private func makeJSONObjectSerializable(_ value: Any) -> Any {
        switch value {
        case let timestamp as Timestamp:
            return ISO8601DateFormatter().string(from: timestamp.dateValue())
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let dict as [String: Any]:
            var result: [String: Any] = [:]
            for (key, nestedValue) in dict {
                result[key] = makeJSONObjectSerializable(nestedValue)
            }
            return result
        case let array as [Any]:
            return array.map { makeJSONObjectSerializable($0) }
        default:
            return value
        }
    }
    
    private func sanitizeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return value.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func inferFileExtension(from url: URL, data: Data) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && ext.count <= 5 {
            return ext
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if data.starts(with: [0x00, 0x00, 0x00]) { return "mp4" }
        return "bin"
    }

    private func decryptMessageContentSync(_ encryptedContent: String, conversationId: String) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var decrypted: String?
        
        Task {
            decrypted = await EncryptionService.shared.decryptChatMessage(encryptedContent, for: conversationId)
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        return decrypted
    }
    
    private func formatTimestamp(_ timestamp: Any?) -> String {
        guard let timestamp = timestamp else { return "" }
        
        if let firebaseTimestamp = timestamp as? Timestamp {
            return ISO8601DateFormatter().string(from: firebaseTimestamp.dateValue())
        } else if let date = timestamp as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else if let string = timestamp as? String {
            return string
        }
        
        return ""
    }
    
    // MARK: - Request Management
    func updateExportRequestProgress(userId: String, requestId: String, progress: Double, status: String) {
        guard !userId.isEmpty else { return }
        db.collection("users").document(userId).collection("dataExportRequests").document(requestId)
            .updateData([
                "progress": progress,
                "status": status,
                "lastUpdated": Timestamp(date: Date())
            ])
    }
    
    func completeExportRequest(userId: String, requestId: String, downloadURL: String) {
        guard !userId.isEmpty else { return }
        db.collection("users").document(userId).collection("dataExportRequests").document(requestId)
            .updateData([
                "status": "ready",
                "progress": 1.0,
                "downloadURL": downloadURL,
                "completedAt": Timestamp(date: Date()),
                "expirationDate": Timestamp(date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
            ])
    }
    
    // MARK: - Cloud Storage Upload
    func uploadToCloudStorage(userId: String, fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard !userId.isEmpty else {
            completion(.failure(NSError(domain: "DataExportService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Usuario no válido"
            ])))
            return
        }

        let exportId = fileURL.deletingPathExtension().lastPathComponent
        let target = StoragePathBuilder.build(userId: userId, domain: .dataExport(exportId: exportId))
        let storageRef = Storage.storage().reference().child(target.objectPath)

        let metadata = StorageMetadata()
        metadata.contentType = target.contentType
        metadata.customMetadata = target.customMetadata

        storageRef.putFile(from: fileURL, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let absolute = url?.absoluteString, !absolute.isEmpty else {
                    completion(.failure(NSError(domain: "DataExportService", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "No se pudo obtener la URL de descarga"
                    ])))
                    return
                }

                completion(.success(absolute))
            }
        }
    }
}

// MARK: - Data Models
struct UserExportData {
    var profile: [String: Any]?
    var moments: [[String: Any]]?
    var stories: [[String: Any]]?
    var following: [[String: Any]]?
    var mutuals: [[String: Any]]?
    var followers: [[String: Any]]?
    var conversations: [[String: Any]]?
    var notifications: [[String: Any]]?
    var activityStats: [[String: Any]]?
    var loginActivity: [[String: Any]]?
    var savedMoments: [[String: Any]]?
    var visits: [[String: Any]]?
    var visitSummaries: [[String: Any]]?
    var mediaUrls: [String]?
}

// MARK: - Background Export Manager
class BackgroundExportManager: ObservableObject {
    static let shared = BackgroundExportManager()
    private let exportService = DataExportService()
    
    private init() {}
    
    func processExportRequest(requestId: String, userId: String, exportType: ExportType, format: ExportFormat) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            // Update status to processing
            self.exportService.updateExportRequestProgress(userId: userId, requestId: requestId, progress: 0.1, status: "processing")
            
            // Generate the export
            self.exportService.generateRealDataExport(userId: userId, exportType: exportType, format: format) { result in
                switch result {
                case .success(let fileURL):
                    // Update progress
                    self.exportService.updateExportRequestProgress(userId: userId, requestId: requestId, progress: 0.8, status: "uploading")
                    
                    // Upload to cloud storage
                    self.exportService.uploadToCloudStorage(userId: userId, fileURL: fileURL) { uploadResult in
                        switch uploadResult {
                        case .success(let downloadURL):
                            // Complete the request
                            self.exportService.completeExportRequest(userId: userId, requestId: requestId, downloadURL: downloadURL)
                            
                            // Send notification email (in production)
                            self.sendCompletionEmail(userId: userId, downloadURL: downloadURL)
                            
                        case .failure:
                            self.exportService.updateExportRequestProgress(userId: userId, requestId: requestId, progress: 0.0, status: "failed")
                        }
                    }
                    
                case .failure:
                    self.exportService.updateExportRequestProgress(userId: userId, requestId: requestId, progress: 0.0, status: "failed")
                }
            }
        }
    }
    
    private func sendCompletionEmail(userId: String, downloadURL: String) {
        // In production, this would trigger a Cloud Function to send an email
        
        // Create a notification in Firestore
        let notificationData: [String: Any] = [
            "type": "data_export_ready",
            // Sin texto fijo: el cliente muestra la cadena localizada según el idioma.
            "message": "",
            "downloadURL": downloadURL,
            "senderId": "system",
            "senderUsername": "Moments",
            "isPending": true,
            "timestamp": Timestamp(date: Date()),
            "isRead": false
        ]
        
        Firestore.firestore().collection("users").document(userId).collection("notifications")
            .addDocument(data: notificationData)
    }
}
