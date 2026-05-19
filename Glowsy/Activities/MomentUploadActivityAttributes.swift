//
//  MomentUploadActivityAttributes.swift
//  Glowsy
//
//  Tipos compartidos para Live Activities de momentos
//  Estos tipos deben coincidir exactamente con los del Widget Extension
//

import Foundation
import ActivityKit

// MARK: - Moment Upload Activity Attributes
// Estos tipos deben ser idénticos a los del Widget Extension
public struct MomentUploadActivityAttributes: ActivityAttributes {
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
    
    public var momentId: String
    public var mediaType: String // "image", "video", o "mixed"
    public var mediaCount: Int
    
    public init(momentId: String, mediaType: String, mediaCount: Int) {
        self.momentId = momentId
        self.mediaType = mediaType
        self.mediaCount = mediaCount
    }
}
