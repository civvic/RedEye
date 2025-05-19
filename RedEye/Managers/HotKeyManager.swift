// RedEye/Managers/HotkeyManager.swift

import Foundation
import AppKit // For NSWorkspace and accessibility elements
import KeyboardShortcuts // Import the library

// Define a namespace for our app's shortcuts
// This helps avoid collisions if other apps use the same library
extension KeyboardShortcuts.Name {
    static let captureSelectedText = Self("captureSelectedText", default: .init(.c, modifiers: [.command, .shift]))
}

class HotkeyManager: BaseMonitorManager, InputMonitorManagerDelegate {

    private let uiManager: UIManager // Store UIManager directly
    private var lastMouseSelectedText: String?
    private var hotkeyObservationToken: Any? // To store the token from KeyboardShortcuts

    override var logCategory: String { "HotkeyManager" }

    init(eventBus: EventBus, uiManager: UIManager, configManager: ConfigurationManaging) {
        self.uiManager = uiManager // Initialize specific dependency
        super.init(monitorType: .hotkeyManager, eventBus: eventBus, configManager: configManager)
        RedEyeLogger.info("HotkeyManager specific initialization complete.", category: logCategory)
    }

    // conditionally register hotkeys
    override func startMonitoring() -> Bool {
        // Log general setting for UI panel
        if self.currentGeneralAppSettings?.showPluginPanelOnHotkeyCapture == true {
            RedEyeLogger.info("UI Panel on hotkey capture is ENABLED via general app settings.", category: logCategory)
        } else {
            RedEyeLogger.info("UI Panel on hotkey capture is DISABLED via general app settings.", category: logCategory)
        }
        
        // Setup hotkey listener
        // Avoid re-registering if already active (check token)
        guard hotkeyObservationToken == nil else {
            RedEyeLogger.debug("Hotkey listener (⌘⇧C) already seems to be set up.", category: logCategory)
            return true // Already "started"
        }
        
        RedEyeLogger.info("Setting up listener for ⌘⇧C (captureSelectedText).", category: logCategory)
        hotkeyObservationToken = KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
            guard let self = self, self.isCurrentlyActive else { // Check base isCurrentlyActive
                // This handles the case where the hotkey fires but the manager is not active
                // (either due to initial config or if live updates were to disable it).
                if !(self?.isCurrentlyActive ?? true) { // Log only if explicitly inactive
                    RedEyeLogger.info("⌘⇧C triggered, but HotkeyManager is not active. Ignoring.", category: self?.logCategory ?? "HotkeyManager")
                }
                return
            }
            self.handleTextCaptureTrigger(isHotkey: true, mousePositionForUI: NSEvent.mouseLocation)
        }
        
        if hotkeyObservationToken != nil {
            RedEyeLogger.info("Successfully set up listener for ⌘⇧C.", category: logCategory)
            return true // Successfully started
        } else {
            // This case should ideally not happen if KeyboardShortcuts.onKeyUp works as expected
            RedEyeLogger.error("Failed to set up listener for ⌘⇧C. Hotkey will not function.", category: logCategory)
            return false // Failed to start
        }
    }

    override func stopMonitoring() {
        // KeyboardShortcuts library doesn't have a direct 'unregister' method for a specific handler token.
        // Setting the shortcut to `nil` for the name would unregister it globally.
        // For now, `isCurrentlyActive` check in the handler and clearing our token is sufficient.
        if hotkeyObservationToken != nil {
            RedEyeLogger.info("Clearing internal hotkey observation token for ⌘⇧C. Actual hotkey deactivation depends on the 'isCurrentlyActive' check in handler.", category: logCategory)
            // We don't "remove" the token from KeyboardShortcuts here, as the API isn't built that way.
            // The library manages its own list of handlers.
            hotkeyObservationToken = nil // Just release our reference
        } else {
            RedEyeLogger.debug("Attempted to stop HotkeyManager, but no observation token was found.", category: logCategory)
        }
        // isCurrentlyActive is handled by BaseMonitorManager.stop()
    }

//    private func setupHotkeyListeners() {
//        // Avoid re-registering if already active
//        guard hotkeyObservationToken == nil else {
//            RedEyeLogger.debug("Listeners already set up.", category: "HotKeyManager")
//            return
//        }
//        
//        RedEyeLogger.info("Setting up listener for ⌘⇧C (captureSelectedText).", category: "HotKeyManager")
//        // Storing the observer allows us to remove it later if needed.
//        // KeyboardShortcuts.onKeyUp returns an object that can be used to stop observing.
//        // However, their API for explicit de-registration isn't as straightforward as add/removeMonitor.
//        // For now, we'll rely on the library's internal management. If we need explicit
//        // dynamic enable/disable of the shortcut itself, we might need to investigate further
//        // or see if KeyboardShortcuts provides a mechanism like KeyboardShortcuts.disable(name:).
//        // For v0.3, KeyboardShortcuts didn't have an easy 'unregister'.
//        // Let's assume for now that if `startMonitoring` isn't called or is called when disabled,
//        // the hotkey simply isn't processed by us.
//        // A more robust solution would be to only call KeyboardShortcuts.onKeyUp once
//        // and internally gate the execution based on config.
//        
//        // Re-evaluating: To truly enable/disable the hotkey based on config,
//        // we should ideally register/unregister. KeyboardShortcuts doesn't have a direct
//        // "unregister". A common pattern if a library doesn't support unregistering is
//        // to manage a boolean flag that the handler checks.
//        // Let's stick to the pattern: if not enabled, handler won't run.
//
//        // If KeyboardShortcuts.onKeyUp can be called multiple times safely without duplication,
//        // this is fine. Otherwise, we need a flag. It's typically safe.
//        hotkeyObservationToken = KeyboardShortcuts.onKeyUp(for: .captureSelectedText) { [weak self] in
//            guard let self = self,
//                  let currentConfig = self.hotkeyMonitorConfig, currentConfig.isEnabled else {
//                // If the hotkey fires but our config says we're disabled, do nothing.
//                // This handles the case where KeyboardShortcuts doesn't have an explicit unregister.
//                if self?.hotkeyMonitorConfig?.isEnabled == false { // Check explicitly if it's loaded and false
//                     RedEyeLogger.info("⌘⇧C triggered, but HotkeyManager is disabled by config. Ignoring.", category: "HotKeyManager")
//                }
//                return
//            }
//            self.handleTextCaptureTrigger(isHotkey: true, mousePositionForUI: NSEvent.mouseLocation)
//        }
//    }

//    private func removeHotkeyListeners() {
//        // KeyboardShortcuts library doesn't have a direct 'remove(observer)' or 'disable(name)' in its public API
//        // as of common versions. The typical way to "disable" a shortcut is to not act on its event
//        // or, if the library supports it, set its key combination to nil.
//        // For now, our guard in the onKeyUp handler (checking self.hotkeyMonitorConfig.isEnabled)
//        // effectively disables it.
//        // If we store the `Shortcut` object returned by `onKeyUp`, we might be able to `.isEnabled = false` on it
//        // if the library supports such a property on the observation token.
//        // For now, setting hotkeyObserver to nil will just release our reference.
//        if hotkeyObserver != nil {
//            RedEyeLogger.info("Clearing internal hotkey observer reference. Actual hotkey deactivation depends on KeyboardShortcuts behavior and internal config check.", category: "HotKeyManager")
//            hotkeyObserver = nil // Release our reference. Actual unregistration is tricky with this lib.
//        }
//    }

    private func handleTextCaptureTrigger(isHotkey: Bool, mousePositionForUI: NSPoint) {
        // Check isCurrentlyActive for hotkey triggers, as the event comes directly from KeyboardShortcuts
        if isHotkey {
            guard self.isCurrentlyActive else {
                RedEyeLogger.info("handleTextCaptureTrigger called for hotkey, but manager is not active. Ignoring.", category: self.logCategory)
                return
            }
        }
        // For mouse-triggered (isHotkey=false), InputMonitorManager handles its own active state.

        let triggerType = isHotkey ? "hotkey (⌘⇧C)" : "mouse_selection"
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            RedEyeLogger.error("Could not determine frontmost app. (Trigger: \(triggerType))", category: "HotKeyManager")
            let errorEvent = RedEyeEvent(eventType: .textSelection, metadata: ["error": "Could not determine frontmost app", "trigger": triggerType])
            eventBus?.publish(event: errorEvent)
            return
        }
        let pid = frontmostApp.processIdentifier
        let appName = frontmostApp.localizedName
        let bundleId = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focusedUIElement: AnyObject?
        let focusError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)
        if focusError != .success {
            let errorEvent = RedEyeEvent(eventType: .textSelection, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, metadata: ["error": "Error getting focused UI: \(focusError.rawValue)", "trigger": triggerType])
            eventBus?.publish(event: errorEvent)
            return
        }
        guard let focusedElement = focusedUIElement else {
            let errorEvent = RedEyeEvent(eventType: .textSelection, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, metadata: ["error": "Focused UI element nil.", "trigger": triggerType])
            eventBus?.publish(event: errorEvent)
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
        eventBus?.publish(event: event)

        // Show UI panel only if text is actually captured and non-empty
        // AND if the hotkey UI is enabled (for hotkey triggers)
        if let textToShowInPanel = capturedText, !textToShowInPanel.isEmpty {
            let showPanelForHotkey = self.currentGeneralAppSettings?.showPluginPanelOnHotkeyCapture ?? false // Default to false if not loaded

            if isHotkey {
                if showPanelForHotkey { // << Check the config flag
                    RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Hotkey. Requesting UI panel (as per config).", category: logCategory)
                    uiManager.showPluginActionsPanel(near: mousePositionForUI, withContextText: textToShowInPanel)
                } else {
                    RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Hotkey. UI panel suppressed by config.", category: logCategory)
                }
            } else { // This was a mouse trigger
                // For mouse triggers, UI is shown if InputMonitorManager is enabled (which it must be to get here).
                // And if text is captured. The general app setting for "hotkey UI" does not apply to mouse-selection UI.
                // The mouse-selection UI visibility is implicitly tied to InputMonitorManager.isEnabled.
                // For now, we assume if mouse selection event happens, panel should show if text is present.
                // This could be a separate config later if needed.
                RedEyeLogger.info("Captured text \"\(textToShowInPanel)\" via Mouse. Requesting UI panel.", category: logCategory)
                uiManager.showPluginActionsPanel(near: mousePositionForUI, withContextText: textToShowInPanel)
            }
        } else {
            RedEyeLogger.info("No text selected or error capturing. Not showing UI panel. (Trigger: \(triggerType))", category: logCategory)
        }
    }

    func mouseUpAfterPotentialSelection(at screenPoint: NSPoint) {
        RedEyeLogger.info("HotkeyManager received mouseUpAfterPotentialSelection at \(screenPoint)", category: "HotKeyManager")
        // Call the common text capture logic. The mousePositionForUI is the 'screenPoint' from the mouse up.
        handleTextCaptureTrigger(isHotkey: false, mousePositionForUI: screenPoint)
    }
}
