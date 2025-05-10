//
//  RedEyeLogger.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/10/25.
//

import Foundation
import os // Import the Unified Logging framework

enum RedEyeLogger {

    // Define a subsystem string for your app.
    // Using the bundle identifier is a common practice.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.yourcompany.RedEye.DefaultSubsystem"

    /// A global switch to enable more detailed debug logs.
    /// Can be set programmatically, e.g., based on build configuration or a user setting.
    static var isVerboseLoggingEnabled: Bool = false

    /// Creates a specific logger for a given category.
    private static func makeLogger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    // MARK: - Public Logging Methods

    /// Logs informational messages. These are generally useful for tracking the app's progress and state.
    /// Visible in Console.app by default.
    static func info(_ message: String, category: String) {
        let logger = makeLogger(category: category)
        logger.info("\(message, privacy: .public)")
    }

    /// Logs debug messages. These are more verbose and intended for development and troubleshooting.
    /// Only outputs if `isVerboseLoggingEnabled` is true.
    /// To see these in Console.app, you might need to enable "Info" and "Debug" messages in Console's Action menu.
    static func debug(_ message: String, category: String) {
        if isVerboseLoggingEnabled {
            let logger = makeLogger(category: category)
            logger.debug("\(message, privacy: .public)")
        }
    }

    /// Logs error messages. Use this when an operation fails or an unexpected state occurs.
    /// Visible in Console.app by default.
    static func error(_ message: String, category: String, error: Error? = nil) {
        let logger = makeLogger(category: category)
        if let err = error {
            // Include the error description if provided.
            // Note: The 'error' object itself might contain sensitive info if not handled carefully.
            // For privacy, consider what parts of 'err.localizedDescription' are safe to log.
            logger.error("‼️ ERROR: \(message, privacy: .public) - Details: \(err.localizedDescription, privacy: .public)")
        } else {
            logger.error("‼️ ERROR: \(message, privacy: .public)")
        }
    }
    
    /// Logs fault messages. Use this for critical errors that might lead to app instability or termination.
    /// Always captured, even in release builds, and provide more context for system diagnostics.
    static func fault(_ message: String, category: String, error: Error? = nil) {
        let logger = makeLogger(category: category)
        if let err = error {
            logger.fault("💥 FAULT: \(message, privacy: .public) - Details: \(err.localizedDescription, privacy: .public)")
        } else {
            logger.fault("💥 FAULT: \(message, privacy: .public)")
        }
    }
}
