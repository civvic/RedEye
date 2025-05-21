// RedEye/Services/TextCaptureService.swift

import Foundation
import AppKit // For NSWorkspace, AXUIElement related constants
import os

// To provide more context than just the string, or detailed errors
struct TextCaptureResult {
    let capturedText: String?
    let sourceApplicationName: String?
    let sourceBundleIdentifier: String?
    let error: TextCaptureError? // Optional error information
}

enum TextCaptureError: Error, LocalizedError {
    case noFrontmostApplication
    case accessibilityError(code: AXError, operation: String)
    case focusedElementUnavailable(String) // E.g. "Focused UI element was nil" or "Could not get focused UI element"
    case noTextSelected
    case unknown

    var errorDescription: String? {
        switch self {
        case .noFrontmostApplication:
            return "Could not determine the frontmost application."
        case .accessibilityError(let code, let operation):
            return "Accessibility API error during '\(operation)': \(Self.stringForAXErrorCode(code)) (Code: \(code.rawValue)). Ensure Accessibility permission is granted for RedEye."
        case .focusedElementUnavailable(let reason):
            return "Focused element for text capture was unavailable: \(reason)."
        case .noTextSelected:
            return "No text appears to be selected in the focused element."
        case .unknown:
            return "An unknown error occurred during text capture."
        }
    }
    
    static func stringForAXErrorCode(_ errorCode: AXError) -> String {
        switch errorCode {
            case .success: return "Success"
            case .failure: return "Failure"
            case .apiDisabled: return "API Disabled (Accessibility not enabled?)"
            case .invalidUIElement: return "Invalid UI Element"
            case .invalidUIElementObserver: return "Invalid UI Element Observer"
            case .cannotComplete: return "Cannot Complete"
            case .attributeUnsupported: return "Attribute Unsupported"
            case .actionUnsupported: return "Action Unsupported"
            case .notImplemented: return "Not Implemented"
            case .notificationUnsupported: return "Notification Unsupported"
            case .notEnoughPrecision: return "Not Enough Precision"
            case .noValue: return "No Value (e.g., for a query)"
            default: return "Unknown AXError"
        }
    }
}

class TextCaptureService: Loggable {

    var logCategoryForInstance: String { return "TextCaptureService" }
    var instanceLogger: Logger { Logger(subsystem: RedEyeLogger.subsystem, category: self.logCategoryForInstance) }

    init() {
        info("TextCaptureService initialized.")
    }

    /// Attempts to capture the currently selected text from the frontmost application.
    /// - Returns: A `TextCaptureResult` containing the text, application info, and any error.
    func captureSelectedTextFromFrontmostApp() -> TextCaptureResult {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            error("Could not determine frontmost application.")
            return TextCaptureResult(capturedText: nil, sourceApplicationName: nil, sourceBundleIdentifier: nil, error: .noFrontmostApplication)
        }

        let pid = frontmostApp.processIdentifier
        let appName = frontmostApp.localizedName
        let bundleId = frontmostApp.bundleIdentifier
        
        debug("Attempting text capture from: \(appName ?? "Unknown App") (\(bundleId ?? "Unknown BundleID"))")

        let appElement = AXUIElementCreateApplication(pid)
        var focusedUIElementAsAnyObject: AnyObject? // Store the AnyObject? from the API

        let focusCopyError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElementAsAnyObject)

        if focusCopyError != .success {
            error("Error getting focused UI element: \(TextCaptureError.stringForAXErrorCode(focusCopyError))")
            return TextCaptureResult(capturedText: nil, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: .accessibilityError(code: focusCopyError, operation: "CopyFocusedUIElement"))
        }
        
        guard let focusedElement = focusedUIElementAsAnyObject else {
            // This means AXAPI returned success but the out-parameter is nil. Highly unlikely but possible.
            error("Focused UI element reference was nil despite AXAPI success for CopyFocusedUIElement.")
            return TextCaptureResult(capturedText: nil, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: .focusedElementUnavailable("Focused UI element reference was nil."))
        }

        // If focusedElement is non-nil, we expect it to be an AXUIElementRef.
        // We perform a forced cast here, as was done in HotkeyManager.
        // If this crashes, it means the AX API returned something unexpected for kAXFocusedUIElementAttribute
        // despite returning .success and a non-nil object.
        let focusedAXElement = focusedElement as! AXUIElement // << REVERTED to forced cast

        var selectedTextValue: AnyObject?
        let selectedTextCopyError = AXUIElementCopyAttributeValue(focusedAXElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        if selectedTextCopyError == .success {
            if let capturedText = selectedTextValue as? String, !capturedText.isEmpty {
                info("Successfully captured text (first 100 chars): \"\(capturedText.prefix(100))\"")
                return TextCaptureResult(capturedText: capturedText, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: nil)
            } else {
                info("Successfully queried for selected text, but no text is selected or selection is empty.")
                return TextCaptureResult(capturedText: nil, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: .noTextSelected)
            }
        } else {
            if selectedTextCopyError == .attributeUnsupported {
                 info("Focused element in \(appName ?? "target app") does not support kAXSelectedTextAttribute.")
                 return TextCaptureResult(capturedText: nil, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: .accessibilityError(code: selectedTextCopyError, operation: "CopySelectedText (AttributeUnsupported)"))
            } else {
                error("Error getting selected text value: \(TextCaptureError.stringForAXErrorCode(selectedTextCopyError))")
                return TextCaptureResult(capturedText: nil, sourceApplicationName: appName, sourceBundleIdentifier: bundleId, error: .accessibilityError(code: selectedTextCopyError, operation: "CopySelectedText"))
            }
        }
    }
}
