// RedEye/Managers/AppActivationMonitor.swift

import AppKit
import Foundation // For NSAppleScript

class AppActivationMonitor {

    private let eventBus: EventBus
    private var lastKnownActiveBundleID: String? // To avoid duplicate events if possible
    private var notificationObserver: NSObjectProtocol? // Store the observer to remove it correctly

    var isEnabled: Bool = true // Default to true, will be set by AppDelegate

    // MARK: - Browser URL Capture PoC (Safari) <<< NEW SECTION
    var isEnabledBrowserURLCapture: Bool = false // Specific toggle for this PoC
    private let safariBundleID = "com.apple.Safari"
    private var appleScriptSafariURLTitle: NSAppleScript?

    init(eventBus: EventBus) {
        self.eventBus = eventBus
        RedEyeLogger.info("AppActivationMonitor initialized.", category: "AppActivationMonitor")
        
        // Pre-compile the AppleScript for Safari URL capture
        let scriptSource = """
        tell application "Safari"
            -- We assume Safari is frontmost as this is triggered on its activation
            if not (exists front window) then return "error:No Safari window"
            try
                set currentTab to current tab of front window
                set theURL to URL of currentTab
                set theTitle to name of currentTab
                if theURL is missing value then set theURL to ""
                if theTitle is missing value then set theTitle to ""
                return theURL & "|||" & theTitle
            on error errMsg number errNum
                return "error:AppleScript error - " & errMsg
            end try
        end tell
        """
        self.appleScriptSafariURLTitle = NSAppleScript(source: scriptSource)
        if self.appleScriptSafariURLTitle == nil {
            RedEyeLogger.error("Failed to initialize AppleScript for Safari URL capture.", category: "AppActivationMonitor")
        }
    }

    func startMonitoring() {
        guard isEnabled || isEnabledBrowserURLCapture else { // Also check browser capture flag
            RedEyeLogger.info("AppActivation monitoring (and Safari URL PoC) is disabled by toggle(s).", category: "AppActivationMonitor")
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
        if let observer = notificationObserver {
            RedEyeLogger.info("Stopping application activation monitoring.", category: "AppActivationMonitor")
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            notificationObserver = nil
        } else {
             RedEyeLogger.debug("Attempted to stop AppActivation monitoring, but it was not active.", category: "AppActivationMonitor")
        }
    }

    deinit {
        stopMonitoring()
        RedEyeLogger.info("AppActivationMonitor deinitialized.", category: "AppActivationMonitor")
    }

    private func handleAppActivation(_ notification: Notification) {
        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            // ... (existing error handling)
            RedEyeLogger.error("Could not get NSRunningApplication from didActivateApplicationNotification.", category: "AppActivationMonitor")
            return
        }

        guard let appName = activatedApp.localizedName, let bundleId = activatedApp.bundleIdentifier else {
            // ... (existing error handling)
            RedEyeLogger.error("Newly activated application is missing name or bundle ID. Name: \(activatedApp.localizedName ?? "N/A"), BundleID: \(activatedApp.bundleIdentifier ?? "N/A")", category: "AppActivationMonitor")
            return
        }

        // --- Standard App Activation Event (if enabled) ---
        if self.isEnabled { // Check general toggle
            if bundleId != lastKnownActiveBundleID { // Avoid duplicates
                RedEyeLogger.info("Application activated: \(appName) (\(bundleId))", category: "AppActivationMonitor")
                let event = RedEyeEvent(
                    eventType: .applicationActivated,
                    sourceApplicationName: appName,
                    sourceBundleIdentifier: bundleId,
                    metadata: ["pid": "\(activatedApp.processIdentifier)"]
                )
                eventBus.publish(event: event)
            }
        }
        lastKnownActiveBundleID = bundleId // Update last known ID regardless of general toggle

        // --- Safari URL Capture PoC (if enabled and Safari is activated) ---
        if self.isEnabledBrowserURLCapture && bundleId == safariBundleID {
            RedEyeLogger.info("Safari activated, attempting to capture URL/Title (PoC).", category: "AppActivationMonitor")
            executeSafariURLTitleScript(appName: appName, bundleId: bundleId)
        }
    }

    // MARK: - Safari URL Capture Helper <<< NEW METHOD
    private func executeSafariURLTitleScript(appName: String, bundleId: String) {
        guard let script = self.appleScriptSafariURLTitle else {
            RedEyeLogger.error("Safari URL AppleScript not compiled.", category: "AppActivationMonitor")
            emitBrowserNavigationError(error: "AppleScript not compiled", appName: appName, bundleId: bundleId)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { // Run script off main thread
            var errorInfo: NSDictionary?
            let resultDescriptor = script.executeAndReturnError(&errorInfo)

            DispatchQueue.main.async { [weak self] in // Switch back to main thread for event emission; capture self weakly here
                guard let self = self else { return } // Ensure self is valid
                if let error = errorInfo {
                    let errorMessage = (error[NSAppleScript.errorAppName] as? String ?? "AppleScript Error") +
                                     ": " + (error[NSAppleScript.errorMessage] as? String ?? "Unknown error") +
                                     " (Code: \(error[NSAppleScript.errorNumber] as? Int ?? 0))"
                    RedEyeLogger.error("Error executing Safari URL AppleScript: \(errorMessage)", category: "AppActivationMonitor")
                    self.emitBrowserNavigationError(error: errorMessage, appName: appName, bundleId: bundleId)
                    
                    // Check for Automation permission denial specifically
                    // Error code -1743 (errAEEventNotPermitted) often indicates Automation permission issue
                    if let errorCode = error[NSAppleScript.errorNumber] as? Int, errorCode == -1743 {
                        RedEyeLogger.error("This may be an Automation permission issue. Please ensure RedEye has permission to control Safari in System Settings > Privacy & Security > Automation.", category: "AppActivationMonitor")
                    }
                    return
                }

                guard let resultString = resultDescriptor.stringValue else {
                    RedEyeLogger.error("Failed to get string result from Safari URL AppleScript.", category: "AppActivationMonitor")
                    self.emitBrowserNavigationError(error: "Invalid or nil result from AppleScript", appName: appName, bundleId: bundleId)
                    return
                }
                
                // Check for our custom error prefix from the script
                if resultString.hasPrefix("error:") {
                    RedEyeLogger.error("Safari URL AppleScript returned an error: \(resultString)", category: "AppActivationMonitor")
                    self.emitBrowserNavigationError(error: resultString, appName: appName, bundleId: bundleId)
                    return
                }

                let parts = resultString.components(separatedBy: "|||")
                guard parts.count == 2 else {
                    RedEyeLogger.error("Safari URL AppleScript returned unexpected format: \(resultString)", category: "AppActivationMonitor")
                    self.emitBrowserNavigationError(error: "Unexpected script result format", appName: appName, bundleId: bundleId)
                    return
                }

                let urlString = parts[0]
                let pageTitle = parts[1]

                RedEyeLogger.info("Safari URL/Title captured: URL='\(urlString)', Title='\(pageTitle)'", category: "AppActivationMonitor")
                
                let metadata: [String: String] = [
                    "browser_url": urlString,
                    "browser_page_title": pageTitle,
                    "trigger": "appActivated"
                ]
                
                let event = RedEyeEvent(
                    eventType: .browserNavigation,
                    sourceApplicationName: appName,
                    sourceBundleIdentifier: bundleId,
                    // contextText: pageTitle, // Or keep contextText nil and use metadata
                    metadata: metadata
                )
                self.eventBus.publish(event: event)
            }
        }
    }
    
    private func emitBrowserNavigationError(error: String, appName: String, bundleId: String) {
        let metadata: [String: String] = [
            "error": error,
            "trigger": "appActivated"
        ]
        let event = RedEyeEvent(
            eventType: .browserNavigation,
            sourceApplicationName: appName,
            sourceBundleIdentifier: bundleId,
            metadata: metadata
        )
        self.eventBus.publish(event: event)
    }
}
