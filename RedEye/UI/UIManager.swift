//
//  UIManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/10/25.
//

import Cocoa

class UIManager: NSObject, PluginActionsPanelDelegate, PluginActionsViewControllerDelegate {

    private var pluginActionsPanel: PluginActionsPanel?
    private var pluginActionsViewController: PluginActionsViewController?
    
    // To store the text that the panel is currently for
    private var currentContextTextForPanel: String?

    // Keep a reference to PluginManager to execute plugins
    private let pluginManager: PluginManager

    init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager
        super.init()
    }

    // MARK: - Panel Management

    func showPluginActionsPanel(near point: NSPoint, withContextText text: String) {
        // Store the context text
        self.currentContextTextForPanel = text

        if pluginActionsPanel == nil {
            // Create the panel and its view controller
            // Determine a reasonable initial size for the panel based on its content
            // For now, a fixed size. Could be dynamic later.
            let panelWidth: CGFloat = 120
            let panelHeight: CGFloat = 40
            let panelRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

            pluginActionsViewController = PluginActionsViewController()
            pluginActionsViewController?.delegate = self
            
            // Initialize the panel. Note: contentRect here is for the panel's frame,
            // its content view will be the VC's view.
            pluginActionsPanel = PluginActionsPanel(contentRect: panelRect,
                                                   backing: .buffered,
                                                   defer: false)
            pluginActionsPanel?.panelDelegate = self
            pluginActionsPanel?.contentViewController = pluginActionsViewController
            
            // Set the panel's frame size explicitly after assigning content VC,
            // as the VC's view frame might influence it.
             pluginActionsPanel?.setFrame(panelRect, display: false)
        }
        
        // Update the context text in the view controller
        pluginActionsViewController?.setContext(text: text)

        // Calculate position: centered above the point, with a small offset
        // The 'point' is usually the mouse cursor's location.
        // We need to convert it from screen coordinates if necessary.
        // For now, assuming 'point' is in screen coordinates.
        var panelX = point.x - (pluginActionsPanel?.frame.width ?? 0) / 2
        var panelY = point.y + 10 // A small offset above the cursor/selection point

        // Ensure it fits on screen (basic boundary check)
        if let screenFrame = NSScreen.main?.visibleFrame {
            if panelX < screenFrame.minX { panelX = screenFrame.minX }
            if (panelX + (pluginActionsPanel?.frame.width ?? 0)) > screenFrame.maxX {
                panelX = screenFrame.maxX - (pluginActionsPanel?.frame.width ?? 0)
            }
            if panelY < screenFrame.minY { panelY = screenFrame.minY } // Should not happen if above point
            if (panelY + (pluginActionsPanel?.frame.height ?? 0)) > screenFrame.maxY {
                // If it's too high (e.g. cursor at top of screen), place it below the point
                panelY = point.y - (pluginActionsPanel?.frame.height ?? 0) - 10
            }
        }
        
        pluginActionsPanel?.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        pluginActionsPanel?.orderFrontRegardless() // Show the panel
        
        print("UIManager: Showing plugin actions panel.")
    }

    func hidePluginActionsPanel() {
        pluginActionsPanel?.orderOut(nil) // Hide the panel
        self.currentContextTextForPanel = nil // Clear the stored text
        print("UIManager: Hiding plugin actions panel.")
    }

    // MARK: - PluginActionsPanelDelegate

    func dismissPanel() {
        // Called by the panel itself (e.g., on Escape if it handles cancelOperation)
        hidePluginActionsPanel()
    }

    // MARK: - PluginActionsViewControllerDelegate

    func didClickPluginActionButton(sender: NSButton, contextText: String?) {
        print("UIManager: Plugin action button clicked. Context: \(contextText ?? "nil")")
        if let text = contextText, !text.isEmpty {
            pluginManager.invokePlugins(withText: text)
        } else {
            print("UIManager: No context text to process for plugin.")
        }
        hidePluginActionsPanel() // Hide panel after action
    }
}
