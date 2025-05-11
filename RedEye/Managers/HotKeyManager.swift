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

class HotkeyManager: InputMonitorManagerDelegate {

    private let eventManager: EventManager
    private let uiManager: UIManager
    private var lastMouseSelectedText: String? // <--- ADD THIS to store last mouse-captured text

    // Modify init to accept EventManager and UIManager
    init(eventManager: EventManager, uiManager: UIManager) {
        self.eventManager = eventManager
        self.uiManager = uiManager // Store the UIManager
        setupHotkeyListeners()
    }

    private func setupHotkeyListeners() {
        KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
            self?.handleTextCaptureTrigger(isHotkey: true, mousePositionForUI: NSEvent.mouseLocation)
        }
        RedEyeLogger.info("Listener for ⌘⇧C (captureSelectedText) is set up.", category: "HotKeyManager")
    }

    // Renamed and generalized original hotkey handler
    private func handleTextCaptureTrigger(isHotkey: Bool, mousePositionForUI: NSPoint) {
        let triggerType = isHotkey ? "hotkey (⌘⇧C)" : "mouse_selection"
//        RedEyeLogger.info("Attempting to capture selected text (Trigger: \(triggerType))...", category: "HotKeyManager")

        // --- Accessibility & Text Fetching Logic (largely the same) ---
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            // ... (error handling for no frontmost app, include triggerType in metadata) ...
            RedEyeLogger.error("Could not determine frontmost app. (Trigger: \(triggerType))", category: "HotKeyManager")
            let errorEvent = RedEyeEvent(eventType: .textSelection, metadata: ["error": "Could not determine frontmost app", "trigger": triggerType])
            eventManager.emit(event: errorEvent)
            return
        }

        let pid = frontmostApp.processIdentifier
        let appName = frontmostApp.localizedName
        let bundleId = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedUIElement: AnyObject?

        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)

        if focusError != .success {
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Error getting focused UI: \(focusError.rawValue)", "trigger": triggerType]
            )
            eventManager.emit(event: errorEvent)
            return
        }
        
        guard let focusedElement = focusedUIElement else {
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Focused UI element nil.", "trigger": triggerType]
            )
            eventManager.emit(event: errorEvent)
            return
        }

        var selectedTextValue: AnyObject?
        let selectedTextError = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        let capturedText = (selectedTextError == .success) ? (selectedTextValue as? String) : nil

        // --- Heuristic for mouse selection: Only proceed if text is non-empty AND different from last ---
        if !isHotkey { // Apply this heuristic only for mouse-triggered selections
            if capturedText == nil || capturedText!.isEmpty {
                RedEyeLogger.info("Mouse selection resulted in empty text. Not processing further. Last mouse selection: \"\(self.lastMouseSelectedText ?? "nil")\"", category: "HotKeyManager")
                // Optionally, clear lastMouseSelectedText if current selection is empty,
                // so a subsequent empty selection doesn't get blocked by a previous non-empty one.
                // However, if it's truly empty, it won't match a previous non-empty one anyway.
                // self.lastMouseSelectedText = nil // Or set to capturedText which is nil/empty
                return // Stop processing for this mouse event
            }
            if capturedText == self.lastMouseSelectedText {
                RedEyeLogger.info("Mouse selected text \"\(capturedText!)\" is the same as the last. Not processing further.", category: "HotKeyManager")
                return // Stop processing for this mouse event
            }
            // If different and non-empty, update lastMouseSelectedText for the next mouse event
            self.lastMouseSelectedText = capturedText
            RedEyeLogger.info("New mouse selection: \"\(capturedText!)\". Previous: \"\(self.lastMouseSelectedText ?? "nil")\" (before update). Processing event.", category: "HotKeyManager")
        } else {
            // For hotkey, always clear any "last mouse selected text" so it doesn't interfere
            // and so that a subsequent mouse selection isn't incorrectly blocked.
            self.lastMouseSelectedText = nil
            RedEyeLogger.info("Hotkey trigger. Processing event for captured text: \"\(capturedText ?? "nil")\"", category: "HotKeyManager")
        }
        // --- End Heuristic ---
        
        // Log the attempt *after* basic heuristics, and only if we are proceeding
        RedEyeLogger.info("Processing text capture (Trigger: \(triggerType), Text: \"\(capturedText ?? "nil")\")...", category: "HotKeyManager")

        var metadata: [String: String] = ["trigger": triggerType]
        if selectedTextError != .success {
            metadata["error"] = "AXSelectedTextError: \(selectedTextError.rawValue)"
        }
        
        // For mouse selections, we've already confirmed capturedText is non-nil and non-empty if we reach here.
        // For hotkeys, capturedText can still be nil/empty.
        let event = RedEyeEvent(
            eventType: .textSelection,
            sourceApplicationName: appName,
            sourceBundleIdentifier: bundleId,
            contextText: capturedText, // It's already nil if empty or error, or non-empty here for mouse
            metadata: metadata
        )
        eventManager.emit(event: event)

        // Show UI panel only if text is actually captured and non-empty
        if let textToShowInPanel = capturedText, !textToShowInPanel.isEmpty {
            RedEyeLogger.info("Captured text \"\(textToShowInPanel)\". Requesting UI panel at \(mousePositionForUI).", category: "HotKeyManager")
            uiManager.showPluginActionsPanel(near: mousePositionForUI, withContextText: textToShowInPanel)
        } else {
            // This branch will now typically only be hit for hotkey trigger with no selection,
            // or if there was an AX error. Mouse selections with empty text are returned early.
            RedEyeLogger.info("No text selected or error capturing. Not showing UI panel. (Trigger: \(triggerType))", category: "HotKeyManager")
        }
    }

    // MARK: - InputMonitorManagerDelegate Implementation
    func mouseUpAfterPotentialSelection(at screenPoint: NSPoint) {
        RedEyeLogger.info("HotkeyManager received mouseUpAfterPotentialSelection at \(screenPoint)", category: "HotKeyManager")
        // Call the common text capture logic. The mousePositionForUI is the 'screenPoint' from the mouse up.
        handleTextCaptureTrigger(isHotkey: false, mousePositionForUI: screenPoint)
    }
}
