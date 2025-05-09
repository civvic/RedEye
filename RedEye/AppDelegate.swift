//
//  AppDelegate.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/8/25.
//

import Cocoa
import ApplicationServices
//import Carbon.HIToolbox // For Carbon Event APIs like RegisterEventHotKey

// @main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
//    var eventMonitor: Any? // We might use this later or for a different approach, but for Carbon hotkeys it's not directly used for the handler itself.
//    var textSelectionHotKeyRef: EventHotKeyRef? // To store the reference to our registered hotkey

    var hotkeyManager: HotkeyManager? // Add a property for our manager

    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions
        let accessibilityGranted = self.checkAndRequestAccessibilityPermissions()

        if !accessibilityGranted {
            // For now, we just log. In a more complex app, you might disable UI elements
            // or show a more persistent reminder.
            // The message is already printed within checkAndRequestAccessibilityPermissions.
        }

//        // Register the hotkey
//        registerTextSelectionHotkey()
        // Initialize and retain the HotkeyManager
        hotkeyManager = HotkeyManager() // This will set up the listeners


        // 1. Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // 2. Configure the status item's button
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
            // Or, for text: button.title = "R"
        }

        // 3. Create a menu
        let menu = NSMenu()

        // 4. Add a "Quit" menu item
        // The 'action' is #selector(NSApplication.terminate(_:)) which tells the app to quit.
        // 'keyEquivalent' is "q" so the user can press Command-Q (though this is often handled at app level).
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // 5. Assign the menu to the status item
        statusItem?.menu = menu
        
        // 6. Log to console
        print("RedEye started. Status item should be visible.")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
//        // Unregister the hotkey when the app quits
//        unregisterTextSelectionHotkey()
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func checkAndRequestAccessibilityPermissions() -> Bool {
        // Define the options for the trusted check.
        // Using kAXTrustedCheckOptionPrompt effectively asks the system to prompt the user
        // if the application is not yet trusted.
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


    // --- Add the new Hotkey methods below ---

//    func registerTextSelectionHotkey() {
//        // 1. Define the hotkey ID (can be anything unique within your app)
//        var hotKeyID = EventHotKeyID()
//        hotKeyID.signature = FourCharCode(string: "hkid") // A 4-character code for the signature
//        hotKeyID.id = 1                                   // A unique ID for this hotkey
//
//        // 2. Define the key combination
//        // kVK_ANSI_C is the virtual key code for 'C'
//        // cmdKey + shiftKey are modifier flags
//        let keyCode = UInt32(kVK_ANSI_C)
//        let modifiers = UInt32(cmdKey | shiftKey) // cmdKey, shiftKey are defined in Carbon.HIToolbox
//
//        // 3. Get the event dispatcher queue for handling the hotkey event
//        // We'll use the main queue for simplicity here.
//        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
//
//        // 4. Install the event handler for the hotkey
//        // This will call our global function `hotKeyHandler` when the hotkey is pressed.
//        InstallEventHandler(GetApplicationEventTarget(), {
//            (nextHanlder, event, userData) -> OSStatus in
//            // This is a C-style callback. We need to bridge to our Swift instance method.
//            // Get the AppDelegate instance from userData.
//            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
//            appDelegate.handleTextSelectionHotkey() // Call our Swift method
//            return noErr // Indicate we've handled the event
//        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
//
//
//        // 5. Register the hotkey
//        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
//                                         GetApplicationEventTarget(), 0, &textSelectionHotKeyRef)
//
//        if status == noErr {
//            print("Hotkey ⌘⇧C registered successfully.")
//        } else {
//            print("Failed to register hotkey ⌘⇧C, error: \(status)")
//        }
//    }
//
//    func unregisterTextSelectionHotkey() {
//        if let hotKeyRef = textSelectionHotKeyRef {
//            UnregisterEventHotKey(hotKeyRef)
//            self.textSelectionHotKeyRef = nil // Clear the reference
//            print("Hotkey ⌘⇧C unregistered.")
//        }
//    }
//
//    // This is the Swift method that will be called by the C callback
//    @objc func handleTextSelectionHotkey() {
//        print("Hotkey ⌘⇧C pressed!")
//        // TODO: Implement text selection capture here (Phase 3)
//    }
}


// Helper to convert a String to FourCharCode (OSType)
// This is needed for the hotKeyID.signature
//func FourCharCode(string: String) -> FourCharCode {
//    return string.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
//}
