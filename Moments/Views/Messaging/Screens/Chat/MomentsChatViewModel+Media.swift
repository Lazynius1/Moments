import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

extension MomentsChatViewModel {
    // MARK: - New Media Message Functions
    func sendImageMessage(_ imageData: Data, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "Invalid conversation ID when sending image")
            return
        }

        trackMediaMessageSent(type: "image")

        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(
            data: imageData,
            conversationId: conversationId,
            messageId: messageId,
            fileExtension: "jpg"
        )
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaUrl: localPreview,
            status: .sending,
            replyTo: replyTo,
            isVanishModeMessage: outgoingVanishMessageFlag
        )

        appendOutgoingMessage(tempMessage)

        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish,
            replyTo: replyTo
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.finalizeOutgoingMediaMessage(
                        messageId: messageId,
                        sentMessage: sentMessage,
                        fallbackMediaUrl: localPreview
                    )
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendImage", comment: "Image send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func sendAudioMessage(
        _ audioData: Data,
        duration: TimeInterval,
        waveform: [Float]? = nil
    ) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.audio", comment: "Invalid conversation ID when sending audio")
            return
        }

        trackMediaMessageSent(type: "audio")

        // ✅ Crear mensaje local inmediatamente para feedback visual (preview local como imágenes)
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(
            data: audioData,
            conversationId: conversationId,
            messageId: messageId,
            fileExtension: "m4a"
        )
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            content: nil,
            mediaUrl: localPreview,
            thumbnailUrl: nil,
            duration: duration,
            audioWaveform: waveform,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )

        appendOutgoingMessage(tempMessage, playsSentSound: false)

        chatService.sendAudioMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            audioData: audioData,
            duration: duration,
            waveform: waveform,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.finalizeOutgoingMediaMessage(
                        messageId: messageId,
                        sentMessage: sentMessage,
                        fallbackMediaUrl: localPreview
                    )
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendAudio", comment: "Audio send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // ✅ NUEVA función para enviar mensajes view-once
    func sendViewOnceMessage(
        data: Data,
        mediaType: EnhancedCameraPickerView.MediaType,
        allowReplay: Bool = false,
        replyTo: String? = nil,
        overlayPayload: ChatMediaOverlayPayload? = nil
    ) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.viewOnce", comment: "Invalid conversation ID when sending view-once message")
            return
        }

        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let messageType: MessageType = mediaType == .image ? .viewOnceImage : .viewOnceVideo

        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: messageType,
            status: .sending,
            replyTo: replyTo,
            isViewed: false,
            mediaBatchId: nil,
            textOverlayLive: overlayPayload?.textOverlayLive,
            textOverlays: overlayPayload?.textOverlays,
            stickers: overlayPayload?.stickers,
            drawingData: overlayPayload?.drawingData,
            isVanishModeMessage: outgoingVanishMessageFlag
        )
        tempMessage.allowReplay = allowReplay ? true : nil

        appendOutgoingMessage(tempMessage)

        chatService.sendViewOnceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            mediaData: data,
            mediaType: mediaType,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish,
            allowReplay: allowReplay,
            replyTo: replyTo,
            overlayPayload: overlayPayload
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendMessage", comment: "Message send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }

        messagesSentThisSession += 1
    }

    // MARK: - GIF / Sticker

    /// Envía un GIF de Giphy por referencia (URL pública, sin cifrado ni re-subida).
    func sendGif(from asset: ChatGiphyAsset) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "")
            return
        }

        trackMediaMessageSent(type: "gif")
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .gif,
            mediaUrl: asset.url,
            mediaWidth: asset.width > 0 ? asset.width : nil,
            mediaHeight: asset.height > 0 ? asset.height : nil,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )
        appendOutgoingMessage(tempMessage)

        chatService.sendGiphyReferenceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .gif,
            giphyId: asset.id,
            mediaUrl: asset.url,
            width: asset.width,
            height: asset.height,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? asset.url,
                        thumbnailUrl: nil
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    /// Envía un sticker de Giphy por referencia (URL pública, sin cifrado ni re-subida).
    func sendSticker(from asset: ChatStickerAsset) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "")
            return
        }

        ChatRecentStickersStore.add(asset)
        trackMediaMessageSent(type: "sticker")
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .sticker,
            mediaUrl: asset.url,
            mediaWidth: asset.width > 0 ? asset.width : nil,
            mediaHeight: asset.height > 0 ? asset.height : nil,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )
        appendOutgoingMessage(tempMessage)

        chatService.sendGiphyReferenceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .sticker,
            giphyId: asset.id,
            mediaUrl: asset.url,
            width: asset.width,
            height: asset.height,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? asset.url,
                        thumbnailUrl: nil
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // MARK: - Ubicación fija

    func sendStaticLocation(coordinate: CLLocationCoordinate2D, name: String?, address: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "")
            return
        }
        trackMediaMessageSent(type: "location")

        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationName: name,
            locationAddress: address,
            isLiveLocation: false,
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )
        appendOutgoingMessage(tempMessage)

        ChatService.shared.sendStaticLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            address: address,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // MARK: - Ubicación en vivo

    func startLiveLocation(duration: LiveLocationDuration) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "")
            return
        }
        guard let location = LocationUtilities.shared.currentLocation else {
            // Sin ubicación todavía: solicitar permiso y avisar.
            LocationUtilities.shared.requestLocationPermission()
            error = NSLocalizedString("chat.location.permissionNeeded", comment: "")
            return
        }

        trackMediaMessageSent(type: "liveLocation")

        let coordinate = location.coordinate
        let messageId = UUID().uuidString
        let sessionId = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(duration.timeInterval)

        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isLiveLocation: true,
            liveLocationExpiresAt: expiresAt,
            liveLocationDuration: duration.firestoreValue,
            liveLocationSessionId: sessionId,
            locationUpdatedAt: Date(),
            status: .sending,
            isVanishModeMessage: outgoingVanishMessageFlag
        )
        appendOutgoingMessage(tempMessage)

        ChatService.shared.sendLiveLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: nil,
            address: nil,
            duration: duration,
            sessionId: sessionId,
            expiresAt: expiresAt,
            messageId: messageId,
            isVanishModeMessage: marksOutgoingAsVanish
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    LiveLocationSharingService.shared.startSession(
                        conversationId: conversationId,
                        messageId: messageId,
                        sessionId: sessionId,
                        duration: duration,
                        expiresAt: expiresAt
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func stopLiveLocation(messageId: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        LiveLocationSharingService.shared.stopSharing(
            messageId: messageId,
            conversationId: conversationId
        )
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].liveLocationStoppedAt = Date()
            updateGroupedMessages()
            objectWillChange.send()
        }
    }
}
