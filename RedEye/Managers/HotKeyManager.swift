//
//  HotKeyManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/8/25.
//

import Foundation
import AppKit // For NSWorkspace and accessibility elements
import KeyboardShortcuts // Import the library

// Define a namespace for our app's shortcuts
// This helps avoid collisions if other apps use the same library
extension KeyboardShortcuts.Name {
    static let captureSelectedText = Self("captureSelectedText", default: .init(.c, modifiers: [.command, .shift]))
}

class HotkeyManager {

    private let eventManager: EventManager // Add property for EventManager
    private let uiManager: UIManager // Add property for UIManager

    // Modify init to accept EventManager and UIManager
    init(eventManager: EventManager, uiManager: UIManager) {
        self.eventManager = eventManager
        self.uiManager = uiManager // Store the UIManager
        setupHotkeyListeners()
    }

    private func setupHotkeyListeners() {
        KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
            self?.handleCaptureSelectedTextHotkey()
        }
        RedEyeLogger.info("Listener for ⌘⇧C (captureSelectedText) is set up.", category: "HotKeyManager")
    }

    private func handleCaptureSelectedTextHotkey() {
        RedEyeLogger.info("⌘⇧C pressed! Attempting to capture selected text...", category: "HotKeyManager")

        // Get mouse location *before* any blocking accessibility calls
        let mouseLocation = NSEvent.mouseLocation // This is in screen coordinates

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            // ... (error handling as before, create error event, emit via eventManager) ...
            let errorEvent = RedEyeEvent(eventType: .textSelection, metadata: ["error": "Could not determine frontmost app"])
            eventManager.emit(event: errorEvent)
            return
        }
        // ... (pid, appName, bundleId, appElement, focusedUIElement logic as before) ...
        let pid = frontmostApp.processIdentifier
        let appName = frontmostApp.localizedName
        let bundleId = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedUIElement: AnyObject?

        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)

        if focusError != .success {
            // ... (create error event with appName, bundleId, metadata, emit via eventManager) ...
            let errorEvent = RedEyeEvent(eventType: .textSelection, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, metadata: ["error": "Error getting focused UI: \(focusError.rawValue)"])
            eventManager.emit(event: errorEvent)
            return
        }
        // ... (guard focusedElement else, create error event, emit) ...
        guard let focusedElement = focusedUIElement else {
            let errorEvent = RedEyeEvent(eventType: .textSelection, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, metadata: ["error": "Focused UI element nil."])
            eventManager.emit(event: errorEvent)
            return
        }

        var selectedTextValue: AnyObject?
        let selectedTextError = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        let capturedText = (selectedTextError == .success) ? (selectedTextValue as? String) : nil
        
        // Always create and log the RedEyeEvent
        let event = RedEyeEvent(
            eventType: .textSelection,
            sourceApplicationName: appName,
            sourceBundleIdentifier: bundleId,
            contextText: capturedText?.isEmpty == false ? capturedText : nil,
            metadata: selectedTextError != .success ? ["error": "AXSelectedTextError: \(selectedTextError.rawValue)"] : nil
        )
        eventManager.emit(event: event) // Log the event (JSON output)

        // Now, if text was successfully captured (or even if not, UI might still show),
        // show the plugin actions panel.
        // We'll pass the capturedText (which can be nil). UIManager can decide what to do.
        if let textToShowInPanel = capturedText, !textToShowInPanel.isEmpty {
            RedEyeLogger.info("Captured text \"\(textToShowInPanel)\". Requesting UI panel.", category: "HotKeyManager")
            uiManager.showPluginActionsPanel(near: mouseLocation, withContextText: textToShowInPanel)
        } else {
            // Decide if you want to show the panel even if no text is selected.
            // For PopClip, it usually only appears if there's a selection.
            RedEyeLogger.error("No text selected or error capturing. Not showing UI panel.", category: "HotKeyManager")
            // Or, to always show it and let UIManager/PluginActionsViewController decide:
            // uiManager.showPluginActionsPanel(near: mouseLocation, withContextText: nil)
        }
    }
    
    // If you need to explicitly unregister (though KeyboardShortcuts often handles this well on deinit or app quit)
    // or manage them more dynamically, you might add methods here.
    // For this library, often just setting up the listener is enough, and it cleans up.
    // We can revisit if specific cleanup is needed beyond what the library provides.
}
