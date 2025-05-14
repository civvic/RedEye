// RedEye/Events/MainEventBus.swift

import Foundation

// Helper struct to store weak references to EventBusSubscriber
// This is specifically typed to EventBusSubscriber now.
private struct WeakSubscriber {
    weak var value: EventBusSubscriber?
    init(_ value: EventBusSubscriber) {
        self.value = value
    }
}

class MainEventBus: EventBus {

    private static let logCategory = "MainEventBus"
    private var subscribers: [WeakSubscriber] = []
    private let busQueue = DispatchQueue(label: "com.vic.RedEye.MainEventBusQueue", qos: .utility)

    init() {
        RedEyeLogger.info("MainEventBus initialized.", category: MainEventBus.logCategory)
    }

    func subscribe(_ subscriber: EventBusSubscriber) {
        busQueue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers.removeAll { $0.value == nil }
            if !self.subscribers.contains(where: { $0.value === subscriber }) {
                
                RedEyeLogger.debug("DEBUG: subscribe - \(String(describing: type(of: subscriber))) - Before add, count: \(self.subscribers.compactMap{$0.value}.count)", category: MainEventBus.logCategory) // Generic logging

                self.subscribers.append(WeakSubscriber(subscriber))
                
                RedEyeLogger.debug("DEBUG: subscribe - \(String(describing: type(of: subscriber))) - After add, count: \(self.subscribers.compactMap{$0.value}.count)", category: MainEventBus.logCategory) // Generic logging

                RedEyeLogger.debug("Subscriber \(type(of: subscriber)) added. Total: \(self.subscribers.compactMap{$0.value}.count)", category: MainEventBus.logCategory)
            } else {
                RedEyeLogger.debug("Subscriber \(type(of: subscriber)) already exists.", category: MainEventBus.logCategory)
            }
        }
    }

    func unsubscribe(_ subscriber: EventBusSubscriber) {
        busQueue.async { [weak self] in
            guard let self = self else { return }
            let initialCount = self.subscribers.compactMap{$0.value}.count
            
            RedEyeLogger.debug("DEBUG: unsubscribe - \(String(describing: type(of: subscriber))) - Before remove, count: \(self.subscribers.compactMap{$0.value}.count)", category: MainEventBus.logCategory) // Generic logging

            self.subscribers.removeAll { $0.value == nil || $0.value === subscriber }
            
            RedEyeLogger.debug("DEBUG: unsubscribe - \(String(describing: type(of: subscriber))) - After remove, count: \(self.subscribers.compactMap{$0.value}.count)", category: MainEventBus.logCategory) // Generic logging

            let finalCount = self.subscribers.compactMap{$0.value}.count
            if initialCount != finalCount {
                RedEyeLogger.debug("Subscriber \(type(of: subscriber)) removed. Total: \(finalCount)", category: MainEventBus.logCategory)
            } else {
                RedEyeLogger.debug("Subscriber \(type(of: subscriber)) not found for removal.", category: MainEventBus.logCategory)
            }
        }
    }

    func publish(event: RedEyeEvent) {
        busQueue.async { [weak self] in
            guard let self = self else { return }

            RedEyeLogger.debug("DEBUG: publish - Entering busQueue block for event \(event.eventType)", category: MainEventBus.logCategory)

            // Get a snapshot of current, valid subscribers
            let currentSubscribersObjects = self.subscribers.compactMap { $0.value }

            RedEyeLogger.debug("DEBUG: publish - Snapshot count: \(currentSubscribersObjects.count)", category: MainEventBus.logCategory)

            if currentSubscribersObjects.isEmpty {
                RedEyeLogger.debug("No subscribers to publish event \(event.eventType).", category: MainEventBus.logCategory)
                self.logEvent(event, wasDelivered: false)
                return
            }
            
            RedEyeLogger.debug("Publishing event \(event.eventType) to \(currentSubscribersObjects.count) subscriber(s).", category: MainEventBus.logCategory)
            self.logEvent(event, wasDelivered: true)

            for subscriberInstance in currentSubscribersObjects {
                RedEyeLogger.debug("DEBUG: publish - Scheduling main.async for subscriber \(String(describing: type(of: subscriberInstance)))", category: MainEventBus.logCategory) // Generic logging

                DispatchQueue.main.async {

                    RedEyeLogger.debug("DEBUG: publish - Executing on main for subscriber \(String(describing: type(of: subscriberInstance))) for event \(event.eventType)", category: MainEventBus.logCategory) // Generic logging

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
                RedEyeLogger.info("--- RedEyeEvent \(deliveryStatus) (via EventBus) ---", category: MainEventBus.logCategory)
                RedEyeLogger.info(jsonString, category: MainEventBus.logCategory)
                RedEyeLogger.info("------------------------------------", category: MainEventBus.logCategory)
            }
        } catch {
            RedEyeLogger.error("Failed to encode RedEyeEvent for EventBus logging", category: MainEventBus.logCategory, error: error)
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
            RedEyeLogger.error("waitForQueueToProcess timed out waiting for busQueue.", category: MainEventBus.logCategory)
        } else {
            RedEyeLogger.debug("waitForQueueToProcess completed.", category: MainEventBus.logCategory)
        }
    }
    #endif
}
