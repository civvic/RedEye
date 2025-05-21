// RedEye/App/AppDelegate.swift

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    private var appCoordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        RedEyeLogger.info("Application starting up...", category: "AppDelegate")

        // 1. Perform initial critical checks like permissions
        _ = self.checkAndRequestAccessibilityPermissions()
        
        // 2. Initialize and start the AppCoordinator
        // This coordinator will now handle the setup of all core services and managers.
        RedEyeLogger.info("Initializing AppCoordinator...", category: "AppDelegate")
        self.appCoordinator = AppCoordinator()
        
        RedEyeLogger.info("Starting services via AppCoordinator...", category: "AppDelegate")
        self.appCoordinator?.start() // AppCoordinator.start() now calls start on all managers
        
        // 3. Setup UI elements like the status bar menu (remains in AppDelegate)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        RedEyeLogger.info("RedEye application finished launching. AppDelegate setup complete.", category: "AppDelegate")
        
        // Global debug logging toggle (can stay here or move to AppCoordinator if preferred)
        #if DEBUG
            print("RedEye Dev Note: Verbose debug logging is ENABLED (DEBUG build).")
        #else
            print("RedEye Info: Verbose debug logging is DISABLED (Release build).")
        #endif
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        RedEyeLogger.info("Application will terminate. Instructing AppCoordinator to stop services...", category: "AppDelegate")
        // Delegate stopping services to the AppCoordinator
        self.appCoordinator?.stop()
        RedEyeLogger.info("AppCoordinator finished stopping services.", category: "AppDelegate")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @discardableResult // Allow ignoring return value
    func checkAndRequestAccessibilityPermissions() -> Bool {
        // Check status first without prompting
        let currentStatus = AXIsProcessTrusted()
        if currentStatus {
            RedEyeLogger.info("Accessibility permissions: Granted.", category: "AppDelegate")
            return true
        } else {
            RedEyeLogger.info("Accessibility permissions: Not granted. Requesting...", category: "AppDelegate")
            // Use prompt option
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if !accessEnabled {
                RedEyeLogger.error("Accessibility permissions still not granted after prompt (or prompt failed). The user may need to grant manually in System Settings.", category: "AppDelegate")
            } else {
                // Note: Even if it returns true here, sometimes a restart is needed for changes to fully apply.
                RedEyeLogger.info("Accessibility permissions prompt acknowledged. Status may require app restart to be fully effective if granted.", category: "AppDelegate")
            }
            return accessEnabled
        }
    }
}
