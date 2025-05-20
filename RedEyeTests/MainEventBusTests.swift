// RedEyeTests/MainEventBusTests.swift

import XCTest
@testable import RedEye

// Mock Subscriber for testing
class MockEventBusSubscriber: EventBusSubscriber {
    var id: UUID // To differentiate subscribers if needed
    var receivedEvents: [RedEyeEvent] = []
    var eventHandledExpectation: XCTestExpectation?
    var handlingThread: Thread?

    init(id: UUID = UUID(), expectation: XCTestExpectation? = nil) {
        self.id = id
        self.eventHandledExpectation = expectation
//        RedEyeLogger.debug("MOCK (\(id.uuidString.prefix(4))): INIT", category: "MainEventBusTests")
    }

    deinit {
//        RedEyeLogger.debug("MOCK (\(id.uuidString.prefix(4))): DEINIT", category: "MainEventBusTests")
    }

    func handleEvent(_ event: RedEyeEvent, on eventBus: EventBus) {
//        RedEyeLogger.debug("MOCK (\(id.uuidString.prefix(4))): handleEvent for \(event.eventType) on thread: \(Thread.current). Expectation exists: \(eventHandledExpectation != nil)", category: "MainEventBusTests")
        handlingThread = Thread.current
        receivedEvents.append(event)
        eventHandledExpectation?.fulfill() // This is key
//        RedEyeLogger.debug("MOCK (\(id.uuidString.prefix(4))): Fulfilled expectation. Event count: \(receivedEvents.count)", category: "MainEventBusTests")
    }

    func reset() {
        receivedEvents.removeAll()
        eventHandledExpectation = nil
        handlingThread = nil
    }
}

class MainEventBusTests: XCTestCase {

    var eventBus: MainEventBus!
    var mockSubscriber1: MockEventBusSubscriber!
    var mockSubscriber2: MockEventBusSubscriber!

    override func setUpWithError() throws {
        // This method is called before the invocation of each test method in the class.
        try super.setUpWithError()
        eventBus = MainEventBus() // Create a fresh bus for each test
        mockSubscriber1 = MockEventBusSubscriber(id: UUID(), expectation: nil) // Expectation set per test
        mockSubscriber2 = MockEventBusSubscriber(id: UUID(), expectation: nil) // Expectation set per test
        RedEyeLogger.isVerboseLoggingEnabled = true // Enable for test logs
    }

    override func tearDownWithError() throws {
        // This method is called after the invocation of each test method in the class.
        eventBus = nil
        mockSubscriber1 = nil
        mockSubscriber2 = nil
        try super.tearDownWithError()
    }

    // Helper to create a dummy event using the public convenience initializer
    private func makeDummyEvent(eventType: RedEyeEventType = .applicationActivated,
                                sourceAppName: String = "TestApp",
                                sourceBundleID: String = "com.test.app",
                                context: String? = "Test Context",
                                metadata: [String:String]? = ["testKey": "testValue"]) -> RedEyeEvent {
        // Uses the RedEyeEvent convenience init which sets its own id and timestamp
        return RedEyeEvent(eventType: eventType,
                           sourceApplicationName: sourceAppName,
                           sourceBundleIdentifier: sourceBundleID,
                           contextText: context,
                           metadata: metadata)
    }

    // MARK: - Test Cases

    func testSubscribeAndPublishToSingleSubscriber() {
        // 1. Arrange
        let expectation = XCTestExpectation(description: "Subscriber 1 should receive the event")
        mockSubscriber1.eventHandledExpectation = expectation
        
        // Define the expected properties for the event we're sending
        let expectedEventType: RedEyeEventType = .textSelection
        let expectedAppName = "SpecificApp"
        let expectedMetadata = ["source": "singleSubTest"]

        let dummyEvent = makeDummyEvent(eventType: expectedEventType,
                                        sourceAppName: expectedAppName,
                                        metadata: expectedMetadata)
        let expectedId = dummyEvent.id
        let expectedTimestamp = dummyEvent.timestamp

        // 2. Act
        eventBus.subscribe(mockSubscriber1)
        eventBus.publish(event: dummyEvent) // The event published will have its own ID and timestamp

        // 3. Assert
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockSubscriber1.receivedEvents.count, 1, "Subscriber 1 should have received exactly one event.")
        
        guard let receivedEvent = mockSubscriber1.receivedEvents.first else {
            XCTFail("Subscriber 1 did not receive any event.")
            return
        }
        
        XCTAssertEqual(receivedEvent.id, expectedId, "Received event has wrong event ID.")
        XCTAssertEqual(receivedEvent.timestamp, expectedTimestamp, "Received event has wrong timestamp.")
        XCTAssertEqual(receivedEvent.eventType, expectedEventType, "Received event has wrong type.")
        XCTAssertEqual(receivedEvent.sourceApplicationName, expectedAppName, "Received event has wrong source app name.")
        XCTAssertEqual(receivedEvent.metadata?["source"], expectedMetadata["source"], "Received event has wrong metadata.")
    }

    func testPublishToMultipleSubscribers() {
        // 1. Arrange
        let expectation1 = XCTestExpectation(description: "Subscriber 1 should receive the event")
        let expectation2 = XCTestExpectation(description: "Subscriber 2 should receive the event")
        mockSubscriber1.eventHandledExpectation = expectation1
        mockSubscriber2.eventHandledExpectation = expectation2

        let dummyEvent = makeDummyEvent(eventType: .fileSystemEvent)
        let expectedId = dummyEvent.id
        let expectedTimestamp = dummyEvent.timestamp

        // 2. Act
        eventBus.subscribe(mockSubscriber1)
        eventBus.subscribe(mockSubscriber2)
        eventBus.publish(event: dummyEvent)

        // 3. Assert
        wait(for: [expectation1, expectation2], timeout: 1.0)

        // Check subscriber 1
        XCTAssertEqual(mockSubscriber1.receivedEvents.count, 1, "Subscriber 1 should have received one event.")
        XCTAssertEqual(mockSubscriber1.receivedEvents.first?.id, expectedId, "Subscriber 1 received wrong event ID.")
        XCTAssertEqual(mockSubscriber1.receivedEvents.first?.eventType, .fileSystemEvent, "Subscriber 1 received event with wrong type.")
        XCTAssertEqual(mockSubscriber1.receivedEvents.first?.timestamp, expectedTimestamp, "Subscriber 1 received wrong timestamp.")


        // Check subscriber 2
        XCTAssertEqual(mockSubscriber2.receivedEvents.count, 1, "Subscriber 2 should have received one event.")
        XCTAssertEqual(mockSubscriber2.receivedEvents.first?.id, expectedId, "Subscriber 2 received wrong event ID.")
        XCTAssertEqual(mockSubscriber2.receivedEvents.first?.eventType, .fileSystemEvent, "Subscriber 2 received event with wrong type.")
        XCTAssertEqual(mockSubscriber2.receivedEvents.first?.timestamp, expectedTimestamp, "Subscriber 2 received wrong timestamp.")
    }

    func testUnsubscribe_EnsuresUnsubscribedIsNotCalled() {
        // 1. Arrange
        let sub1ShouldBeCalledExpectation = XCTestExpectation(description: "Subscriber 1 should receive event")
        
        // Reset subscribers first to ensure clean state for this test
        mockSubscriber1.reset()
        mockSubscriber2.reset()

        // NOW assign the expectation to mockSubscriber1
        mockSubscriber1.eventHandledExpectation = sub1ShouldBeCalledExpectation // <<< CRUCIAL FIX

        let eventToPublish = makeDummyEvent(eventType: .applicationActivated)

        // 2. Act
        eventBus.subscribe(mockSubscriber1)
        eventBus.subscribe(mockSubscriber2)

        #if DEBUG
        eventBus.waitForQueueToProcess(timeout: 0.2) // Increased slightly
        #endif

        eventBus.unsubscribe(mockSubscriber2)

        #if DEBUG
        eventBus.waitForQueueToProcess(timeout: 0.2) // Increased slightly
        #endif

        eventBus.publish(event: eventToPublish)

        // 3. Assert
        wait(for: [sub1ShouldBeCalledExpectation], timeout: 2.0) // Increased timeout for CI/slower machines

        XCTAssertEqual(mockSubscriber1.receivedEvents.count, 1, "MockSubscriber1 should have received 1 event.")
        if let firstEvent = mockSubscriber1.receivedEvents.first {
            XCTAssertEqual(firstEvent.id, eventToPublish.id, "MockSubscriber1 received wrong event.")
        }

        XCTAssertTrue(mockSubscriber2.receivedEvents.isEmpty, "MockSubscriber2 (unsubscribed) should have received 0 events, but received \(mockSubscriber2.receivedEvents.count).")
    }

    func testPublishWithNoSubscribers() {
        // 1. Arrange
        let dummyEvent = makeDummyEvent(eventType: .keyboardEvent)
        
        // Ensure our mock subscribers (which are not subscribed) are clean
        mockSubscriber1.reset()
        mockSubscriber2.reset()

        // 2. Act
        // Publish an event when no subscribers are registered
        eventBus.publish(event: dummyEvent)
        
        // To ensure the publish operation (which is async to busQueue) has had a chance to complete
        // its internal logic (like logging "No subscribers"), we can wait on the bus queue.
        #if DEBUG
        eventBus.waitForQueueToProcess(timeout: 0.5)
        #else
        // For non-debug, a small sleep might be the only way to increase likelihood of processing,
        // though the primary assertion is that no crashes occur and mocks are empty.
        // This part of the test (verifying the log output implicitly) is less critical than crash safety.
        Thread.sleep(forTimeInterval: 0.1) // Give a small window for async operations
        #endif

        // 3. Assert
        // Verify that mock subscribers (which were never subscribed) did not receive the event.
        XCTAssertTrue(mockSubscriber1.receivedEvents.isEmpty, "MockSubscriber1 should not have received any events.")
        XCTAssertTrue(mockSubscriber2.receivedEvents.isEmpty, "MockSubscriber2 should not have received any events.")
        
        // The main test here is that the publish call doesn't crash or hang.
        // We can also check the logs manually (if running locally) to see the
        // "No subscribers to publish event..." message from MainEventBus.
        // Programmatically asserting log output is beyond simple XCTest without extra tools.
        RedEyeLogger.debug("TEST: testPublishWithNoSubscribers - END (Assertions assume no crash and mocks are empty)", category: "MainEventBusTests")
    }
    
    func testEventDeliveryOnMainThread() {
        let testID = "DeliveryTest"
//        RedEyeLogger.debug("TEST [\(testID)]: START", category: "MainEventBusTests")

        // 1. Arrange
        let expectation = XCTestExpectation(description: "[\(testID)] Subscriber should receive event and check thread")
//        RedEyeLogger.debug("TEST [\(testID)]: Created expectation: \(expectation.description)", category: "MainEventBusTests")
        
        mockSubscriber1.reset() // Reset first
//        RedEyeLogger.debug("TEST [\(testID)]: mockSubscriber1 reset. Expectation before set: \(mockSubscriber1.eventHandledExpectation == nil ? "nil" : "exists")", category: "MainEventBusTests")
        
        mockSubscriber1.eventHandledExpectation = expectation // Assign expectation
//        RedEyeLogger.debug("TEST [\(testID)]: mockSubscriber1 expectation set. Expectation after set: \(mockSubscriber1.eventHandledExpectation == nil ? "nil" : "exists")", category: "MainEventBusTests")


        let dummyEvent = makeDummyEvent(eventType: .applicationActivated)
//        RedEyeLogger.debug("TEST [\(testID)]: Created dummyEvent: ID \(dummyEvent.id), Type \(dummyEvent.eventType)", category: "MainEventBusTests")

        // 2. Act
//        RedEyeLogger.debug("TEST [\(testID)]: Subscribing mockSubscriber1 (\(mockSubscriber1.id.uuidString.prefix(4)))", category: "MainEventBusTests")
        eventBus.subscribe(mockSubscriber1)

        // Wait for subscribe to process
        #if DEBUG
        eventBus.waitForQueueToProcess(timeout: 0.1)
        #endif
//        RedEyeLogger.debug("TEST [\(testID)]: Subscription processed", category: "MainEventBusTests")

//        RedEyeLogger.debug("TEST [\(testID)]: Publishing event \(dummyEvent.id)", category: "MainEventBusTests")
        eventBus.publish(event: dummyEvent)
//        RedEyeLogger.debug("TEST [\(testID)]: eventBus.publish call returned", category: "MainEventBusTests")


        // 3. Assert
//        RedEyeLogger.debug("TEST [\(testID)]: Waiting for expectation: \(expectation.description)", category: "MainEventBusTests")
        wait(for: [expectation], timeout: 1.0) // Original timeout
//        RedEyeLogger.debug("TEST [\(testID)]: Expectation wait finished. Fulfilled: ??? (check logs from MOCK)", category: "MainEventBusTests")


        XCTAssertNotNil(mockSubscriber1.handlingThread, "[\(testID)] Handling thread should have been recorded.")
        if let handlingThread = mockSubscriber1.handlingThread {
            XCTAssertTrue(handlingThread.isMainThread, "[\(testID)] Event should have been delivered on the main thread. Was on: \(handlingThread)")
//            RedEyeLogger.debug("TEST [\(testID)]: Verified event delivered on thread: \(handlingThread)", category: "MainEventBusTests")
        } else {
            XCTFail("[\(testID)] Handling thread was not recorded by mock subscriber.")
        }
        
        XCTAssertEqual(mockSubscriber1.receivedEvents.count, 1, "[\(testID)] Subscriber should have received one event.")
        RedEyeLogger.debug("TEST [\(testID)]: END", category: "MainEventBusTests")
    }

    func testWeakReferenceOfSubscriber() {
//        RedEyeLogger.debug("TEST: testWeakReferenceOfSubscriber - START", category: "MainEventBusTests")
        // 1. Arrange
        var deallocatableSubscriber: MockEventBusSubscriber? = MockEventBusSubscriber(id: UUID(), expectation: nil)
//        let deallocatableSubscriberID = deallocatableSubscriber!.id // For logging

        // A persistent subscriber to ensure the bus still works
        let persistentSubscriberExpectation = XCTestExpectation(description: "Persistent subscriber should receive event after other is deallocated")
        mockSubscriber1.eventHandledExpectation = persistentSubscriberExpectation
        mockSubscriber1.reset()

        let dummyEvent = makeDummyEvent(eventType: .fileSystemEvent)

        // 2. Act
//        RedEyeLogger.debug("TEST: Subscribing deallocatableSubscriber (\(deallocatableSubscriberID.uuidString.prefix(4)))", category: "MainEventBusTests")
        eventBus.subscribe(deallocatableSubscriber!)
//        RedEyeLogger.debug("TEST: Subscribing persistentSubscriber (mockSubscriber1: \(mockSubscriber1.id.uuidString.prefix(4)))", category: "MainEventBusTests")
        eventBus.subscribe(mockSubscriber1)

        // Ensure subscriptions are processed
        #if DEBUG
        eventBus.waitForQueueToProcess(timeout: 0.1)
        #endif
//        RedEyeLogger.debug("TEST: Subscriptions processed", category: "MainEventBusTests")


        // Make the deallocatableSubscriber go out of scope and eligible for deallocation
//        RedEyeLogger.debug("TEST: De-referencing deallocatableSubscriber (\(deallocatableSubscriberID.uuidString.prefix(4)))", category: "MainEventBusTests")
        // Add a deinit to MockEventBusSubscriber to confirm deallocation
        deallocatableSubscriber = nil
        
        // ARC deallocation can be asynchronous. To increase the chance that MainEventBus's
        // weak reference becomes nil and gets cleaned up during a subsequent subscribe/publish,
        // we can publish one event (which persistent should get), then another.
        // The internal cleanup in subscribe/publish might remove the nilled weak ref.

        // Publish first event
//        RedEyeLogger.debug("TEST: Publishing first dummy event (post-dealloc attempt)", category: "MainEventBusTests")
        eventBus.publish(event: makeDummyEvent(eventType: .keyboardEvent)) // Different event type for clarity if needed

        // Wait for persistent subscriber to get the first event
        // Use a temporary expectation for this intermediate publish
        let tempExpectation = XCTestExpectation(description: "Persistent subscriber gets first event")
        mockSubscriber1.eventHandledExpectation = tempExpectation // Re-assign expectation
        wait(for: [tempExpectation], timeout: 1.0)
        mockSubscriber1.reset() // Reset for the main event we care about for this test
        mockSubscriber1.eventHandledExpectation = persistentSubscriberExpectation // Assign the main expectation


        // Publish the main test event
//        RedEyeLogger.debug("TEST: Publishing main test dummyEvent (\(dummyEvent.id))", category: "MainEventBusTests")
        eventBus.publish(event: dummyEvent)

        // 3. Assert
//        RedEyeLogger.debug("TEST: Waiting for persistentSubscriberExpectation (\(mockSubscriber1.id.uuidString.prefix(4)))", category: "MainEventBusTests")
        wait(for: [persistentSubscriberExpectation], timeout: 1.0)
//        RedEyeLogger.debug("TEST: persistentSubscriberExpectation fulfilled", category: "MainEventBusTests")


        XCTAssertEqual(mockSubscriber1.receivedEvents.count, 1, "Persistent subscriber should have received the main test event.")
        if let event = mockSubscriber1.receivedEvents.first {
            XCTAssertEqual(event.id, dummyEvent.id, "Persistent subscriber received wrong event.")
        }
        
        // The main assertion is that the test didn't crash trying to access a deallocated subscriber.
        // We can't easily assert that `deallocatableSubscriber`'s handleEvent was *not* called
        // because the instance itself is gone.
        // We also cannot reliably assert the internal count of subscribers in MainEventBus
        // without making its internal array or count public/internal.
        // The bus's internal cleanup (`self.subscribers.removeAll { $0.value == nil }`) happens
        // during subscribe or before iterating in publish.

//        RedEyeLogger.debug("TEST: testWeakReferenceOfSubscriber - END (Test assumes no crash when publishing after a subscriber deallocates)", category: "MainEventBusTests")
    }

}
