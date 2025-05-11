//
//  AppActivationMonitor.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/11/25.
//


import AppKit

class AppActivationMonitor {

    private let eventManager: EventManager
    private var lastKnownActiveBundleID: String? // To avoid duplicate events if possible

    init(eventManager: EventManager) {
        self.eventManager = eventManager
        RedEyeLogger.info("AppActivationMonitor initialized.", category: "AppActivationMonitor")
    }

    func startMonitoring() {
        RedEyeLogger.info("Starting application activation monitoring.", category: "AppActivationMonitor")
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil // Observe for any application
        )
    }

    func stopMonitoring() {
        RedEyeLogger.info("Stopping application activation monitoring.", category: "AppActivationMonitor")
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppActivation(_ notification: Notification) {
        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            RedEyeLogger.error("Could not get NSRunningApplication from didActivateApplicationNotification.", category: "AppActivationMonitor")
            return
        }

        guard let appName = activatedApp.localizedName, let bundleId = activatedApp.bundleIdentifier else {
            RedEyeLogger.error("Newly activated application is missing name or bundle ID. Name: \(activatedApp.localizedName ?? "N/A"), BundleID: \(activatedApp.bundleIdentifier ?? "N/A")", category: "AppActivationMonitor")
            return
        }

        // Basic de-duplication: Only emit if the bundle ID has changed.
        // This helps if multiple notifications fire for the same app activation.
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
            contextText: nil, // No context text for this event type
            metadata: ["pid": "\(activatedApp.processIdentifier)"] // Example of additional metadata
        )
        eventManager.emit(event: event)
    }

    deinit {
        stopMonitoring()
        RedEyeLogger.info("AppActivationMonitor deinitialized.", category: "AppActivationMonitor")
    }
}