// RedEye/IPC/IPCCommandHandler.swift (New File)

import Foundation
import os

class IPCCommandHandler: Loggable {
    var logCategoryForInstance: String { return "IPCCommandHandler" }
    var instanceLogger: Logger { Logger(subsystem: RedEyeLogger.subsystem, category: self.logCategoryForInstance) }

    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    private weak var configManager: ConfigurationManaging?

    init(configManager: ConfigurationManaging) {
        self.configManager = configManager
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder() // Initialize encoder
        self.jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Consistent with ConfigManager
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        info("IPCCommandHandler initialized with ConfigurationManager.")
    }

    /// Public entry point to handle a raw command string received from an IPC client.
    /// For ACK/NACK and data responses, the handler needs to produce a string to send back.
    /// The actual sending is done by WebSocketServerManager.
    /// - Parameters:
    ///   - commandString: The raw JSON string received from the client.
    ///   - clientID: The unique identifier of the client that sent the command. (Useful for logging & future stateful interactions)
    ///   - webSocket: The WebSocket connection object, if a direct response is needed. (Optional for now, can be added if handlers need to send immediate replies)
    public func handleRawCommand(_ commandString: String, from clientID: UUID) async -> String? {
        debug("Handling raw command from client \(clientID): \(commandString)")

        guard let configManager = self.configManager else {
            error("ConfigurationManager not available in IPCCommandHandler. Cannot process config commands.")
            return createErrorResponse(message: "Internal Server Error: Configuration service unavailable.", commandId: nil)
        }

        guard let commandData = commandString.data(using: .utf8) else {
            error("Could not convert command string to Data. Client: \(clientID)")
            return createErrorResponse(message: "Invalid command format: Not valid UTF-8.", commandId: nil)
        }

        let receivedCommand: IPCReceivedCommand
        do {
            receivedCommand = try self.jsonDecoder.decode(IPCReceivedCommand.self, from: commandData)
        } catch {
            self.error("Failed to decode IPC command from client \(clientID): \(error.localizedDescription)", error: error)
            return createErrorResponse(message: "Command decoding failed: \(error.localizedDescription)", commandId: nil)
        }
        
        info("Routing command '\(receivedCommand.action)' (ID: \(receivedCommand.commandId ?? "N/A")) from client \(clientID)")

        guard let action = IPCAction(rawValue: receivedCommand.action) else {
            error("Unknown action '\(receivedCommand.action)' from client \(clientID).")
            return createErrorResponse(message: "Unknown action: \(receivedCommand.action)", commandId: receivedCommand.commandId)
        }

        // Route to specific handlers
        do {
            switch action {
            case .logMessageFromServer:
                try await handleLogMessageFromServer(payload: receivedCommand.payload, clientID: clientID)
                return createAckResponse(commandId: receivedCommand.commandId, message: "Log message processed.")
            
            // Configuration Getters
            case .getConfig:
                let config = configManager.getCurrentConfig()
                return try createDataResponse(data: config, commandId: receivedCommand.commandId)
            case .getMonitorSettings:
                let settings = configManager.getCurrentConfig().monitorSettings // Or a dedicated method
                return try createDataResponse(data: settings, commandId: receivedCommand.commandId)
            case .getMonitorSetting:
                let payload = try decodePayload(MonitorTypePayload.self, from: receivedCommand.payload, action: action)
                guard let monitorType = MonitorType(rawValue: payload.monitorType) else {
                    throw IPCError.invalidPayload("Unknown monitorType: \(payload.monitorType)")
                }
                let setting = configManager.getMonitorSetting(for: monitorType)
                return try createDataResponse(data: setting, commandId: receivedCommand.commandId)
            case .getGeneralSettings:
                let settings = configManager.getGeneralSettings()
                return try createDataResponse(data: settings, commandId: receivedCommand.commandId)
            case .getCapabilities: // << MODIFIED: useRawDict is no longer needed
                let caps = configManager.getCapabilities() // Now returns [String: JSONValue]
                return try createDataResponse(data: caps, commandId: receivedCommand.commandId)
            case .getMonitorParameters:
                let payload = try decodePayload(MonitorTypePayload.self, from: receivedCommand.payload, action: action)
                guard let monitorType = MonitorType(rawValue: payload.monitorType) else {
                    throw IPCError.invalidPayload("Unknown monitorType: \(payload.monitorType)")
                }
                let params = configManager.getMonitorSetting(for: monitorType)?.parameters
                return try createDataResponse(data: params, commandId: receivedCommand.commandId)

            // Configuration Setters
            case .setMonitorEnabled:
                let payload = try decodePayload(SetMonitorEnabledPayload.self, from: receivedCommand.payload, action: action)
                guard let monitorType = MonitorType(rawValue: payload.monitorType) else {
                    throw IPCError.invalidPayload("Unknown monitorType: \(payload.monitorType)")
                }
                try configManager.setMonitorEnabled(type: monitorType, isEnabled: payload.isEnabled)
                return createAckResponse(commandId: receivedCommand.commandId, message: "Monitor '\(monitorType.rawValue)' enabled state set to \(payload.isEnabled).")
            
            case .setMonitorParameters:
                let payload = try decodePayload(SetMonitorParametersPayload.self, from: receivedCommand.payload, action: action)
                guard let monitorType = MonitorType(rawValue: payload.monitorType) else {
                    throw IPCError.invalidPayload("Unknown monitorType: \(payload.monitorType)")
                }
                try configManager.setMonitorParameters(type: monitorType, parameters: payload.parameters)
                return createAckResponse(commandId: receivedCommand.commandId, message: "Parameters for monitor '\(monitorType.rawValue)' set.")

            case .setGeneralSettings:
                let payload = try decodePayload(GeneralAppSettings.self, from: receivedCommand.payload, action: action)
                try configManager.updateGeneralSettings(newSettings: payload)
                return createAckResponse(commandId: receivedCommand.commandId, message: "General settings updated.")

            case .resetConfigToDefaults:
                try configManager.resetToDefaults()
                return createAckResponse(commandId: receivedCommand.commandId, message: "Configuration reset to defaults.")
            }
        } catch let error as IPCError {
            self.error("IPCError handling action \(action.rawValue): \(error.localizedDescription)", error: error)
            return createErrorResponse(message: error.localizedDescription, commandId: receivedCommand.commandId)
        } catch {
            self.error("Unexpected error handling action \(action.rawValue): \(error.localizedDescription)", error: error)
            return createErrorResponse(message: "Unexpected error: \(error.localizedDescription)", commandId: receivedCommand.commandId)
        }
    }

    // MARK: - Specific Command Handlers

    private func handleLogMessageFromServer(payload: [String: JSONValue]?, clientID: UUID) async throws {
        let logPayload = try decodePayload(LogMessagePayload.self, from: payload, action: .logMessageFromServer)
        info("Client \(clientID) says via IPC: \"\(logPayload.message)\"")
    }

    // MARK: - Helper Methods for Decoding and Response Creation

    private func decodePayload<T: Decodable>(_ type: T.Type, from payloadDict: [String: JSONValue]?, action: IPCAction) throws -> T {
        guard let dict = payloadDict else {
            throw IPCError.missingPayload("Payload missing for action: \(action.rawValue)")
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict.mapValues { convertJSONValueToAny($0) })
            return try jsonDecoder.decode(T.self, from: jsonData)
        } catch {
            self.error("Failed to decode \(String(describing: T.self)) for \(action.rawValue): \(error.localizedDescription)", error: error)
            throw IPCError.invalidPayload("Payload for \(action.rawValue) could not be decoded: \(error.localizedDescription)")
        }
    }

    private func createAckResponse(commandId: String?, message: String) -> String? {
        let response = IPCResponseWrapper(commandId: commandId, status: "success", message: message, data: nil as String?)
        return encodeResponse(response)
    }

    private func createErrorResponse(message: String, commandId: String?) -> String? {
        let response = IPCResponseWrapper(commandId: commandId, status: "error", message: message, data: nil as String?)
        return encodeResponse(response)
    }

    private func createDataResponse<T: Encodable>(data: T, commandId: String?) throws -> String? {
        let response = IPCResponseWrapper(commandId: commandId, status: "success", message: nil, data: data) // T must be Encodable
        return encodeResponse(response)
    }

    private func encodeResponse<T: Encodable>(_ responseWrapper: IPCResponseWrapper<T>) -> String? {
        do {
            let jsonData = try jsonEncoder.encode(responseWrapper)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            self.error("Failed to encode IPC response: \(error.localizedDescription)", error: error)
            // Fallback error response if encoding the main response fails
            let fallback = IPCResponseWrapper(commandId: responseWrapper.commandId, status: "error", message: "Internal server error: Failed to encode response.", data: nil as String?)
            return String(data: try! jsonEncoder.encode(fallback), encoding: .utf8) // Should not fail
        }
    }
    
    private func convertJSONValueToAny(_ jsonValue: JSONValue) -> Any {
        switch jsonValue {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { convertJSONValueToAny($0) }
        case .dictionary(let dict): return dict.mapValues { convertJSONValueToAny($0) }
        case .null: return NSNull()
        }
    }
}

// MARK: - IPC Error Enum and Response Wrapper

enum IPCError: Error, LocalizedError {
    case missingPayload(String)
    case invalidPayload(String)
    // Add other IPC specific errors if needed

    var errorDescription: String? {
        switch self {
        case .missingPayload(let msg): return "Missing payload: \(msg)"
        case .invalidPayload(let msg): return "Invalid payload: \(msg)"
        }
    }
}

// Generic wrapper for IPC responses to ensure consistent structure (status, data, message, commandId)
struct IPCResponseWrapper<T: Encodable>: Encodable {
    let commandId: String?
    let status: String // "success" or "error"
    let message: String? // Optional human-readable message, especially for errors or simple ACKs
    let data: T?     // The actual data payload for the response
}
