import Foundation
import NIOCore
import NIOPosix // For MultiThreadedEventLoopGroup
import NIOHTTP1 // For HTTPRequestHead, configureHTTPServerPipeline
import NIOWebSocket // For NIOWebSocketServerUpgrader, WebSocketErrorCode
import WebSocketKit // For WebSocket object and WebSocket.server

class WebSocketServerManager {

    private let port: Int = 8765
    private var serverChannel: Channel?
    private var group: EventLoopGroup?
    private var connectedClients: [UUID: WebSocket] = [:]

    // Add this encoder at the class level for reuse
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Or just .sortedKeys for compactness over network
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }() // Add this

    init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func startServer() {
        guard let group = self.group else {
            RedEyeLogger.error("EventLoopGroup not initialized.", category: "WebSocketServerManager")
            return
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
            guard let self = self else { return }
            RedEyeLogger.debug("Received text from client \(clientID): \(text)", category: "WebSocketServerManager")
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

    func stopServer() {
        RedEyeLogger.info("Attempting to stop WebSocket server...", category: "WebSocketServerManager")
        
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
    
    public func broadcastEvent(_ event: RedEyeEvent) {
        do {
            let jsonData = try self.jsonEncoder.encode(event) // Use Self.jsonEncoder
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                RedEyeLogger.error("Failed to convert RedEyeEvent to JSON string for broadcasting.", category: "WebSocketServerManager")
                return
            }

            if connectedClients.isEmpty {
                RedEyeLogger.debug("No WebSocket clients connected. Event not broadcasted.", category: "WebSocketServerManager")
                return
            }

            RedEyeLogger.info("Broadcasting event (\(event.eventType)) to \(connectedClients.count) client(s).", category: "WebSocketServerManager")
            // RedEyeLogger.debug("Event JSON for broadcast: \(jsonString)", category: "WebSocketServerManager") // Can be verbose

            for (clientID, ws) in connectedClients {
                RedEyeLogger.debug("Sending event to client \(clientID).", category: "WebSocketServerManager")
                ws.send(jsonString) // WebSocketKit's send method takes a String directly
            }
        } catch {
            RedEyeLogger.error("Failed to encode RedEyeEvent for broadcasting: \(error.localizedDescription)", category: "WebSocketServerManager", error: error)
        }
    }

}
