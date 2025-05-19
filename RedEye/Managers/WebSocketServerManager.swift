// RedEye/Managers/WebSocketServerManager.swift

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import WebSocketKit

class WebSocketServerManager: EventBusSubscriber {

    private static let logCategory = "WebSocketServerManager"
    
    private let port: Int = 8765
    private var serverChannel: Channel?
    private var group: EventLoopGroup?
    private var connectedClients: [UUID: WebSocket] = [:]
    private let jsonEncoder: JSONEncoder

    private weak var eventBus: EventBus?
    private var isSubscribedToBus: Bool = false

    private let ipcCommandHandler: IPCCommandHandler

    init(eventBus: EventBus, ipcCommandHandler: IPCCommandHandler) {
        self.eventBus = eventBus
        self.ipcCommandHandler = ipcCommandHandler
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount) // Use System.coreCount
        self.jsonEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys] // More compact for network
            encoder.dateEncodingStrategy = .iso8601
            return encoder
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

        webSocket.onText { [weak self] ws, text in // Use 'ws' as provided by the closure
            guard let self = self else { return } // Ensure self is valid

            RedEyeLogger.debug("Received text from client \(clientID): \(text)", category: WebSocketServerManager.logCategory)
            
            // The `ws` object (WebSocketKit.WebSocket) is an EventLoopBoundBox.
            // Its methods (like send) are designed to be called from its event loop or
            // will hop to it. We can call ws.send from within the Task.
            Task {
                let responseString = await self.ipcCommandHandler.handleRawCommand(text, from: clientID)
                
                if let response = responseString {
                    RedEyeLogger.debug("Sending response to client \(clientID): \(response)", category: WebSocketServerManager.logCategory)
                    do {
                        try await ws.send(response)
                    } catch {
                        RedEyeLogger.error("Failed to send response to client \(clientID): \(error.localizedDescription)", category: WebSocketServerManager.logCategory, error: error)
                        // Optionally, try to close the WebSocket if sending fails catastrophically,
                        // or just log and let the connection continue if it's a transient issue.
                        // Example: _ = ws.close(code: .unexpectedServerError)
                    }
                } else {
                    RedEyeLogger.debug("IPCCommandHandler did not return a response string for client \(clientID) command: \(text)", category: WebSocketServerManager.logCategory)
                }
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
