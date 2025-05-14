// RedEye/Events/EventBus.swift

import Foundation

// Protocol for event subscribers to conform to
protocol EventBusSubscriber: AnyObject { // AnyObject for weak references
    func handleEvent(_ event: RedEyeEvent, on eventBus: EventBus)
    // We could add a subscriberID or allow subscribers to filter what they receive here
    // but for v0.3, a simple handler for all events is the starting point.
}

// Protocol defining the Event Bus interface
protocol EventBus: AnyObject {
    func subscribe(_ subscriber: EventBusSubscriber)
    func unsubscribe(_ subscriber: EventBusSubscriber)
    func publish(event: RedEyeEvent)
}
