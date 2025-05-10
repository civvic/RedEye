//
//  EventManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/9/25.
//

import Foundation

class EventManager {

    private let jsonEncoder: JSONEncoder
    // private let pluginManager: PluginManager // We can remove this if UIManager handles all invocations

    // init(pluginManager: PluginManager) { // Adjust init if pluginManager is removed
    init() { // Simplified init
        // self.pluginManager = pluginManager
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    func emit(event: RedEyeEvent) {
        // 1. Log the event as JSON (as before)
        do {
            let jsonData = try jsonEncoder.encode(event)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                RedEyeLogger.info("--- RedEyeEvent Emitted ---", category: "EventManager")
                RedEyeLogger.info(jsonString, category: "EventManager")
                RedEyeLogger.info("---------------------------", category: "EventManager")
            } else {
                RedEyeLogger.error("Could not convert JSON data to string.", category: "EventManager")
            }
        } catch {
            RedEyeLogger.error("Failed to encode RedEyeEvent to JSON", category: "EventManager", error:error)
        }

        // 2. For now, EventManager only logs. Plugin invocation is handled by UIManager via UI.
        // if event.eventType == .textSelection {
        //     if let textToProcess = event.contextText, !textToProcess.isEmpty {
        //         // print("EventManager: (Old logic) Passing text to PluginManager: \"\(textToProcess)\"")
        //         // pluginManager.invokePlugins(withText: textToProcess)
        //     }
        // }
    }
}
