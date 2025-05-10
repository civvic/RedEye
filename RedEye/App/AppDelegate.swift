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
    var pluginManager: PluginManager? // Add property for PluginManager
    var uiManager: UIManager? // Add property for UIManager

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions
        let accessibilityGranted = self.checkAndRequestAccessibilityPermissions()
        if !accessibilityGranted {
            // Handle lack of permissions if necessary
        }
        
        // 1. Create PluginManager (scans for plugins)
        self.pluginManager = PluginManager()
        
        // 2. Create EventManager (needs PluginManager for eventual direct invocation, though UI will trigger now)
        //    The EventManager's role in directly triggering plugins might diminish if UI always does it.
        //    For now, it can keep its reference.
        guard let pManager = self.pluginManager else {
            fatalError("CRITICAL ERROR: PluginManager could not be initialized.") // Or handle more gracefully
        }
        self.eventManager = EventManager()// pluginManager: pManager)

        // 3. Create UIManager (needs PluginManager to tell it what to run)
        self.uiManager = UIManager(pluginManager: pManager)
        
        // 4. Create HotkeyManager (needs EventManager for logging, and UIManager for showing UI)
        guard let evtManager = self.eventManager, let uiMgr = self.uiManager else {
            fatalError("CRITICAL ERROR: EventManager or UIManager could not be initialized.")
        }
        self.hotkeyManager = HotkeyManager(eventManager: evtManager, uiManager: uiMgr)

        // --- Status item setup code ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        print("RedEye started. Status item should be visible.")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Cleanup if needed
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func checkAndRequestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if accessEnabled {
            print("Accessibility permissions: Granted.")
            return true
        } else {
            print("Accessibility permissions: Not granted. The user may have been prompted.")
            print("Please grant Accessibility access to RedEye in System Settings > Privacy & Security > Accessibility, then relaunch the app if features aren't working.")
            // For this step, we rely on the system prompt. If it fails or the user denies,
            // they'll need to go to System Settings manually.
            return false
        }
    }
    
}
