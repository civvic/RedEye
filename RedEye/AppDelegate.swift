//
//  AppDelegate.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/8/25.
//

import Cocoa

// @main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

