// RedEye/Managers/HotkeyManager.swift

import Foundation
import AppKit // For NSWorkspace and accessibility elements
import KeyboardShortcuts // Import the library

// Define a namespace for our app's shortcuts
// This helps avoid collisions if other apps use the same library
extension KeyboardShortcuts.Name {
    static let captureSelectedText = Self("captureSelectedText", default: .init(.c, modifiers: [.command, .shift]))
}

class HotkeyManager: InputMonitorManagerDelegate {

    private let eventBus: EventBus
    private let uiManager: UIManager
    private var lastMouseSelectedText: String?

    // MARK: - Developer Toggle for UI Panel
    var isHotkeyUiEnabled: Bool = true // Default to true, can be set by AppDelegate
    
    init(eventBus: EventBus, uiManager: UIManager) {
        self.uiManager = uiManager
        self.eventBus = eventBus
        setupHotkeyListeners()
    }

    private func setupHotkeyListeners() {
        KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
            self?.handleTextCaptureTrigger(isHotkey: true, mousePositionForUI: NSEvent.mouseLocation)
        }
        RedEyeLogger.info("Listener for ⌘⇧C (captureSelectedText) is set up.", category: "HotKeyManager")
    }

    private func handleTextCaptureTrigger(isHotkey: Bool, mousePositionForUI: NSPoint) {
        let triggerType = isHotkey ? "hotkey (⌘⇧C)" : "mouse_selection"

        // --- Accessibility & Text Fetching Logic (largely the same) ---
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            // ... (error handling for no frontmost app, include triggerType in metadata) ...
            RedEyeLogger.error("Could not determine frontmost app. (Trigger: \(triggerType))", category: "HotKeyManager")
            let errorEvent = RedEyeEvent(eventType: .textSelection, metadata: ["error": "Could not determine frontmost app", "trigger": triggerType])
            eventBus.publish(event: errorEvent)
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
            eventBus.publish(event: errorEvent)
            return
        }
        
        guard let focusedElement = focusedUIElement else {
            let errorEvent = RedEyeEvent(
                eventType: .textSelection,
                sourceApplicationName: appName,
                sourceBundleIdentifier: bundleId,
                metadata: ["error": "Focused UI element nil.", "trigger": triggerType]
            )
            eventBus.publish(event: errorEvent)
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
        eventBus.publish(event: event)

        // Show UI panel only if text is actually captured and non-empty
        // AND if the hotkey UI is enabled (for hotkey triggers)
        if let textToShowInPanel = capturedText, !textToShowInPanel.isEmpty {
            if isHotkey { // This was a hotkey trigger
                if isHotkeyUiEnabled { // <<< CHECK THE NEW FLAG
                    RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Hotkey. Requesting UI panel at \(mousePositionForUI).", category: "HotKeyManager")
                    uiManager.showPluginActionsPanel(near: mousePositionForUI, withContextText: textToShowInPanel)
                } else {
                    RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Hotkey. UI panel suppressed by toggle.", category: "HotKeyManager")
                }
            } else { // This was a mouse trigger (shortcut-less)
                // For mouse triggers, the UI is implicitly controlled by InputMonitorManager.isEnabled.
                // If IMM is disabled, we wouldn't get here. So if we are here, show it.
                RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Mouse. Requesting UI panel at \(mousePositionForUI).", category: "HotKeyManager")
                uiManager.showPluginActionsPanel(near: mousePositionForUI, withContextText: textToShowInPanel)
            }
        } else {
            RedEyeLogger.info("No text selected or error capturing. Not showing UI panel. (Trigger: \(triggerType))", category: "HotKeyManager")
        }
    }

    func mouseUpAfterPotentialSelection(at screenPoint: NSPoint) {
        RedEyeLogger.info("HotkeyManager received mouseUpAfterPotentialSelection at \(screenPoint)", category: "HotKeyManager")
        // Call the common text capture logic. The mousePositionForUI is the 'screenPoint' from the mouse up.
        handleTextCaptureTrigger(isHotkey: false, mousePositionForUI: screenPoint)
    }
}
