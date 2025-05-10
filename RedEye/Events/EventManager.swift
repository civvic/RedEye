//
//  EventManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/9/25.
//

import Foundation

class EventManager {

    private let jsonEncoder: JSONEncoder
    private let pluginManager: PluginManager // Add property for PluginManager

    // Modify init to accept a PluginManager
    init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager // Store the PluginManager
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    func emit(event: RedEyeEvent) {
        // 1. Log the event as JSON (as before)
        do {
            let jsonData = try jsonEncoder.encode(event)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("--- RedEyeEvent Emitted ---")
                print(jsonString)
                print("---------------------------")
            } else {
                print("EventManager Error: Could not convert JSON data to string.")
            }
        } catch {
            print("EventManager Error: Failed to encode RedEyeEvent to JSON: \(error.localizedDescription)")
        }

        // 2. If it's a text selection event and there's text, invoke plugins
        //    For now, we only care about the contextText for the echo plugin.
        //    Later, we might pass the full JSON string of the event to plugins.
        if event.eventType == .textSelection {
            if let textToProcess = event.contextText, !textToProcess.isEmpty {
                print("EventManager: Passing text to PluginManager: \"\(textToProcess)\"")
                pluginManager.invokePlugins(withText: textToProcess)
            } else {
                // If there's no contextText, we might still notify plugins,
                // but our current echo_plugin.sh expects some input.
                // For now, we'll only invoke if there's text.
                print("EventManager: No contextText in textSelection event to pass to plugins.")
            }
        }
        // Add logic here for other event types and how they might trigger plugins
    }
}
