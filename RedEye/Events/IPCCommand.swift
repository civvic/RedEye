//
//  IPCCommand.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/11/25.
//

import Foundation

// Generic structure for any command received from the client
struct IPCReceivedCommand: Codable {
    let commandId: String? // Optional: Client might not always send one
    let action: String     // Mandatory: Identifies the action to perform
    let payload: [String: JSONValue]? // Flexible payload, using a helper for JSON values
}

// Enum to represent known actions (we'll add to this)
enum IPCAction: String {
    case logMessageFromServer = "logMessageFromServer"
    // Future actions:
    // case requestTextManipulation = "requestTextManipulation"
    // case getSelectedText = "getSelectedText"
    // ... etc.
}

// MARK: - Payload Structures (Examples for specific actions)

// Example payload for the "logMessageFromServer" action
struct LogMessagePayload: Codable {
    let message: String
    // let level: String? // Optional: e.g., "info", "debug", "error"
}

// Helper to allow for flexible JSON types in the payload,
// as [String: AnyDecodable] can be tricky with JSONEncoder/Decoder directly
// if not handled carefully. A simpler [String: JSONValue] can work well.

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null // Explicit null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let dictionary = try? container.decode([String: JSONValue].self) {
            self = .dictionary(dictionary)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .bool(let bool):
            try container.encode(bool)
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dictionary):
            try container.encode(dictionary)
        case .null:
            try container.encodeNil()
        }
    }
    
    // Convenience accessor for string values from the payload
    func stringValue() -> String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
