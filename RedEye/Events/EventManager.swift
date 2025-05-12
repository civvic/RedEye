//
//  EventManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/9/25.
//

import Foundation

class EventManager: FSEventMonitorDelegate { // <-- Adopt the protocol
    private let jsonEncoder: JSONEncoder
    private weak var webSocketServerManager: WebSocketServerManager? // Make it weak to avoid retain cycles if WSSM might ever hold EventManager

    init(webSocketServerManager: WebSocketServerManager?) { // Allow optional for flexibility, though we'll pass it
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        self.webSocketServerManager = webSocketServerManager
    }

    func emit(event: RedEyeEvent) {
        // 1. Log the event as JSON (as before)
        do {
            let jsonData = try jsonEncoder.encode(event)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                RedEyeLogger.info("--- RedEyeEvent Emitted (Logged) ---", category: "EventManager")
                RedEyeLogger.info(jsonString, category: "EventManager") // This is the local log
                RedEyeLogger.info("------------------------------------", category: "EventManager")
            } else {
                RedEyeLogger.error("Could not convert JSON data to string for local logging.", category: "EventManager")
            }
        } catch {
            RedEyeLogger.error("Failed to encode RedEyeEvent to JSON for local logging", category: "EventManager", error:error)
        }

        // 2. Broadcast the event via WebSocketServerManager
        if let manager = webSocketServerManager {
            RedEyeLogger.debug("EventManager: Asking WebSocketServerManager to broadcast event.", category: "EventManager")
            manager.broadcastEvent(event)
        } else {
            RedEyeLogger.debug("EventManager: WebSocketServerManager not available. Event not broadcasted.", category: "EventManager")
        }
    }
    
    // MARK: - FSEventMonitorDelegate
    
    func fsEventMonitor(_ monitor: FSEventMonitorManager, didEmit event: RedEyeEvent) {
        RedEyeLogger.info("EventManager received event from FSEventMonitor.", category: "EventManager")
        // Simply pass the received event to the main emit flow
        emit(event: event)
    }

}
