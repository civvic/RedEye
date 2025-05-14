// RedEye/Managers/WebSocketServerManager.swift

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import WebSocketKit

// Make WebSocketServerManager conform to EventBusSubscriber <<< NEW
class WebSocketServerManager: EventBusSubscriber {

    private static let logCategory = "WebSocketServerManager"
    
    private let port: Int = 8765
    private var serverChannel: Channel?
    private var group: EventLoopGroup?
    private var connectedClients: [UUID: WebSocket] = [:]
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    private weak var eventBus: EventBus?
    private var isSubscribedToBus: Bool = false

    init(eventBus: EventBus) {
        self.eventBus = eventBus
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount) // Use System.coreCount
        self.jsonEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys] // More compact for network
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }()
        self.jsonDecoder = {
            let decoder = JSONDecoder()
            return decoder
        }()
        RedEyeLogger.info("WebSocketServerManager initialized.", category: WebSocketServerManager.logCategory)
    }

    func startServer() {
        guard let group = self.group else {
            RedEyeLogger.error("EventLoopGroup not initialized.", category: "WebSocketServerManager")
            return
        }
        
        // Subscribe to the event bus if not already
        if let bus = self.eventBus, !isSubscribedToBus {
            bus.subscribe(self)
            isSubscribedToBus = true
            RedEyeLogger.info("WebSocketServerManager subscribed to EventBus.", category: WebSocketServerManager.logCategory)
        }

        // This is the pattern from WebSocketKitTests/Utilities.swift, inlined:
        let webSocketUpgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 14, // Default max frame size
            automaticErrorHandling: true, // Recommended by NIO
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<HTTPHeaders?> in
                RedEyeLogger.debug("WebSocket upgrade request for URI: \(head.uri)", category: "WebSocketServerManager")
                // For RedEye, we accept all WebSocket upgrade requests on our specific port.
                return channel.eventLoop.makeSucceededFuture([:]) // Empty headers, accept upgrade
            },
            upgradePipelineHandler: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<Void> in
                // This closure is called after the WebSocket handshake is successful.
                // It's responsible for configuring the pipeline for WebSocket frames.
                // We use WebSocketKit's WebSocket.server here.
                RedEyeLogger.info("WebSocket client HTTP handshake successful for URI: \(head.uri). Setting up WebSocket handlers.", category: "WebSocketServerManager")
                
                // WebSocket.server(on: channel, onUpgrade: callback)
                // The onUpgrade callback receives the WebSocketKit.WebSocket object.
                return WebSocket.server(on: channel) { [weak self] ws in // ws is WebSocketKit.WebSocket
                    guard let self = self else {
                        _ = ws.close(code: .unexpectedServerError)
                        return
                    }
                    self.handleNewClient(webSocket: ws, requestHead: head)
                }
            }
        )

        // Now setup the ServerBootstrap
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // Configure the HTTP server pipeline with the WebSocket upgrader.
                return channel.pipeline.configureHTTPServerPipeline(
                    withPipeliningAssistance: false, // Standard for WebSocket upgrades
                    withServerUpgrade: (
                        upgraders: [webSocketUpgrader], // Pass the NIOWebSocketServerUpgrader instance
                        completionHandler: { ctx in
                            // This is called after the upgrade is completed and HTTP handlers
                            // (that are no longer needed) are removed from the pipeline.
                            RedEyeLogger.debug("HTTP server pipeline upgrade processing fully completed for a client.", category: "WebSocketServerManager")
                        }
                    )
                )
            }

        do {
            let channel = try bootstrap.bind(host: "localhost", port: self.port).wait()
            self.serverChannel = channel
            RedEyeLogger.info("WebSocket server started and listening on ws://localhost:\(self.port)", category: "WebSocketServerManager")
        } catch {
            RedEyeLogger.error("Failed to start WebSocket server: \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
            stopServerCleanup()
        }
    }
    
    private func handleNewClient(webSocket: WebSocket, requestHead: HTTPRequestHead) {
        let clientID = UUID()
        RedEyeLogger.info("WebSocket client connected: \(clientID) from URI: \(requestHead.uri)", category: "WebSocketServerManager")
        self.connectedClients[clientID] = webSocket

        webSocket.onText { [weak self] ws, text in
            guard let self = self else { return } // 'self' is WebSocketServerManager here

            RedEyeLogger.debug("Received text from client \(clientID): \(text)", category: "WebSocketServerManager")

            guard let commandData = text.data(using: .utf8) else {
                RedEyeLogger.error("Could not convert incoming text to Data for client \(clientID). Text: \(text)", category: "WebSocketServerManager")
                // Optionally, send an error response back to the client
                // ws.send("Error: Invalid UTF-8 in command.")
                return
            }

            do {
                let receivedCommand = try self.jsonDecoder.decode(IPCReceivedCommand.self, from: commandData)
                RedEyeLogger.info("Successfully decoded command: \(receivedCommand.action) from client \(clientID)", category: "WebSocketServerManager")
                
                // Offload actual command processing to avoid blocking the EventLoop
                Task { // Create a new Task for concurrent execution
                    await self.routeCommand(receivedCommand, fromClient: clientID, webSocket: ws)
                }

            } catch {
                RedEyeLogger.error("Failed to decode IPC command from client \(clientID): \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
                RedEyeLogger.debug("Problematic JSON string from client \(clientID): \(text)", category: "WebSocketServerManager")
                // Optionally, send an error response back to the client
                // let errorResponse = """
                // {"status": "error", "message": "Failed to decode command: \(error.localizedDescription.escapedForJSON())"}
                // """
                // ws.send(errorResponse)
            }
        }
        webSocket.onBinary { [weak self] ws, buffer in
            guard let self = self else { return }
            RedEyeLogger.debug("Received binary data from client \(clientID). Length: \(buffer.readableBytes)", category: "WebSocketServerManager")
        }

        webSocket.onClose.whenComplete { [weak self] result in
            guard let self = self else { return }
            RedEyeLogger.info("WebSocket client disconnected: \(clientID)", category: "WebSocketServerManager")
            self.connectedClients.removeValue(forKey: clientID)
            
            switch result {
            case .success():
                let closeCodeString = webSocket.closeCode.map { String(describing: $0) } ?? "N/A"
                RedEyeLogger.info("Client \(clientID) connection closed gracefully. Code: \(closeCodeString)", category: "WebSocketServerManager")
            case .failure(let error):
                // This is where we'd catch errors that lead to a close.
                RedEyeLogger.error("Client \(clientID) connection closed with error: \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
            }
        }
        
        webSocket.onPing { ws, data in
             RedEyeLogger.debug("Received Ping from client \(clientID). Data: \(data.readableBytes) bytes. (Pong is auto-sent by stack)", category: "WebSocketServerManager")
        }
        
        webSocket.onPong { ws, data in
             RedEyeLogger.debug("Received Pong from client \(clientID). Data: \(data.readableBytes) bytes", category: "WebSocketServerManager")
        }
    }

    private func routeCommand(_ command: IPCReceivedCommand, fromClient clientID: UUID, webSocket: WebSocket) async {
        RedEyeLogger.info("Routing command '\(command.action)' (ID: \(command.commandId ?? "N/A")) from client \(clientID)", category: "WebSocketServerManager")

        // Attempt to map the action string to our IPCAction enum
        guard let action = IPCAction(rawValue: command.action) else {
            RedEyeLogger.error("Unknown action '\(command.action)' received from client \(clientID).", category: "WebSocketServerManager")
            // Optionally send an error response back to the client
            // await sendErrorResponse(to: webSocket, commandId: command.commandId, message: "Unknown action: \(command.action)")
            return
        }

        // Switch on the known action
        switch action {
        case .logMessageFromServer:
            await handleLogMessageFromServer(payload: command.payload, clientID: clientID, commandId: command.commandId, webSocket: webSocket)
        // Add other cases here as we define more actions
        // case .requestTextManipulation:
        //     RedEyeLogger.info("Placeholder for \(action.rawValue)", category: "WebSocketServerManager")
        }
    }

    private func handleLogMessageFromServer(payload: [String: JSONValue]?, clientID: UUID, commandId: String?, webSocket: WebSocket) async {
        RedEyeLogger.info("Handling 'logMessageFromServer' from client \(clientID)", category: "WebSocketServerManager")

        guard let payloadDict = payload else {
            RedEyeLogger.error("'logMessageFromServer' received without a payload from client \(clientID).", category: "WebSocketServerManager")
            // await sendErrorResponse(to: webSocket, commandId: commandId, message: "Payload missing for logMessageFromServer")
            return
        }

        // Attempt to decode the generic payload into our specific LogMessagePayload struct
        // For this, we need to convert [String: JSONValue] back to Data, then decode.
        // This is a bit round-about. A more direct decoding from JSONValue dictionary to struct might be possible
        // with a custom decoder or by making LogMessagePayload use JSONValue directly.
        // For now, let's try the Data conversion route for simplicity, though it's less efficient.

        do {
            // Convert the [String: JSONValue] payload back to JSON Data
            let payloadData = try JSONSerialization.data(withJSONObject: payloadDict.mapValues { convertJSONValueToAny($0) })
                                                    // Using a temporary helper function to convert JSONValue to Any for JSONSerialization
            
            // Now decode this Data into our specific payload struct
            let logPayload = try self.jsonDecoder.decode(LogMessagePayload.self, from: payloadData)
            
            RedEyeLogger.info("Message from client \(clientID) (via IPC command): \(logPayload.message)", category: "IPCMessageHandler") // Log to a specific category
            
            // Optional: Send acknowledgement (Phase 5)
            // await sendAckResponse(to: webSocket, commandId: commandId, message: "Message logged successfully.")

        } catch {
            RedEyeLogger.error("Failed to decode LogMessagePayload or process 'logMessageFromServer' from client \(clientID): \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
            RedEyeLogger.debug("Problematic payload for logMessageFromServer: \(payloadDict)", category: "WebSocketServerManager")
            // await sendErrorResponse(to: webSocket, commandId: commandId, message: "Invalid payload for logMessageFromServer: \(error.localizedDescription)")
        }
    }
    
    // Helper function to convert JSONValue to a type that JSONSerialization can handle
    // This is needed because JSONSerialization.data(withJSONObject:) expects standard Swift types.
    private func convertJSONValueToAny(_ jsonValue: JSONValue) -> Any {
        switch jsonValue {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { convertJSONValueToAny($0) }
        case .dictionary(let dict): return dict.mapValues { convertJSONValueToAny($0) }
        case .null: return NSNull() // JSONSerialization uses NSNull for null
        }
    }
    
    // Placeholder for sending acknowledgements (Phase 5)
    // private func sendAckResponse(to webSocket: WebSocket, commandId: String?, message: String) async { ... }
    // private func sendErrorResponse(to webSocket: WebSocket, commandId: String?, message: String) async { ... }
    
    // This method is NO LONGER CALLED EXTERNALLY by EventManager.
    // It will be triggered by handleEvent from EventBusSubscriber conformance.
    private func broadcastEventToClients(_ event: RedEyeEvent) {
        do {
            let jsonData = try self.jsonEncoder.encode(event)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                RedEyeLogger.error("Failed to convert RedEyeEvent to JSON string for broadcasting.", category: WebSocketServerManager.logCategory)
                return
            }

            if connectedClients.isEmpty {
                // EventBus already logs if no subscribers; WSSM might still want to log this specific state.
                RedEyeLogger.debug("No WebSocket clients connected. Event from bus not broadcasted.", category: WebSocketServerManager.logCategory)
                return
            }

            RedEyeLogger.debug("Broadcasting event (\(event.eventType)) from bus to \(connectedClients.count) client(s).", category: WebSocketServerManager.logCategory)
            // RedEyeLogger.debug("Event JSON for broadcast: \(jsonString)", category: "WebSocketServerManager")

            for (clientID, ws) in connectedClients {
                // RedEyeLogger.debug("Sending event to client \(clientID).", category: WebSocketServerManager.logCategory)
                ws.send(jsonString)
            }
        } catch {
            RedEyeLogger.error("Failed to encode RedEyeEvent for broadcasting: \(error.localizedDescription)", category: WebSocketServerManager.logCategory, error: error)
        }
    }

    func stopServer() {
        RedEyeLogger.info("Attempting to stop WebSocket server...", category: "WebSocketServerManager")
        
        if let bus = self.eventBus, isSubscribedToBus {
            bus.unsubscribe(self)
            isSubscribedToBus = false
            RedEyeLogger.info("WebSocketServerManager unsubscribed from EventBus.", category: WebSocketServerManager.logCategory)
        }

        for (id, ws) in connectedClients {
            RedEyeLogger.info("Closing connection to client \(id)...", category: "WebSocketServerManager")
            ws.close(code: .goingAway, promise: nil)
        }
        connectedClients.removeAll()

        serverChannel?.close(mode: .all, promise: nil)
        RedEyeLogger.info("Server channel close initiated.", category: "WebSocketServerManager")
        
        stopServerCleanup()
    }
    
    private func stopServerCleanup() {
        if let group = self.group {
            RedEyeLogger.debug("Shutting down EventLoopGroup...", category: "WebSocketServerManager")
            group.shutdownGracefully { error in
                if let error = error {
                    RedEyeLogger.error("Failed to shut down EventLoopGroup gracefully: \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
                } else {
                    RedEyeLogger.info("EventLoopGroup shut down gracefully.", category: "WebSocketServerManager")
                }
            }
        }
        self.group = nil
        self.serverChannel = nil
    }
    
    // MARK: - EventBusSubscriber Conformance
    func handleEvent(_ event: RedEyeEvent, on eventBus: EventBus) {
        // This method will be called by the MainEventBus on the main thread.
        RedEyeLogger.debug("WebSocketServerManager received event \(event.eventType) from EventBus.", category: WebSocketServerManager.logCategory)
        
        // The actual broadcast involves network I/O, so it's good practice
        // to ensure it happens on the appropriate thread (WebSocketKit handles this via EventLoop).
        // Since broadcastEventToClients uses ws.send(), which is designed to be called
        // from any thread (it will hop to its EventLoop if necessary), calling it directly is fine.
        broadcastEventToClients(event)
    }

}
