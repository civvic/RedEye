// RedEye/Managers/AppActivationMonitor.swift

import AppKit

class AppActivationMonitor {

    private let eventManager: EventManager
    private var lastKnownActiveBundleID: String? // To avoid duplicate events if possible
    private var notificationObserver: NSObjectProtocol? // Store the observer to remove it correctly

    // MARK: - Developer Toggle <<< NEW
    var isEnabled: Bool = true // Default to true, will be set by AppDelegate

    init(eventManager: EventManager) {
        self.eventManager = eventManager
        RedEyeLogger.info("AppActivationMonitor initialized.", category: "AppActivationMonitor")
    }

    func startMonitoring() {
        // Respect the isEnabled flag <<< MODIFIED
        guard isEnabled else {
            RedEyeLogger.info("AppActivation monitoring is disabled by toggle.", category: "AppActivationMonitor")
            return
        }
        
        guard notificationObserver == nil else {
             RedEyeLogger.info("AppActivation monitoring is already active.", category: "AppActivationMonitor")
             return
        }

        RedEyeLogger.info("Starting application activation monitoring.", category: "AppActivationMonitor")
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, // Observe for any application
            queue: OperationQueue.main // Specify a queue, main is often suitable
        ) { [weak self] notification in
                self?.handleAppActivation(notification)
        }
    }

    func stopMonitoring() {
        // Only attempt to remove if the observer exists <<< MODIFIED
        if let observer = notificationObserver {
            RedEyeLogger.info("Stopping application activation monitoring.", category: "AppActivationMonitor")
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            notificationObserver = nil
        } else {
            // Optional: Log if stop is called when not monitoring
             RedEyeLogger.debug("Attempted to stop AppActivation monitoring, but it was not active.", category: "AppActivationMonitor")
        }
    }

    // Make private again as it's only called internally now via closure
    private func handleAppActivation(_ notification: Notification) {
        // ... (rest of handleAppActivation logic remains the same) ...
        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            RedEyeLogger.error("Could not get NSRunningApplication from didActivateApplicationNotification.", category: "AppActivationMonitor")
            return
        }

        guard let appName = activatedApp.localizedName, let bundleId = activatedApp.bundleIdentifier else {
            RedEyeLogger.error("Newly activated application is missing name or bundle ID. Name: \(activatedApp.localizedName ?? "N/A"), BundleID: \(activatedApp.bundleIdentifier ?? "N/A")", category: "AppActivationMonitor")
            return
        }

        if bundleId == lastKnownActiveBundleID {
            RedEyeLogger.debug("Application \(appName) (\(bundleId)) re-activated or notification duplicated. Ignoring.", category: "AppActivationMonitor")
            return
        }
        lastKnownActiveBundleID = bundleId

        RedEyeLogger.info("Application activated: \(appName) (\(bundleId))", category: "AppActivationMonitor")

        let event = RedEyeEvent(
            eventType: .applicationActivated,
            sourceApplicationName: appName,
            sourceBundleIdentifier: bundleId,
            contextText: nil,
            metadata: ["pid": "\(activatedApp.processIdentifier)"]
        )
        eventManager.emit(event: event)
    }

    deinit {
        stopMonitoring() // Ensure cleanup on deinitialization
        RedEyeLogger.info("AppActivationMonitor deinitialized.", category: "AppActivationMonitor")
    }
}
