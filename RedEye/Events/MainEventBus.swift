// RedEye/Events/MainEventBus.swift

import Foundation
import os

// Helper struct to store weak references to EventBusSubscriber
// This is specifically typed to EventBusSubscriber now.
private struct WeakSubscriber {
    weak var value: EventBusSubscriber?
    init(_ value: EventBusSubscriber) {
        self.value = value
    }
}

class MainEventBus: EventBus, Loggable {
    var logCategoryForInstance: String { return "MainEventBus" }
    var instanceLogger: Logger { Logger(subsystem: RedEyeLogger.subsystem, category: self.logCategoryForInstance) }

    private static let logCategory = ""
    private var subscribers: [WeakSubscriber] = []
    private let busQueue = DispatchQueue(label: "com.vic.RedEye.MainEventBusQueue", qos: .utility)

    init() {
        info("MainEventBus initialized.")
    }

    func subscribe(_ subscriber: EventBusSubscriber) {
        busQueue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers.removeAll { $0.value == nil }
            if !self.subscribers.contains(where: { $0.value === subscriber }) {
                
                debug("DEBUG: subscribe - \(String(describing: type(of: subscriber))) - Before add, count: \(self.subscribers.compactMap{$0.value}.count)") // Generic logging

                self.subscribers.append(WeakSubscriber(subscriber))
                
                debug("DEBUG: subscribe - \(String(describing: type(of: subscriber))) - After add, count: \(self.subscribers.compactMap{$0.value}.count)") // Generic logging

                debug("Subscriber \(type(of: subscriber)) added. Total: \(self.subscribers.compactMap{$0.value}.count)")
            } else {
                debug("Subscriber \(type(of: subscriber)) already exists.")
            }
        }
    }

    func unsubscribe(_ subscriber: EventBusSubscriber) {
        busQueue.async { [weak self] in
            guard let self = self else { return }
            let initialCount = self.subscribers.compactMap{$0.value}.count
            
            debug("DEBUG: unsubscribe - \(String(describing: type(of: subscriber))) - Before remove, count: \(self.subscribers.compactMap{$0.value}.count)") // Generic logging

            self.subscribers.removeAll { $0.value == nil || $0.value === subscriber }
            
            debug("DEBUG: unsubscribe - \(String(describing: type(of: subscriber))) - After remove, count: \(self.subscribers.compactMap{$0.value}.count)") // Generic logging

            let finalCount = self.subscribers.compactMap{$0.value}.count
            if initialCount != finalCount {
                debug("Subscriber \(type(of: subscriber)) removed. Total: \(finalCount)")
            } else {
                debug("Subscriber \(type(of: subscriber)) not found for removal.")
            }
        }
    }

    func publish(event: RedEyeEvent) {
        busQueue.async { [weak self] in
            guard let self = self else { return }

            debug("DEBUG: publish - Entering busQueue block for event \(event.eventType)")

            // Get a snapshot of current, valid subscribers
            let currentSubscribersObjects = self.subscribers.compactMap { $0.value }

            debug("DEBUG: publish - Snapshot count: \(currentSubscribersObjects.count)")

            if currentSubscribersObjects.isEmpty {
                debug("No subscribers to publish event \(event.eventType).")
                self.logEvent(event, wasDelivered: false)
                return
            }
            
            debug("Publishing event \(event.eventType) to \(currentSubscribersObjects.count) subscriber(s).")
            self.logEvent(event, wasDelivered: true)

            for subscriberInstance in currentSubscribersObjects {
                debug("DEBUG: publish - Scheduling main.async for subscriber \(String(describing: type(of: subscriberInstance)))") // Generic logging

                DispatchQueue.main.async {

                    self.debug("DEBUG: publish - Executing on main for subscriber \(String(describing: type(of: subscriberInstance))) for event \(event.eventType)") // Generic logging

                    // subscriberInstance is already guaranteed non-nil here due to compactMap
                    subscriberInstance.handleEvent(event, on: self)
                }
            }
        }
    }
    
    private func logEvent(_ event: RedEyeEvent, wasDelivered: Bool) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(event)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let deliveryStatus = wasDelivered ? "Published" : "Not Published (No Subscribers)"
                info("--- RedEyeEvent \(deliveryStatus) (via EventBus) ---")
                info(jsonString)
                info("------------------------------------")
            }
        } catch {
            self.error("Failed to encode RedEyeEvent for EventBus logging", error: error)
        }
    }
    
    // MARK: - Testability Hook <<< NEW SECTION
    #if DEBUG // Or a more specific TESTING build configuration flag
    /// **For Testing Only:** Allows a test to synchronize with the internal bus queue.
    /// Enqueues a block on the bus's serial queue and waits for it to complete.
    internal func waitForQueueToProcess(timeout: TimeInterval = 0.5) {
        let group = DispatchGroup()
        group.enter() // Enter the group before dispatching
        self.busQueue.async { // Dispatch a block to the busQueue
            group.leave() // Leave the group once this block is executed
        }
        // Wait for the group to be empty (i.e., the block on busQueue has executed)
        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            error("waitForQueueToProcess timed out waiting for busQueue.")
        } else {
            debug("waitForQueueToProcess completed.")
        }
    }
    #endif
}
