// RedEye/IPC/IPCCommand.swift

import Foundation

// Generic structure for any command received from the client
struct IPCReceivedCommand: Codable {
    let commandId: String? // Optional: Client might not always send one
    let action: String     // Mandatory: Identifies the action to perform
    let payload: [String: JSONValue]? // Flexible payload, using a helper for JSON values
}

// Enum to represent known actions (we'll add to this)
enum IPCAction: String, Codable {
    case logMessageFromServer = "logMessageFromServer"
    
    // Configuration Actions (v0.4)
    case getConfig = "getConfig" // Get the entire current RedEyeConfig object
    case getMonitorSettings = "getMonitorSettings" // Get settings for all monitors
    case getMonitorSetting = "getMonitorSetting"   // Get settings for a specific monitor (payload: { "monitorType": "..." })
    case setMonitorEnabled = "setMonitorEnabled"   // Payload: { "monitorType": "...", "isEnabled": true/false }
    case getMonitorParameters = "getMonitorParameters" // Payload: { "monitorType": "..." }
    case setMonitorParameters = "setMonitorParameters"   // Payload: { "monitorType": "...", "parameters": { ... } }
    
    case getGeneralSettings = "getGeneralSettings"
    case setGeneralSettings = "setGeneralSettings"   // Payload: { generalSettings object }

    case getCapabilities = "getCapabilities"
    case resetConfigToDefaults = "resetConfigToDefaults"
    
    // Future/More Granular:
    // case setConfigValue = "setConfigValue" // For setting a specific deep path in config
}

// Example payload for the "logMessageFromServer" action
struct LogMessagePayload: Codable {
    let message: String
    // let level: String? // Optional: e.g., "info", "debug", "error"
}

// MARK: - Payload Structures for Configuration Actions

struct MonitorTypePayload: Codable {
    let monitorType: String // e.g., "keyboardMonitorManager" (MonitorType.rawValue)
}

struct SetMonitorEnabledPayload: Codable {
    let monitorType: String
    let isEnabled: Bool
}

struct SetMonitorParametersPayload: Codable {
    let monitorType: String
    let parameters: [String: JSONValue]? // Using JSONValue for flexibility
}

// For setGeneralSettings, the payload would directly be the GeneralAppSettings struct.
// For getConfig, getMonitorSettings, getGeneralSettings, getCapabilities, resetConfigToDefaults: No specific request payload struct needed,
// but their responses will be structured (e.g., RedEyeConfig, [MonitorSpecificConfig], etc.).

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
    
    func boolValue() -> Bool? {
        if case .bool(let b) = self { return b }
        // Optional: Add interpretation for strings or numbers if needed
        // if case .string(let s) = self { return Bool(s.lowercased()) } // "true" -> true
        // if case .int(let i) = self { return i != 0 }
        return nil
    }
    
    func arrayValue() -> [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    
    func intValue() -> Int? {
        if case .int(let i) = self { return i }
        // Optional: could try to parse from string if case .string(let s) = self { return Int(s) }
        return nil
    }
}
