import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit


// MARK: - Enhanced MomentsChatViewModel with Better Audio Deletion
class MomentsChatViewModel: EnhancedChatViewModel {
    @Published var groupedMessages: [(Date, [EnhancedMessage])] = []
    @Published private(set) var chatRenderRows: [ChatRenderRow] = []
    @Published var messagesSentThisSession: Int = 0

    override init(conversation: Conversation) {
        super.init(conversation: conversation)
    }

    func syncMessagePresentation() {
        let calendar = Calendar.current
        let sortedMessages = messages.sorted {
            MessageSyncCursor(timestamp: $0.timestamp, messageId: $0.id)
                < MessageSyncCursor(timestamp: $1.timestamp, messageId: $1.id)
        }

        var grouped: [(Date, [EnhancedMessage])] = []
        var rows: [ChatRenderRow] = []
        var currentDay: Date?
        var dayBucket: [EnhancedMessage] = []

        func flushDay() {
            guard let day = currentDay, !dayBucket.isEmpty else { return }
            grouped.append((day, dayBucket))
            rows.append(.header(day))
            for item in ClusterMessageGrouper.group(dayBucket) {
                rows.append(.message(item))
            }
        }

        for message in sortedMessages {
            let day = calendar.startOfDay(for: message.timestamp)
            if day != currentDay {
                flushDay()
                currentDay = day
                dayBucket = []
            }
            dayBucket.append(message)
        }
        flushDay()

        groupedMessages = grouped
        chatRenderRows = rows
    }

    func updateGroupedMessages() {
        syncMessagePresentation()
    }

    override func sendTextMessage(_ content: String, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "Invalid conversation ID when sending text")
            return
        }

        // Track antes de enviar

        messagesSentThisSession += 1

        // ✅ USAR el método de la clase padre que maneja mensajes temporales
        super.sendTextMessage(content, replyTo: replyTo)
    }

    func trackMediaMessageSent(type: String) {
        messagesSentThisSession += 1
    }

    override func sendVideoMessage(data: Data) {
        trackMediaMessageSent(type: "video")
        super.sendVideoMessage(data: data)
    }
}
