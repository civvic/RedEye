// RedEye/Managers/AppActivationMonitor.swift

import AppKit
import Foundation // For NSAppleScript

class AppActivationMonitor: BaseMonitorManager {
    private var lastKnownActiveBundleID: String? // To avoid duplicate events if possible
    private var notificationObserver: NSObjectProtocol? // Store the observer to remove it correctly

    private let safariBundleID = "com.apple.Safari"
    private var appleScriptSafariURLTitle: NSAppleScript?

    override var logCategory: String { "AppActivationMonitor" }

    init(eventBus: EventBus, configManager: ConfigurationManaging) {
        super.init(monitorType: .appActivationMonitor, eventBus: eventBus, configManager: configManager)

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
            RedEyeLogger.error("Failed to initialize AppleScript for Safari URL capture.", category: self.logCategory)
        }
        RedEyeLogger.info("AppActivationMonitor specific initialization complete.", category: self.logCategory)
    }

    override func startMonitoring() -> Bool {
        guard notificationObserver == nil else {
             RedEyeLogger.info("Monitoring is already active.", category: self.logCategory)
            return true // Considered successfully "started" if already active
        }

        let browserURLCaptureEnabled = self.currentMonitorConfig?.parameters?["enableBrowserURLCapture"]?.boolValue() ?? false
        if browserURLCaptureEnabled {
            RedEyeLogger.info("Safari URL capture is ENABLED via configuration parameters.", category: self.logCategory)
        } else {
            RedEyeLogger.info("Safari URL capture is DISABLED via configuration parameters.", category: self.logCategory)
        }

        RedEyeLogger.info("Starting application activation NSWorkspace notifications.", category: self.logCategory)
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] notification in
                self?.handleAppActivation(notification)
        }
        if notificationObserver != nil {
            RedEyeLogger.info("Successfully started AppActivationMonitor.", category: self.logCategory)
            return true
        } else {
            RedEyeLogger.error("Failed to create NSWorkspace notification observer.", category: self.logCategory)
            return false
        }
    }

    override func stopMonitoring() {
        if let observer = notificationObserver {
            RedEyeLogger.info("Stopping application activation NSWorkspace notifications.", category: self.logCategory)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            notificationObserver = nil
        } else {
             RedEyeLogger.debug("Attempted to stop, but NSWorkspace observer was not active for AppActivationMonitor.", category: self.logCategory)
        }
    }

    private func handleAppActivation(_ notification: Notification) {
        guard self.isCurrentlyActive else {
            RedEyeLogger.info("handleAppActivation called but monitor is not currently active.", category: logCategory)
            return
        }

        guard let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            RedEyeLogger.error("Could not get NSRunningApplication from didActivateApplicationNotification.", category: logCategory)
            return
        }

        guard let appName = activatedApp.localizedName, let bundleId = activatedApp.bundleIdentifier else {
            RedEyeLogger.error("Newly activated application is missing name or bundle ID. Name: \(activatedApp.localizedName ?? "N/A"), BundleID: \(activatedApp.bundleIdentifier ?? "N/A")", category: logCategory)
            return
        }

        // --- Standard App Activation Event (if enabled) ---
        if bundleId != lastKnownActiveBundleID {
            RedEyeLogger.info("Application activated: \(appName) (\(bundleId))", category: logCategory)
            let event = RedEyeEvent(
                eventType: .applicationActivated,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["pid": "\(activatedApp.processIdentifier)"]
            )
            self.eventBus?.publish(event: event)
        }
        lastKnownActiveBundleID = bundleId

        // --- Safari URL Capture PoC (if enabled and Safari is activated) ---
        let browserURLCaptureEnabled = self.currentMonitorConfig?.parameters?["enableBrowserURLCapture"]?.boolValue() ?? false
        if browserURLCaptureEnabled && bundleId == safariBundleID {
            RedEyeLogger.info("Safari activated, attempting to capture URL/Title (PoC as per config).", category: logCategory)
            executeSafariURLTitleScript(appName: appName, bundleId: bundleId)
        }
    }

    private func executeSafariURLTitleScript(appName: String, bundleId: String) {
        guard let script = self.appleScriptSafariURLTitle else {
            RedEyeLogger.error("Safari URL AppleScript not compiled.", category: logCategory)
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
                self.eventBus?.publish(event: event)
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
        self.eventBus?.publish(event: event)
    }
}
