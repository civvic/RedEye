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

    // Array to hold weak subscribers.
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
                self.subscribers.append(WeakSubscriber(subscriber)) // <<< MODIFIED
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
            self.subscribers.removeAll { $0.value == nil || $0.value === subscriber }
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

            // Get a snapshot of current, valid subscribers
            let currentSubscribersObjects = self.subscribers.compactMap { $0.value } // <<< MODIFIED

            if currentSubscribersObjects.isEmpty {
                RedEyeLogger.debug("No subscribers to publish event \(event.eventType).", category: MainEventBus.logCategory)
                self.logEvent(event, wasDelivered: false)
                return
            }
            
            RedEyeLogger.debug("Publishing event \(event.eventType) to \(currentSubscribersObjects.count) subscriber(s).", category: MainEventBus.logCategory)
            self.logEvent(event, wasDelivered: true)

            for subscriberInstance in currentSubscribersObjects { // <<< MODIFIED
                DispatchQueue.main.async {
                    // subscriberInstance is already guaranteed non-nil here due to compactMap
                    subscriberInstance.handleEvent(event, on: self)
                }
            }
        }
    }
    
    private func logEvent(_ event: RedEyeEvent, wasDelivered: Bool) {
        // ...
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
}
