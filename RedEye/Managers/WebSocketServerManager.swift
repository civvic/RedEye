// RedEye/Managers/WebSocketServerManager.swift

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import WebSocketKit
import os

class WebSocketServerManager: EventBusSubscriber, Loggable {
    var logCategoryForInstance: String { return "WebSocketServerManager" }
    var instanceLogger: Logger { Logger(subsystem: RedEyeLogger.subsystem, category: self.logCategoryForInstance) }

    
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
        info("WebSocketServerManager initialized.")
    }

    func startServer() {
        guard let group = self.group else {
            error("EventLoopGroup not initialized.")
            return
        }
        
        // Subscribe to the event bus if not already
        if let bus = self.eventBus, !isSubscribedToBus {
            bus.subscribe(self)
            isSubscribedToBus = true
            info("WebSocketServerManager subscribed to EventBus.")
        }

        // This is the pattern from WebSocketKitTests/Utilities.swift, inlined:
        let webSocketUpgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 14, // Default max frame size
            automaticErrorHandling: true, // Recommended by NIO
            shouldUpgrade: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<HTTPHeaders?> in
                self.debug("WebSocket upgrade request for URI: \(head.uri)")
                // For RedEye, we accept all WebSocket upgrade requests on our specific port.
                return channel.eventLoop.makeSucceededFuture([:]) // Empty headers, accept upgrade
            },
            upgradePipelineHandler: { (channel: Channel, head: HTTPRequestHead) -> EventLoopFuture<Void> in
                // This closure is called after the WebSocket handshake is successful.
                // It's responsible for configuring the pipeline for WebSocket frames.
                // We use WebSocketKit's WebSocket.server here.
                self.info("WebSocket client HTTP handshake successful for URI: \(head.uri). Setting up WebSocket handlers.")
                
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
                            self.debug("HTTP server pipeline upgrade processing fully completed for a client.")
                        }
                    )
                )
            }

        do {
            let channel = try bootstrap.bind(host: "localhost", port: self.port).wait()
            self.serverChannel = channel
            info("WebSocket server started and listening on ws://localhost:\(self.port)")
        } catch {
            self.error("Failed to start WebSocket server: \(error.localizedDescription)", error: error)
            stopServerCleanup()
        }
    }
    
    private func handleNewClient(webSocket: WebSocket, requestHead: HTTPRequestHead) {
        let clientID = UUID()
        info("WebSocket client connected: \(clientID) from URI: \(requestHead.uri)")
        self.connectedClients[clientID] = webSocket

        webSocket.onText { [weak self] ws, text in // Use 'ws' as provided by the closure
            guard let self = self else { return } // Ensure self is valid

            debug("Received text from client \(clientID): \(text)")
            
            // The `ws` object (WebSocketKit.WebSocket) is an EventLoopBoundBox.
            // Its methods (like send) are designed to be called from its event loop or
            // will hop to it. We can call ws.send from within the Task.
            Task {
                let responseString = await self.ipcCommandHandler.handleRawCommand(text, from: clientID)
                
                if let response = responseString {
                    self.debug("Sending response to client \(clientID): \(response)")
                    do {
                        try await ws.send(response)
                    } catch {
                        self.error("Failed to send response to client \(clientID): \(error.localizedDescription)", error: error)
                        // Optionally, try to close the WebSocket if sending fails catastrophically,
                        // or just log and let the connection continue if it's a transient issue.
                        // Example: _ = ws.close(code: .unexpectedServerError)
                    }
                } else {
                    self.debug("IPCCommandHandler did not return a response string for client \(clientID) command: \(text)")
                }
            }
        }
        
        webSocket.onBinary { [weak self] ws, buffer in
            guard let self = self else { return }
            debug("Received binary data from client \(clientID). Length: \(buffer.readableBytes)")
        }

        webSocket.onClose.whenComplete { [weak self] result in
            guard let self = self else { return }
            info("WebSocket client disconnected: \(clientID)")
            self.connectedClients.removeValue(forKey: clientID)
            
            switch result {
            case .success():
                let closeCodeString = webSocket.closeCode.map { String(describing: $0) } ?? "N/A"
                info("Client \(clientID) connection closed gracefully. Code: \(closeCodeString)")
            case .failure(let error):
                // This is where we'd catch errors that lead to a close.
                self.error("Client \(clientID) connection closed with error: \(error.localizedDescription)", error: error)
            }
        }
        
        webSocket.onPing { ws, data in
            self.debug("Received Ping from client \(clientID). Data: \(data.readableBytes) bytes. (Pong is auto-sent by stack)")
        }
        
        webSocket.onPong { ws, data in
            self.debug("Received Pong from client \(clientID). Data: \(data.readableBytes) bytes")
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
                error("Failed to convert RedEyeEvent to JSON string for broadcasting.")
                return
            }

            if connectedClients.isEmpty {
                // EventBus already logs if no subscribers; WSSM might still want to log this specific state.
                debug("No WebSocket clients connected. Event from bus not broadcasted.")
                return
            }

            debug("Broadcasting event (\(event.eventType)) from bus to \(connectedClients.count) client(s).")
            // debug("Event JSON for broadcast: \(jsonString)")

            for (clientID, ws) in connectedClients {
                // debug("Sending event to client \(clientID).")
                ws.send(jsonString)
            }
        } catch {
            self.error("Failed to encode RedEyeEvent for broadcasting: \(error.localizedDescription)", error: error)
        }
    }

    func stopServer() {
        info("Attempting to stop WebSocket server...")
        
        if let bus = self.eventBus, isSubscribedToBus {
            bus.unsubscribe(self)
            isSubscribedToBus = false
            info("WebSocketServerManager unsubscribed from EventBus.")
        }

        for (id, ws) in connectedClients {
            info("Closing connection to client \(id)...")
            ws.close(code: .goingAway, promise: nil)
        }
        connectedClients.removeAll()

        serverChannel?.close(mode: .all, promise: nil)
        info("Server channel close initiated.")
        
        stopServerCleanup()
    }
    
    private func stopServerCleanup() {
        if let group = self.group {
            debug("Shutting down EventLoopGroup...")
            group.shutdownGracefully { error in
                if let error = error {
                    self.error("Failed to shut down EventLoopGroup gracefully: \(error.localizedDescription)", error: error)
                } else {
                    self.info("EventLoopGroup shut down gracefully.")
                }
            }
        }
        self.group = nil
        self.serverChannel = nil
    }
    
    // MARK: - EventBusSubscriber Conformance
    func handleEvent(_ event: RedEyeEvent, on eventBus: EventBus) {
        // This method will be called by the MainEventBus on the main thread.
        debug("WebSocketServerManager received event \(event.eventType) from EventBus.")
        
        // The actual broadcast involves network I/O, so it's good practice
        // to ensure it happens on the appropriate thread (WebSocketKit handles this via EventLoop).
        // Since broadcastEventToClients uses ws.send(), which is designed to be called
        // from any thread (it will hop to its EventLoop if necessary), calling it directly is fine.
        broadcastEventToClients(event)
    }

}
