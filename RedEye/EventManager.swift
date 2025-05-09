//
//  EventManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/9/25.
//

// EventManager.swift

import Foundation

class EventManager {

    private let jsonEncoder: JSONEncoder

    init() {
        self.jsonEncoder = JSONEncoder()
        // Configure the encoder for readability
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.jsonEncoder.dateEncodingStrategy = .iso8601 // Standard date format
    }

    func emit(event: RedEyeEvent) {
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
            // For more detailed error, you could print the `error` object itself.
        }
    }
}
