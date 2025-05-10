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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions
        let accessibilityGranted = self.checkAndRequestAccessibilityPermissions()
        if !accessibilityGranted {
            // Handle lack of permissions if necessary
        }
        
        // 1. Create the PluginManager
        self.pluginManager = PluginManager()

        // 2. Create the EventManager and pass the PluginManager to it
        if let pManager = self.pluginManager {
            self.eventManager = EventManager(pluginManager: pManager)
        } else {
            // This should not happen if PluginManager() initializes
            print("CRITICAL ERROR: PluginManager could not be initialized.")
            // Fallback: Create EventManager without a PluginManager if absolutely necessary
            // self.eventManager = EventManager(pluginManager: nil) // Would require EventManager.pluginManager to be optional
            // Or terminate/disable features
        }

        // 3. Create HotkeyManager and pass the EventManager to it
        if let evtManager = self.eventManager {
            self.hotkeyManager = HotkeyManager(eventManager: evtManager)
        } else {
            print("CRITICAL ERROR: EventManager could not be initialized.")
            // Handle
        }
        
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
