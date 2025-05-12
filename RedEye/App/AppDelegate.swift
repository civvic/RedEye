//
//  AppDelegate.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/8/25.
//

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    var hotkeyManager: HotkeyManager?
    var eventManager: EventManager?
    var pluginManager: PluginManager?
    var uiManager: UIManager?
    var webSocketServerManager: WebSocketServerManager?
    var inputMonitorManager: InputMonitorManager?
    var appActivationMonitor: AppActivationMonitor?
    var fsEventMonitorManager: FSEventMonitorManager?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions
        let accessibilityGranted = self.checkAndRequestAccessibilityPermissions()
        if !accessibilityGranted {
            // Handle lack of permissions if necessary
        }
        
        // 1. Create PluginManager (scans for plugins)
        self.pluginManager = PluginManager()
        
        // PREP: Initialize WebSocketServerManager first so it can be passed around
        self.webSocketServerManager = WebSocketServerManager() // Initialize WSSM

        // 2. Create EventManager (needs PluginManager for eventual direct invocation, though UI will trigger now)
        //    The EventManager's role in directly triggering plugins might diminish if UI always does it.
        //    For now, it can keep its reference.
        guard let pManager = self.pluginManager else {
            fatalError("CRITICAL ERROR: PluginManager could not be initialized.") // Or handle more gracefully
        }
        self.eventManager = EventManager(webSocketServerManager: self.webSocketServerManager)

        // 3. Create UIManager (needs PluginManager to tell it what to run)
        self.uiManager = UIManager(pluginManager: pManager)
        
        // 4. Create HotkeyManager (needs EventManager for logging, and UIManager for showing UI)
        guard let evtManager = self.eventManager, let uiMgr = self.uiManager else {
            fatalError("CRITICAL ERROR: EventManager or UIManager could not be initialized.")
        }
        self.hotkeyManager = HotkeyManager(eventManager: evtManager, uiManager: uiMgr)

        // 5. Initialize and Start WebSocketServerManager
        self.webSocketServerManager?.startServer() // Start the server

        // 6. Initialize and Start InputMonitorManager
        self.inputMonitorManager = InputMonitorManager()
        self.inputMonitorManager?.delegate = self.hotkeyManager
        self.inputMonitorManager?.startMonitoring()

        // 7. Initialize and Start AppActivationMonitor
        if let evtMgr = self.eventManager { // Ensure eventManager is available
            self.appActivationMonitor = AppActivationMonitor(eventManager: evtMgr)
            self.appActivationMonitor?.startMonitoring()
        } else {
            RedEyeLogger.fault("EventManager not available for AppActivationMonitor. App activation events will not be monitored.", category: "AppDelegate")
        }

        // 8. Initialize and Start FSEventMonitorManager
        if let evtMgr = self.eventManager { // Ensure eventManager is available and can act as delegate
            self.fsEventMonitorManager = FSEventMonitorManager(delegate: evtMgr) // Pass EventManager as delegate
            self.fsEventMonitorManager?.startMonitoring() // Start monitoring default paths
        } else {
            RedEyeLogger.fault("EventManager not available for FSEventMonitorManager. File system events will not be monitored.", category: "AppDelegate")
        }

        // --- Status item setup code ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        RedEyeLogger.info("RedEye application finished launching. Status item should be visible.", category: "AppDelegate")

        // Enable verbose logging for DEBUG builds
        #if DEBUG
        RedEyeLogger.isVerboseLoggingEnabled = true
        // Using a standard print here is acceptable as it's a one-time developer note during startup
        print("RedEye Dev Note: Verbose debug logging is ENABLED (DEBUG build).")
        RedEyeLogger.debug("This is a test debug message from AppDelegate.", category: "AppDelegate")
        #else
        // Using a standard print here for a release build note is also fine if desired
        print("RedEye Info: Verbose debug logging is DISABLED (Release build).")
        #endif
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        RedEyeLogger.info("RedEye application will terminate. Stopping services...", category: "AppDelegate")
        webSocketServerManager?.stopServer()
        inputMonitorManager?.stopMonitoring()
        appActivationMonitor?.stopMonitoring()
        fsEventMonitorManager?.stopMonitoring()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func checkAndRequestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if accessEnabled {
            RedEyeLogger.info("Accessibility permissions: Granted.", category: "AppDelegate")
            return true
        } else {
            RedEyeLogger.error("Accessibility permissions: Not granted. The user may have been prompted.", category: "AppDelegate")
            RedEyeLogger.error("Please grant Accessibility access to RedEye in System Settings > Privacy & Security > Accessibility, then relaunch the app if features aren't working.", category: "AppDelegate")
            // For this step, we rely on the system prompt. If it fails or the user denies,
            // they'll need to go to System Settings manually.
            return false
        }
    }
    
}
