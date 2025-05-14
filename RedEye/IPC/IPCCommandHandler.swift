// RedEye/IPC/IPCCommandHandler.swift (New File)

import Foundation

class IPCCommandHandler {

    private static let logCategory = "IPCCommandHandler"

    // The JSONDecoder can be kept here, similar to WebSocketServerManager
    private let jsonDecoder: JSONDecoder

    init() {
        self.jsonDecoder = JSONDecoder()
        // Configure decoder if needed (e.g., dateDecodingStrategy)
        RedEyeLogger.info("IPCCommandHandler initialized.", category: IPCCommandHandler.logCategory)
    }

    /// Public entry point to handle a raw command string received from an IPC client.
    /// - Parameters:
    ///   - commandString: The raw JSON string received from the client.
    ///   - clientID: The unique identifier of the client that sent the command. (Useful for logging & future stateful interactions)
    ///   - webSocket: The WebSocket connection object, if a direct response is needed. (Optional for now, can be added if handlers need to send immediate replies)
    public func handleRawCommand(_ commandString: String, from clientID: UUID /*, webSocket: WebSocket? = nil */) async {
        RedEyeLogger.debug("Received raw command string from client \(clientID): \(commandString)", category: IPCCommandHandler.logCategory)

        guard let commandData = commandString.data(using: .utf8) else {
            RedEyeLogger.error("Could not convert incoming command string to Data for client \(clientID). String: \(commandString)", category: IPCCommandHandler.logCategory)
            // TODO: Consider if/how to send an error response back to the client
            return
        }

        do {
            let receivedCommand = try self.jsonDecoder.decode(IPCReceivedCommand.self, from: commandData)
            RedEyeLogger.info("Successfully decoded command: \(receivedCommand.action) (ID: \(receivedCommand.commandId ?? "N/A")) from client \(clientID)", category: IPCCommandHandler.logCategory)
            
            // Route the decoded command
            await self.routeCommand(receivedCommand, fromClient: clientID)

        } catch {
            RedEyeLogger.error("Failed to decode IPC command from client \(clientID): \(error.localizedDescription)", category: IPCCommandHandler.logCategory, error: error)
            RedEyeLogger.debug("Problematic JSON string from client \(clientID): \(commandString)", category: IPCCommandHandler.logCategory)
            // TODO: Consider if/how to send an error response back to the client
        }
    }

    // This method will be moved from WebSocketServerManager
    private func routeCommand(_ command: IPCReceivedCommand, fromClient clientID: UUID) async {
        RedEyeLogger.info("Routing command '\(command.action)' (ID: \(command.commandId ?? "N/A")) from client \(clientID)", category: IPCCommandHandler.logCategory)

        guard let action = IPCAction(rawValue: command.action) else {
            RedEyeLogger.error("Unknown action '\(command.action)' received from client \(clientID).", category: IPCCommandHandler.logCategory)
            // TODO: Send error response
            return
        }

        switch action {
        case .logMessageFromServer:
            // This specific handler will also be moved here
            await handleLogMessageFromServer(payload: command.payload, clientID: clientID, commandId: command.commandId)
        // Add other cases here as more actions are defined
        }
    }

    // This method will be moved from WebSocketServerManager
    private func handleLogMessageFromServer(payload: [String: JSONValue]?, clientID: UUID, commandId: String?) async {
        RedEyeLogger.info("Handling 'logMessageFromServer' from client \(clientID)", category: IPCCommandHandler.logCategory)

        guard let payloadDict = payload else {
            RedEyeLogger.error("'logMessageFromServer' received without a payload from client \(clientID).", category: IPCCommandHandler.logCategory)
            // TODO: Send error response
            return
        }

        do {
            // Convert [String: JSONValue] payload back to JSON Data, then decode to specific struct
            let payloadData = try JSONSerialization.data(withJSONObject: payloadDict.mapValues { convertJSONValueToAny($0) })
            let logPayload = try self.jsonDecoder.decode(LogMessagePayload.self, from: payloadData)
            
            // Log with a specific category indicating it's from an IPC client message
            RedEyeLogger.info("Client \(clientID) says via IPC: \"\(logPayload.message)\"", category: "IPCClientMessage")
            
            // TODO: Optional: Send acknowledgement response
        } catch {
            RedEyeLogger.error("Failed to decode LogMessagePayload for 'logMessageFromServer' from client \(clientID): \(error.localizedDescription)", category: IPCCommandHandler.logCategory, error: error)
            RedEyeLogger.debug("Problematic payload for logMessageFromServer: \(payloadDict)", category: IPCCommandHandler.logCategory)
            // TODO: Send error response
        }
    }
    
    // This helper method will be moved from WebSocketServerManager (or could be a global utility)
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

    // TODO: Methods for sending ACK/NACK responses back via WebSocketServerManager if needed.
    // This would require IPCCommandHandler to have a way to talk back to WSSM,
    // perhaps via a delegate or closure passed during command handling.
    // For v0.3, sending responses is not a primary goal.
}
