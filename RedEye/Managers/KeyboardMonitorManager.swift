// RedEye/Managers/KeyboardMonitorManager.swift

import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// --- C Callback Function ---
// This function must be defined at the top level or as a static method.
// It receives the event details and the userInfo pointer we provide.
private func keyboardEventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        RedEyeLogger.error("Event tap callback received nil refcon (userInfo).", category: "KeyboardMonitor")
        // Pass the event through unchanged if we can't process it
        return Unmanaged.passUnretained(event)
    }
    
    // Reconstitute the KeyboardMonitorManager instance from the opaque pointer
    let manager = Unmanaged<KeyboardMonitorManager>.fromOpaque(refcon).takeUnretainedValue()
    
    // Call the instance method to handle the event
    // We need to retain the event before passing it to the handler if the handler might keep it.
    // If the handler just inspects and potentially creates a *new* event, passing unmanaged is okay.
    // For safety, let's use passRetained/autorelease if we plan complex handling.
    // But for simple inspection now, passUnretained is fine and more efficient.
    return manager.handleEventTap(proxy: proxy, type: type, event: event)
}
// --- End C Callback Function ---

// Define a protocol for emitting events, similar to FSEventMonitorManager.
// This promotes decoupling from EventManager, preparing for the EventBus refactor.
protocol KeyboardEventMonitorDelegate: AnyObject {
    func keyboardEventMonitor(_ monitor: KeyboardMonitorManager, didEmit event: RedEyeEvent)
}

class KeyboardMonitorManager {

    // MARK: - Properties
    private static let logCategory = "KeyboardMonitor"
    weak var delegate: KeyboardEventMonitorDelegate?
    var isEnabled: Bool = true
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Keep track of permission state
    private var hasInputMonitoringPermission: Bool = false

    // MARK: - Initialization
    init(delegate: KeyboardEventMonitorDelegate?) {
        self.delegate = delegate
        RedEyeLogger.info("KeyboardMonitorManager initialized.", category: KeyboardMonitorManager.logCategory)
    }

    deinit {
        stopMonitoring()
        RedEyeLogger.info("KeyboardMonitorManager deinitialized.", category: KeyboardMonitorManager.logCategory)
    }

    // MARK: - Permission Handling

    /// Checks the current Input Monitoring permission status.
    /// Optionally prompts the user if permission is not granted.
    /// Updates the `hasInputMonitoringPermission` property.
    /// - Parameter promptIfNeeded: If true, prompts the user via the system dialog if access is not granted.
    /// - Returns: True if permission is currently granted, false otherwise.
    @discardableResult // Allow ignoring the return value if only checking/prompting
    private func checkAndRequestInputMonitoringPermission(promptIfNeeded: Bool = false) -> Bool {
        let currentStatus = AXIsProcessTrusted() // Check current status without prompting

        if currentStatus {
            if !hasInputMonitoringPermission {
                 RedEyeLogger.info("Input Monitoring permission already granted.", category: KeyboardMonitorManager.logCategory)
                 hasInputMonitoringPermission = true
            }
            return true
        } else {
            hasInputMonitoringPermission = false
            RedEyeLogger.info("Input Monitoring permission not granted.", category: KeyboardMonitorManager.logCategory)
            if promptIfNeeded {
                RedEyeLogger.info("Requesting Input Monitoring permission from user...", category: KeyboardMonitorManager.logCategory)
                // This will show the system prompt. It requires a Info.plist key NSInputMonitoringUsageDescription.
                // It doesn't block; the user grants/denies asynchronously in System Settings.
                // We check again next time the app starts or tries to monitor.
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                // We return false *now* because the user has to grant it manually.
                // The app will likely need a restart, or we need more complex logic
                // to re-check periodically after prompting. For now, we rely on restart.
                RedEyeLogger.error("Input Monitoring permission must be granted in System Settings > Privacy & Security > Input Monitoring. Please grant access and restart RedEye if needed.", category: KeyboardMonitorManager.logCategory)
            }
            return false
        }
    }

    // MARK: - Public Methods: Start/Stop Monitoring
    func startMonitoring() {
        guard isEnabled else {
            RedEyeLogger.info("Keyboard monitoring is disabled by toggle.", category: KeyboardMonitorManager.logCategory)
            return
        }
        guard eventTap == nil else {
            RedEyeLogger.error("Attempted to start keyboard monitoring, but tap already exists.", category: KeyboardMonitorManager.logCategory)
            return
        }

        RedEyeLogger.info("Attempting to start keyboard event monitoring...", category: KeyboardMonitorManager.logCategory)

        if !checkAndRequestInputMonitoringPermission(promptIfNeeded: !hasInputMonitoringPermission) {
             RedEyeLogger.error("Cannot start keyboard monitoring due to lack of Input Monitoring permission.", category: KeyboardMonitorManager.logCategory)
             return
        }
        
        // Define the events we want to tap
        // Combine keyDown, keyUp, and flagsChanged events.
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << CGEventType.flagsChanged.rawValue)

        // Get self as an opaque pointer to pass to the callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Create the event tap
        // We use `.listenOnly` as we don't intend to modify events (yet).
        // Use `.cgSessionEventTap` for wider scope including login window etc if needed,
        // but `.cgAnnotatedSessionEventTap` is usually sufficient for typical apps and slightly more restricted. Let's start with annotated.
        eventTap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, // Location
                                     place: .headInsertEventTap,     // Place (head = before others)
                                     options: .listenOnly,            // Options (listen, not modify)
                                     eventsOfInterest: eventMask,     // Mask of events
                                     callback: keyboardEventTapCallback, // C callback function
                                     userInfo: selfPtr)               // Pointer to self

        // Check if tap creation was successful
        guard let tap = eventTap else {
            RedEyeLogger.error("Failed to create keyboard event tap (CGEvent.tapCreate returned nil). This might happen if permission was just granted and a restart is needed, or another issue occurred.", category: KeyboardMonitorManager.logCategory)
            // Reset permission flag to force re-check/prompt next time if needed
            hasInputMonitoringPermission = false // Assume permission might be the issue
            return
        }

        // Create a run loop source from the event tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = runLoopSource else {
             RedEyeLogger.error("Failed to create run loop source from event tap.", category: KeyboardMonitorManager.logCategory)
             // Clean up the tap if source creation fails
             CFMachPortInvalidate(tap)
             // CFRelease(tap) // tapCreate follows the Create Rule, so we need to release. Handled in stopMonitoring/deinit now.
             eventTap = nil
             return
        }

        // Add the source to the current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        
        RedEyeLogger.info("Keyboard event tap created and added to run loop.", category: KeyboardMonitorManager.logCategory)
    }

    func stopMonitoring() {
        guard let tap = eventTap else { return }
        RedEyeLogger.info("Stopping keyboard event monitoring...", category: KeyboardMonitorManager.logCategory)

        // Remove the source from the run loop first
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            // CFRelease(source); // No release needed for CFRunLoopSource according to docs? Let ARC handle if possible. Check needed.
            // Update: Docs suggest CFRunLoopSourceInvalidate implicitly releases. Let's rely on tap invalidation.
            runLoopSource = nil
            RedEyeLogger.debug("Removed run loop source.", category: KeyboardMonitorManager.logCategory)
        } else {
            RedEyeLogger.debug("No run loop source found to remove.", category: KeyboardMonitorManager.logCategory)
        }

        // Invalidate the tap (this also disables the callback)
        CFMachPortInvalidate(tap)
        // CFRelease(tap); // tapCreate follows Create Rule, must be released. Let ARC manage if Swift wrapper used, but direct CF calls need manual release.
        // Let's ensure ARC doesn't interfere and manage CF manually where needed.
        // However, since eventTap is CFMachPort?, ARC *should* handle the release when eventTap is set to nil.
        // Let's rely on ARC for now unless we see leaks.
        RedEyeLogger.debug("Invalidated event tap.", category: KeyboardMonitorManager.logCategory)

        eventTap = nil // Let ARC release the CFMachPort object

        RedEyeLogger.info("Keyboard event monitoring stopped and resources released.", category: KeyboardMonitorManager.logCategory)
    }

    // MARK: - Private Event Handling Logic (Called by C callback)
    
    func handleEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        
        // Filter out events we are not interested in
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event) // Pass through
        }
        
        // Extract event details
        var metadata: [String: String] = [:]
        let eventTypeString: String
        
        // Get modifier flags (common to all types we monitor)
        let flags = event.flags
        metadata.merge(interpretCGEventFlags(flags)) { (_, new) in new } // Add interpreted flags
        metadata["keyboard_modifiers_flags"] = String(flags.rawValue) // Add raw flags value

        // Get Key Code (relevant for keyUp/keyDown, sometimes for flagsChanged)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        metadata["keyboard_key_code"] = String(keyCode)

        // Handle based on event type
        switch type {
        case .keyDown:
            eventTypeString = "keyDown"
            metadata["keyboard_event_type"] = eventTypeString
            if let character = getCharacterForKeyCode(event: event) {
                metadata["keyboard_character"] = character
            }
            
        case .keyUp:
            eventTypeString = "keyUp"
            metadata["keyboard_event_type"] = eventTypeString
             if let character = getCharacterForKeyCode(event: event) { // Also useful on keyUp potentially
                 metadata["keyboard_character"] = character
             }

        case .flagsChanged:
             eventTypeString = "flagsChanged"
             metadata["keyboard_event_type"] = eventTypeString
            // Character is usually not relevant for flagsChanged directly
            // Key code *might* indicate which modifier key was pressed/released (e.g., 56 for Shift L)

        default:
            // Should not happen due to guard, but good practice
            eventTypeString = "unknown"
            RedEyeLogger.debug("Processing unexpected event type in switch: \(type.rawValue)", category: KeyboardMonitorManager.logCategory)
            return Unmanaged.passUnretained(event) // Pass through
        }
        
        // Log the detailed event info (optional, can be verbose)
        // RedEyeLogger.debug("Keyboard Event: \(eventTypeString), Code: \(keyCode), Char: \(metadata["keyboard_character"] ?? "N/A"), Flags: \(flags.rawValue)", category: KeyboardMonitorManager.logCategory)
        
        // Create the RedEyeEvent
        // We don't easily know the source app from CGEventTap alone, so leave it nil.
        let redEyeEvent = RedEyeEvent(
            eventType: .keyboardEvent,
            sourceApplicationName: nil, // Cannot reliably get this from low-level tap
            sourceBundleIdentifier: nil, // Cannot reliably get this from low-level tap
            contextText: metadata["keyboard_character"], // Use character as context? Or nil? TBD. Let's use char for now.
            metadata: metadata
        )

        // Emit the event via the delegate
        delegate?.keyboardEventMonitor(self, didEmit: redEyeEvent)

        // Pass the event through unmodified
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Helper Functions

    /// Attempts to get the Unicode character produced by a keyDown/keyUp event,
    /// considering the current keyboard layout and modifier keys.
    private func getCharacterForKeyCode(event: CGEvent) -> String? {
        var actualLength = 0
        var unicodeString: [UniChar] = [0, 0] // Max 2 UniChars for complex scripts/dead keys
        
        // TIS (Text Input Source) alternative - often more reliable than legacy UCKeyTranslate
        // Requires linking Carbon framework
        // guard let currentKeyboard = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        // guard let layoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        // let layoutPtr = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        // let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutPtr), to: UnsafePointer<UCKeyboardLayout>.self)
        // var deadKeyState: UInt32 = 0
        // let modifierKeyState = ... // Need to map CGEventFlags to UCKeyTranslate modifier state
        // let keyAction = ... // Map keyCode appropriately
        
        // Using the simpler (but sometimes less accurate) CGEventKeyboardGetUnicodeString
        // This directly uses the event's state.
        event.keyboardGetUnicodeString(maxStringLength: 2, actualStringLength: &actualLength, unicodeString: &unicodeString)

        if actualLength > 0 {
            return String(utf16CodeUnits: unicodeString, count: actualLength)
        }
        
        // Fallback or if no character generated (e.g., modifier key press)
        return nil
    }


    /// Converts CGEventFlags into a human-readable dictionary.
    private func interpretCGEventFlags(_ flags: CGEventFlags) -> [String: String] {
        var interpretations: [String: String] = [:]
        interpretations["keyboard_modifier_cmd_active"] = flags.contains(.maskCommand).description
        interpretations["keyboard_modifier_shift_active"] = flags.contains(.maskShift).description
        interpretations["keyboard_modifier_option_active"] = flags.contains(.maskAlternate).description // Option/Alt
        interpretations["keyboard_modifier_control_active"] = flags.contains(.maskControl).description
        interpretations["keyboard_modifier_fn_active"] = flags.contains(.maskSecondaryFn).description // Fn key
        interpretations["keyboard_modifier_capslock_active"] = flags.contains(.maskAlphaShift).description // Caps Lock
        // You could add .maskHelp, .maskNumericPad if needed
        return interpretations
    }

}
