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
    private var hotkeyObservationToken: Any?
    private let textCaptureService: TextCaptureService

    override var logCategory: String { "HotkeyManager" }

    init(eventBus: EventBus, uiManager: UIManager, configManager: ConfigurationManaging, textCaptureService: TextCaptureService) {
        self.uiManager = uiManager
        self.textCaptureService = textCaptureService // Store injected service
        super.init(monitorType: .hotkeyManager, eventBus: eventBus, configManager: configManager)
        RedEyeLogger.info("HotkeyManager specific initialization complete with TextCaptureService.", category: self.logCategory)
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

    private func handleTextCaptureTrigger(isHotkey: Bool, mousePositionForUI: NSPoint) {
        if isHotkey {
            guard self.isCurrentlyActive else { /* ... log and return ... */ return }
        }

        let triggerType = isHotkey ? "hotkey (⌘⇧C)" : "mouse_selection"
        RedEyeLogger.info("Attempting text capture via TextCaptureService. Trigger: \(triggerType)", category: self.logCategory)

        // << MODIFIED: Use TextCaptureService >>
        let captureResult = textCaptureService.captureSelectedTextFromFrontmostApp()

        var metadata: [String: String] = ["trigger": triggerType]
        if let error = captureResult.error {
            // Use a more specific error key if desired, or add to a list of errors.
            metadata["textCaptureError"] = error.localizedDescription
            RedEyeLogger.debug("TextCaptureService reported an issue: \(error.localizedDescription)", category: self.logCategory)
        }
        
        // For mouse selections, apply heuristic: Only proceed if text is non-empty AND different from last
        if !isHotkey {
            if captureResult.capturedText == nil || captureResult.capturedText!.isEmpty {
                RedEyeLogger.info("Mouse selection resulted in empty text (via service). Not processing event.", category: self.logCategory)
                return
            }
            if captureResult.capturedText == self.lastMouseSelectedText {
                RedEyeLogger.info("Mouse selected text (via service) is same as last. Not processing event.", category: self.logCategory)
                return
            }
            self.lastMouseSelectedText = captureResult.capturedText
            RedEyeLogger.info("New mouse selection (via service): \"\(captureResult.capturedText!)\". Processing event.", category: self.logCategory)
        } else { // For hotkey, always clear lastMouseSelectedText
            self.lastMouseSelectedText = nil
            RedEyeLogger.info("Hotkey trigger. Processing event for text (via service): \"\(captureResult.capturedText ?? "nil")\"", category: self.logCategory)
        }
        // --- End Heuristic ---

        // Log the attempt *after* basic heuristics for mouse selection.
        // Redundant logging here if service already logged, but confirms HotkeyManager is proceeding.
        // RedEyeLogger.info("Processing text capture (Trigger: \(triggerType), Text: \"\(captureResult.capturedText ?? "nil")\")", category: self.logCategory)

        
        let event = RedEyeEvent(
            eventType: .textSelection,
            sourceApplicationName: captureResult.sourceApplicationName, // From captureResult
            sourceBundleIdentifier: captureResult.sourceBundleIdentifier, // From captureResult
            contextText: captureResult.capturedText, // From captureResult
            metadata: metadata
        )
        self.eventBus?.publish(event: event)

        // Show UI panel only if text is actually captured and non-empty
        // AND if the hotkey UI is enabled (for hotkey triggers)
        if let textToShowInPanel = captureResult.capturedText, !textToShowInPanel.isEmpty {
            let showPanelForHotkey = self.currentGeneralAppSettings?.showPluginPanelOnHotkeyCapture ?? false

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
            RedEyeLogger.info("No text captured by service or text is empty. Not showing UI panel. (Trigger: \(triggerType))", category: self.logCategory)
        }
    }

    func mouseUpAfterPotentialSelection(at screenPoint: NSPoint) {
        RedEyeLogger.info("HotkeyManager received mouseUpAfterPotentialSelection at \(screenPoint)", category: "HotKeyManager")
        // Call the common text capture logic. The mousePositionForUI is the 'screenPoint' from the mouse up.
        handleTextCaptureTrigger(isHotkey: false, mousePositionForUI: screenPoint)
    }
}
