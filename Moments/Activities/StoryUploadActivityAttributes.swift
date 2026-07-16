//
//  StoryUploadActivityAttributes.swift
//  Moments
//
//  Tipos compartidos para Live Activities de historias
//  Estos tipos deben coincidir exactamente con los del Widget Extension
//

import Foundation
import ActivityKit

// MARK: - Story Upload Activity Attributes
// Estos tipos deben ser idénticos a los del Widget Extension
public struct StoryUploadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var progress: Double
        public var status: String // "uploading", "processing", "completed", "failed"
        public var percentage: Int {
            Int(progress * 100)
        }
        
        public init(progress: Double, status: String) {
            self.progress = progress
            self.status = status
        }
    }
    
    public var storyId: String
    public var mediaType: String // "image" o "video"
    public var previewImageFileName: String? // nombre de fichero dentro del App Group, para mostrar miniatura real

    public init(storyId: String, mediaType: String, previewImageFileName: String? = nil) {
        self.storyId = storyId
        self.mediaType = mediaType
        self.previewImageFileName = previewImageFileName
    }
}
