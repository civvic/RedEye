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

    // Modify init to accept an EventManager
    init(eventManager: EventManager) {
        self.eventManager = eventManager
        setupHotkeyListeners()
    }

    private func setupHotkeyListeners() {
        KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
            // The [weak self] is important to avoid retain cycles if 'self' is used more extensively inside.
            // For a simple print, it's less critical but good practice.
            self?.handleCaptureSelectedTextHotkey()
        }
        
        print("HotkeyManager: Listener for ⌘⇧C (captureSelectedText) is set up.")
    }

    private func handleCaptureSelectedTextHotkey() {
        print("HotkeyManager: ⌘⇧C pressed! Attempting to capture selected text...")

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("Error: Could not determine the frontmost application.")
            // Optionally, emit an error event here if desired
            // let errorEvent = RedEyeEvent(eventType: .textSelection, metadata: ["error": "Could not determine frontmost app"])
            // eventManager.emit(event: errorEvent)
            return
        }

        let pid = frontmostApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedUIElement: AnyObject?
        
        // It's good practice to get app name and bundle ID here as well
        let appName = frontmostApp.localizedName
        let bundleId = frontmostApp.bundleIdentifier

        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)

        if focusError != .success {
            print("Error getting focused UI element: \(focusError.rawValue)")
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Error getting focused UI element: \(focusError.rawValue)"]
            )
            eventManager.emit(event: errorEvent)
            return
        }

        guard let focusedElement = focusedUIElement else {
            print("Error: Focused UI element is nil.")
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Focused UI element was nil after successful AX query."]
            )
            eventManager.emit(event: errorEvent)
            return
        }

        var selectedTextValue: AnyObject?
        let selectedTextError = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        if selectedTextError == .success {
            let capturedText = selectedTextValue as? String // Can be nil or empty
            
            let event = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                contextText: capturedText?.isEmpty == false ? capturedText : nil // Store nil if empty for cleaner JSON
            )
            eventManager.emit(event: event)
            
            // For console feedback during dev, we can still print the direct outcome
            if let text = capturedText, !text.isEmpty {
                 print("Selected text captured: \"\(text)\"")
            } else {
                 print("No text selected or focused element provided no text.")
            }

        } else {
            print("Could not get selected text. Error: \(selectedTextError.rawValue)")
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Could not get selected text from focused element: \(selectedTextError.rawValue)"]
            )
            eventManager.emit(event: errorEvent)
        }
    }
    
    // If you need to explicitly unregister (though KeyboardShortcuts often handles this well on deinit or app quit)
    // or manage them more dynamically, you might add methods here.
    // For this library, often just setting up the listener is enough, and it cleans up.
    // We can revisit if specific cleanup is needed beyond what the library provides.
}
