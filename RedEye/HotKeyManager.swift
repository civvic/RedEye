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

    init() {
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
        print("HotkeyManager: ⌘⇧C pressed! (via KeyboardShortcuts)")
        print("HotkeyManager: ⌘⇧C pressed! Attempting to capture selected text...")

        // 1. Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("Error: Could not determine the frontmost application.")
            return
        }

        // Get the process identifier (PID) of the frontmost application
        let pid = frontmostApp.processIdentifier
        
        // 2. Create an AXUIElement for the frontmost application
        let appElement = AXUIElementCreateApplication(pid)

        // 3. Get the focused UI element from the application element
        var focusedUIElement: AnyObject? // Needs to be AnyObject for AXUIElementCopyAttributeValue
        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)

        if focusError != .success {
            print("Error getting focused UI element: \(focusError.rawValue)")
            // Common errors:
            // -1 (errAPINotEnabled): Accessibility API is disabled (should be caught by our earlier check, but good to note)
            // -25204 (errAXAPIDisabled) or -25212 (errAXPrivilegeNotGranted): More specific accessibility errors
            // Other errors might mean the app doesn't support this attribute or is slow to respond.
            return
        }

        guard let focusedElement = focusedUIElement else {
            print("Error: Focused UI element is nil, even though no direct error was reported.")
            return
        }

        // 4. Get the selected text from the focused UI element
        var selectedTextValue: AnyObject?
        let selectedTextError = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
                                                            // Cast to AXUIElement is safe here if focusError was .success and focusedElement is not nil.

        if selectedTextError == .success {
            if let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
                print("Selected text: \"\(selectedText)\"")
            } else if selectedTextValue == nil || (selectedTextValue as? String)?.isEmpty ?? true {
                // This case handles when the attribute exists but there's no text selected (e.g., empty string or nil value)
                print("No text selected in the focused element, or element does not support kAXSelectedTextAttribute directly with content.")
            } else {
                // This case handles if selectedTextValue is something other than a String (e.g. NSAccessibilityNullValue)
                 print("Focused element has kAXSelectedTextAttribute, but the value is not a non-empty string (possibly NSAccessibilityNullValue or an empty string). Value: \(String(describing: selectedTextValue))")
            }
        } else {
            // If kAXSelectedTextAttribute is not available or an error occurs
            print("Could not get selected text (focused element might not support it or no text is selected). Error: \(selectedTextError.rawValue)")
            // Common errors:
            // -25205 (errAXAttributeUnsupported): The element doesn't have a 'selected text' attribute.
            // You might also want to try kAXValueAttribute for some elements if kAXSelectedTextAttribute fails,
            // as some simple text fields might put their entire content in kAXValueAttribute if nothing specific is "selected".
            // However, for "selected text", kAXSelectedTextAttribute is the primary one.
        }
    }

    // If you need to explicitly unregister (though KeyboardShortcuts often handles this well on deinit or app quit)
    // or manage them more dynamically, you might add methods here.
    // For this library, often just setting up the listener is enough, and it cleans up.
    // We can revisit if specific cleanup is needed beyond what the library provides.
}
