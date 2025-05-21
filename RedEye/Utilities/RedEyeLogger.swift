// RedEye/Utilities/RedEyeLogger.swift

import Foundation
import os // Unified Logging framework

// --- Loggable Protocol ---
protocol Loggable {
    /// A pre-configured OS Logger instance specific to the conforming type.
    /// This logger should ideally be configured with the appropriate category for the type.
    var instanceLogger: Logger { get }
}

// --- RedEyeLogger Enum (Main Public Interface for Logging) ---
enum RedEyeLogger {

    static let subsystem: String = Bundle.main.bundleIdentifier ?? "com.vic.RedEye.DefaultSubsystem"

    enum LogLevel: Int, Comparable, Codable {
        case fault = 0   // Critical errors, app might terminate. (OS Level: Fault)
        case error = 1   // Serious errors, operation failed. (OS Level: Error)
        case warning = 2 // Potential issues, unexpected situations. (OS Level: Default/Info, we add prefix)
        case info = 3    // General operational information. (OS Level: Info/Default)
        case debug = 4   // Detailed debugging for developers. (OS Level: Debug)
        case trace = 5   // Highly verbose, step-by-step flow. (OS Level: Debug, we add prefix)

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    static var currentLevel: LogLevel = {
        #if DEBUG
            return .debug // Default to debug in DEBUG builds
        #else
            return .info  // Default to info in Release builds
        #endif
    }() {
        didSet {
            // Log the level change itself using a dedicated logger for this specific event.
            let systemLogger = Logger(subsystem: subsystem, category: "LoggerConfig")
            systemLogger.notice("RedEye global log level changed to: \(String(describing: self.currentLevel))")
        }
    }

    // --- Static logging methods (for use where a Loggable instance isn't available or for generic logs) ---
    // These methods still require a category to be passed.

    static func fault(_ message: String, category: String, error: Error? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
        if currentLevel >= .fault {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            let fullMsg = "\(context) 💥 FAULT: \(message)"
            if let err = error { log.fault("\(fullMsg) - Details: \(err.localizedDescription, privacy: .public)") }
            else { log.fault("\(fullMsg)") }
        }
    }

    static func error(_ message: String, category: String, error: Error? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
        if currentLevel >= .error {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            let fullMsg = "\(context) ‼️ ERROR: \(message)"
            if let err = error { log.error("\(fullMsg) - Details: \(err.localizedDescription, privacy: .public)") }
            else { log.error("\(fullMsg)") }
        }
    }
    
    static func warning(_ message: String, category: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if currentLevel >= .warning {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            // os.Logger doesn't have a .warning level, map to .default or .error. Using .error to make it stand out.
            log.error("\(context) ⚠️ WARNING: \(message)") // Using .error for OSLog visibility of warnings
        }
    }

    static func info(_ message: String, category: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if currentLevel >= .info {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            log.info("\(context) \(message)")
        }
    }

    static func debug(_ message: String, category: String, file: String = #file, function: String = #function, line: UInt = #line) {
        // This will only be effective if DEBUG flag is set OR if currentLevel is manually set to .debug/.trace in release.
        // And Console.app needs to show Debug messages.
        if currentLevel >= .debug {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            log.debug("\(context) \(message)")
        }
    }
    
    static func trace(_ message: String, category: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if currentLevel >= .trace {
            let log = Logger(subsystem: subsystem, category: category)
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression))]"
            // os.Logger doesn't have a .trace level. We map it to .debug for os.Logger.
            // The distinction is purely for our `currentLevel` filtering.
            log.debug("\(context) 🔬 TRACE: \(message)")
        }
    }
}

// --- Convenience logging methods for types conforming to Loggable ---
// These use the `instanceLogger` from the conforming type.
extension Loggable {
    // Helper to get a clean function name without parameters for context
    private func cleanFunction(_ function: String) -> String {
        return function.replacingOccurrences(of: "\\(.*\\)", with: "", options: .regularExpression)
    }

    func fault(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .fault {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            let fullMsg = "\(context) 💥 FAULT: \(message)"
            if let err = error { instanceLogger.fault("\(fullMsg) - Details: \(err.localizedDescription, privacy: .public)") }
            else { instanceLogger.fault("\(fullMsg)") }
        }
    }
    
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .error {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            let fullMsg = "\(context) ‼️ ERROR: \(message)"
            if let err = error { instanceLogger.error("\(fullMsg) - Details: \(err.localizedDescription, privacy: .public)") }
            else { instanceLogger.error("\(fullMsg)") }
        }
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .warning {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            // os.Logger maps .warning to .error to make it more visible in Console if not explicitly filtered.
            instanceLogger.error("\(context) ⚠️ WARNING: \(message)")
        }
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .info {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            instanceLogger.info("\(context) \(message)")
        }
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .debug {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            instanceLogger.debug("\(context) \(message)")
        }
    }
    
    func trace(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        if RedEyeLogger.currentLevel >= .trace {
            let context = "[\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(cleanFunction(function))]"
            instanceLogger.debug("\(context) 🔬 TRACE: \(message)") // os.Logger maps trace to debug
        }
    }
}
