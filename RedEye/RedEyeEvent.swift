//
//  RedEyeEvent.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/9/25.
//

// RedEyeEvent.swift

import Foundation

// Enum to define the type of event
// Conforms to String for easier Codable representation if you want string values in JSON
// Conforms to Codable to be part of RedEyeEvent's Codable conformance
enum RedEyeEventType: String, Codable {
    case textSelection
    // Add other event types here later, e.g., fileSelection, screenshotTaken
}

struct RedEyeEvent: Codable {
    let id: UUID
    let timestamp: Date
    let eventType: RedEyeEventType
    let sourceApplicationName: String? // Making it optional in case we can't get it
    let sourceBundleIdentifier: String? // Making it optional for same reason
    let contextText: String? // Optional if no text is relevant or captured
    let metadata: [String: String]? // Optional for extra, non-standardized data

    // Custom initializer for convenience
    init(eventType: RedEyeEventType,
         sourceApplicationName: String? = nil,
         sourceBundleIdentifier: String? = nil,
         contextText: String? = nil,
         metadata: [String: String]? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.eventType = eventType
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.contextText = contextText
        self.metadata = metadata
    }
}
