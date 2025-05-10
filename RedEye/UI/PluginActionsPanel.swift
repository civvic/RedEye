//
//  PluginActionsPanel.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/10/25.
//

import Cocoa

class PluginActionsPanel: NSPanel {

    // We'll store a reference to a UIManager or a delegate to handle dismissal
    // For now, we can make it weak to avoid retain cycles if the UIManager holds the panel.
    weak var panelDelegate: PluginActionsPanelDelegate?

    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        // Initialize with basic settings for a borderless, floating panel
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel], // Borderless and non-activating
                   backing: backing,
                   defer: flag)

        self.isFloatingPanel = true             // Makes the panel float above normal windows
        self.level = .popUpMenu                // High window level, but below menus if needed. .floating is also common.
        self.collectionBehavior = .canJoinAllSpaces // Ensures panel can appear on all Mission Control spaces
        self.hidesOnDeactivate = false          // We will control when it hides
        self.isOpaque = false                   // Allows for transparency if the background is clear
        self.backgroundColor = NSColor.clear    // Make window background clear if view has its own background
        self.hasShadow = true                   // Nice to have a shadow, can be customized
        
        // To make it dismissable with the Escape key
        // Note: This might not work immediately if the panel doesn't become key.
        // We might need a more robust way to handle Escape if it's not the key window.
    }

    // Override to handle Escape key if the panel is key.
    // If not key, this won't be called. We might need a global event monitor for Escape.
    override func cancelOperation(_ sender: Any?) {
        print("PluginActionsPanel: cancelOperation called (Escape pressed if key window)")
        panelDelegate?.dismissPanel()
    }
    
    // To ensure the panel can become the key window when needed (e.g., to receive keyboard events like Escape)
    // However, for a PopClip-like UI, we often want it *not* to become key to avoid stealing focus.
    // This is a tricky balance. `.nonactivatingPanel` helps with not stealing main focus.
    override var canBecomeKey: Bool {
        return true // Or false, depending on how we want to handle keyboard input like Escape
    }

    // If you want it to *not* become main, which is typical for such popups
    override var canBecomeMain: Bool {
        return false
    }
}

// Protocol for the panel to communicate back (e.g., for dismissal)
protocol PluginActionsPanelDelegate: AnyObject {
    func dismissPanel()
}
