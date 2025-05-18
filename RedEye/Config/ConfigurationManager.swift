// RedEye/Config/ConfigurationManager.swift

import Foundation

protocol ConfigurationManaging: AnyObject {
    // MARK: - Configuration Access
    func getCurrentConfig() -> RedEyeConfig
    func getMonitorSetting(for type: MonitorType) -> MonitorSpecificConfig?
    func getGeneralSettings() -> GeneralAppSettings

    // MARK: - Configuration Modification (for IPC and future UI)
    // These methods will modify the in-memory config and persist it.
    // They should also notify relevant components if live updates are needed.

    /// Sets the enabled state for a specific monitor.
    func setMonitorEnabled(type: MonitorType, isEnabled: Bool) throws
    
    /// Sets specific parameters for a monitor.
    /// Replaces all existing parameters for that monitor.
    func setMonitorParameters(type: MonitorType, parameters: [String: JSONValue]?) throws

    /// Updates a single parameter for a specific monitor.
    /// If the parameter does not exist, it's added. If `value` is nil, it could be removed (TBD).
    // func updateMonitorParameter(type: MonitorType, key: String, value: JSONValue?) throws

    /// Updates the general application settings.
    func updateGeneralSettings(newSettings: GeneralAppSettings) throws
    
    /// Resets the configuration to default settings.
    func resetToDefaults() throws

    // MARK: - Persistence
    func saveConfiguration() throws // Explicit save, though setters might save automatically
    func loadConfiguration() throws // Explicit load, usually done at init

    // MARK: - Introspection (as per v0.4 roadmap)
    // Command to retrieve RedEye's current capabilities (available monitors, event types)
    // This might not solely rely on config, but config is a part of it.
    // For now, we can list monitor types from MonitorType.allCases and their config.
    func getCapabilities() -> [String: Any] // Simplified return type for now
}

class ConfigurationManager: ConfigurationManaging {

    private static let logCategory = "ConfigurationManager"
    private let appName = "RedEye" // Or Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "RedEye"
    private let configFileName = "config.json"
    
    private var currentConfig: RedEyeConfig
    private let configFileURL: URL

    // Queue for serializing access to currentConfig and file operations
    private let configQueue = DispatchQueue(label: "com.vic.RedEye.ConfigurationManagerQueue", qos: .utility)

    // JSON Coders
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initialization
    init() {
        // Determine config file URL (e.g., in Application Support)
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            RedEyeLogger.fault("CRITICAL: Could not find Application Support directory. Configuration system will not work.", category: ConfigurationManager.logCategory)
            // This is a non-recoverable state for the config manager.
            // We'll use a dummy config, but saving/loading will be impossible.
            self.configFileURL = URL(fileURLWithPath: "/dev/null/redeye_config.json") // Invalid path
            self.currentConfig = RedEyeConfig.defaultConfig() // In-memory default
            self.encoder = JSONEncoder() // Still need to init these
            self.decoder = JSONDecoder()
            RedEyeLogger.error("ConfigurationManager will operate with in-memory defaults only. No persistence.", category: ConfigurationManager.logCategory)
            return
        }

        let redEyeAppSupportDir = appSupportDir.appendingPathComponent(self.appName, isDirectory: true)
        self.configFileURL = redEyeAppSupportDir.appendingPathComponent(self.configFileName)
        
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Make JSON human-readable
        self.encoder.dateEncodingStrategy = .iso8601 // Consistent date handling

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Initial load or default creation.
        // This needs to be synchronous for init, or init needs to be throwable/async.
        // For now, load synchronously. If load fails, use defaults and attempt to save them.
        // This logic will be fleshed out in the implementation part.
        do {
            // Ensure the directory exists before trying to load/save.
            // This is done within performSaveConfiguration if the file is being created.
            // For loading, if the directory doesn't exist, the file won't exist.
            RedEyeLogger.info("Attempting to load configuration from: \(self.configFileURL.path)", category: ConfigurationManager.logCategory)
            let loadedConfig = try Self.performLoadConfiguration(
                url: self.configFileURL,
                decoder: self.decoder
            )
            self.currentConfig = loadedConfig
            RedEyeLogger.info("Configuration loaded successfully. Schema version: \(self.currentConfig.schemaVersion)", category: ConfigurationManager.logCategory)
            // Optional: Perform schema version check and migration if needed in the future.
        } catch {
            RedEyeLogger.info("Failed to load configuration (Reason: \(error.localizedDescription)). Using default configuration and attempting to save.", category: ConfigurationManager.logCategory)
            self.currentConfig = RedEyeConfig.defaultConfig()
            do {
                RedEyeLogger.info("Attempting to save default configuration to: \(self.configFileURL.path)", category: ConfigurationManager.logCategory)
                try Self.performSaveConfiguration(
                    config: self.currentConfig,
                    url: self.configFileURL,
                    encoder: self.encoder,
                    appName: self.appName // Pass appName for directory creation
                )
                RedEyeLogger.info("Default configuration saved successfully.", category: ConfigurationManager.logCategory)
            } catch let saveError {
                RedEyeLogger.error("CRITICAL: Failed to save default configuration (Reason: \(saveError.localizedDescription)). Configuration might not persist.", category: ConfigurationManager.logCategory, error: saveError)
            }
        }
        RedEyeLogger.info("ConfigurationManager initialized.", category: ConfigurationManager.logCategory)
    }

    // MARK: - Static File Operations
    
    /// Loads configuration data from the specified URL.
    private static func performLoadConfiguration(url: URL, decoder: JSONDecoder) throws -> RedEyeConfig {
        RedEyeLogger.debug("Static: performLoadConfiguration from URL: \(url.path)", category: logCategory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            RedEyeLogger.debug("Static: Config file not found at \(url.path)", category: logCategory)
            throw ConfigError.fileNotFound
        }
        do {
            let data = try Data(contentsOf: url)
            RedEyeLogger.debug("Static: Successfully read \(data.count) bytes from \(url.path)", category: logCategory)
            let config = try decoder.decode(RedEyeConfig.self, from: data)
            RedEyeLogger.debug("Static: Successfully decoded config. Schema version: \(config.schemaVersion)", category: logCategory)
            return config
        } catch let readError as NSError where readError.domain == NSCocoaErrorDomain && readError.code == NSFileReadNoSuchFileError {
            // This catch block might be redundant if fileExistsAtPath is checked first, but good for robustness.
            RedEyeLogger.debug("Static: Config file explicitly reported as not found during read: \(url.path)", category: logCategory)
            throw ConfigError.fileNotFound
        } catch let decodingError as DecodingError {
            RedEyeLogger.error("Static: DecodingError during config load: \(decodingError.localizedDescription). Context: \(decodingError)", category: logCategory, error: decodingError)
            throw ConfigError.deserializationFailed(decodingError)
        } catch {
            RedEyeLogger.error("Static: Generic error during config load from \(url.path): \(error.localizedDescription)", category: logCategory, error: error)
            throw ConfigError.fileReadFailed(error)
        }
    }

    /// Saves configuration data to the specified URL.
    /// Creates the necessary directory if it doesn't exist.
    private static func performSaveConfiguration(config: RedEyeConfig, url: URL, encoder: JSONEncoder, appName: String) throws {
        RedEyeLogger.debug("Static: performSaveConfiguration to URL: \(url.path) for schema version \(config.schemaVersion)", category: logCategory)
        do {
            // Ensure directory exists
            let directoryURL = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                RedEyeLogger.info("Static: Configuration directory not found at \(directoryURL.path). Attempting to create.", category: logCategory)
                do {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                    RedEyeLogger.info("Static: Successfully created configuration directory: \(directoryURL.path)", category: logCategory)
                } catch {
                    RedEyeLogger.error("Static: Failed to create configuration directory \(directoryURL.path): \(error.localizedDescription)", category: logCategory, error: error)
                    throw ConfigError.directoryCreationFailed(error)
                }
            }

            let data = try encoder.encode(config)
            RedEyeLogger.debug("Static: Successfully encoded config. Data size: \(data.count) bytes.", category: logCategory)
            try data.write(to: url, options: .atomicWrite) // .atomicWrite is safer
            RedEyeLogger.debug("Static: Successfully wrote config data to \(url.path)", category: logCategory)
        } catch let encodingError as EncodingError {
            RedEyeLogger.error("Static: EncodingError during config save: \(encodingError.localizedDescription). Context: \(encodingError)", category: logCategory, error: encodingError)
            throw ConfigError.serializationFailed(encodingError)
        } catch {
            RedEyeLogger.error("Static: Generic error during config save to \(url.path): \(error.localizedDescription)", category: logCategory, error: error)
            throw ConfigError.fileWriteFailed(error)
        }
    }

    // MARK: - Configuration Access (Thread-Safe Getters)

    func getCurrentConfig() -> RedEyeConfig {
        // Synchronous access to currentConfig, protected by the queue.
        // Returns a copy to ensure the caller doesn't inadvertently modify the internal state
        // outside the queue, though RedEyeConfig is a struct, so it's already a copy.
        return configQueue.sync {
            self.currentConfig
        }
    }

    func getMonitorSetting(for type: MonitorType) -> MonitorSpecificConfig? {
        return configQueue.sync {
            self.currentConfig.monitorSettings[type.rawValue]
        }
    }

    func getGeneralSettings() -> GeneralAppSettings {
        return configQueue.sync {
            self.currentConfig.generalSettings
        }
    }

    // MARK: - Configuration Modification (Thread-Safe Setters)

    func setMonitorEnabled(type: MonitorType, isEnabled: Bool) throws {
        try configQueue.sync { // `sync` here makes the method blocking and allows throwing errors out
            guard self.currentConfig.monitorSettings[type.rawValue] != nil else {
                RedEyeLogger.error("Attempted to set 'isEnabled' for unknown monitor type: \(type.rawValue)", category: ConfigurationManager.logCategory)
                throw ConfigError.unknownMonitorType(type.rawValue)
            }
            self.currentConfig.monitorSettings[type.rawValue]?.isEnabled = isEnabled
            RedEyeLogger.info("Monitor '\(type.rawValue)' isEnabled set to \(isEnabled). Attempting to save.", category: ConfigurationManager.logCategory)
            try Self.performSaveConfiguration(config: self.currentConfig, url: self.configFileURL, encoder: self.encoder, appName: self.appName)
            // TODO: Future: Notify relevant components about the config change.
        }
    }

    func setMonitorParameters(type: MonitorType, parameters: [String : JSONValue]?) throws {
        try configQueue.sync {
            guard self.currentConfig.monitorSettings[type.rawValue] != nil else {
                RedEyeLogger.error("Attempted to set 'parameters' for unknown monitor type: \(type.rawValue)", category: ConfigurationManager.logCategory)
                throw ConfigError.unknownMonitorType(type.rawValue)
            }
            self.currentConfig.monitorSettings[type.rawValue]?.parameters = parameters
            let paramsDescription = parameters?.mapValues { $0.debugDescription }.description ?? "nil"
            RedEyeLogger.info("Monitor '\(type.rawValue)' parameters set to \(paramsDescription). Attempting to save.", category: ConfigurationManager.logCategory)
            try Self.performSaveConfiguration(config: self.currentConfig, url: self.configFileURL, encoder: self.encoder, appName: self.appName)
            // TODO: Future: Notify relevant components.
        }
    }

    func updateGeneralSettings(newSettings: GeneralAppSettings) throws {
        try configQueue.sync {
            self.currentConfig.generalSettings = newSettings
            RedEyeLogger.info("General settings updated. Attempting to save. New 'showPluginPanelOnHotkeyCapture': \(newSettings.showPluginPanelOnHotkeyCapture)", category: ConfigurationManager.logCategory)
            try Self.performSaveConfiguration(config: self.currentConfig, url: self.configFileURL, encoder: self.encoder, appName: self.appName)
            // TODO: Future: Notify relevant components.
        }
    }
    
    func resetToDefaults() throws {
        try configQueue.sync {
            RedEyeLogger.info("Resetting configuration to defaults and saving.", category: ConfigurationManager.logCategory)
            self.currentConfig = RedEyeConfig.defaultConfig()
            try Self.performSaveConfiguration(config: self.currentConfig, url: self.configFileURL, encoder: self.encoder, appName: self.appName)
            // TODO: Future: Notify relevant components.
        }
    }

    // MARK: - Persistence (Explicit Public Methods)

    func saveConfiguration() throws {
        // This public save method also uses the queue to serialize access.
        try configQueue.sync {
            RedEyeLogger.info("Explicit saveConfiguration called. Saving current in-memory config.", category: ConfigurationManager.logCategory)
            try Self.performSaveConfiguration(config: self.currentConfig, url: self.configFileURL, encoder: self.encoder, appName: self.appName)
        }
    }

    func loadConfiguration() throws {
        // This public load method reloads from disk and updates currentConfig.
        try configQueue.sync {
            RedEyeLogger.info("Explicit loadConfiguration called. Reloading from disk: \(self.configFileURL.path)", category: ConfigurationManager.logCategory)
            let loadedConfig = try Self.performLoadConfiguration(url: self.configFileURL, decoder: self.decoder)
            self.currentConfig = loadedConfig
            RedEyeLogger.info("Configuration reloaded successfully from disk. Schema version: \(self.currentConfig.schemaVersion)", category: ConfigurationManager.logCategory)
            // TODO: Future: Notify ALL components that entire config might have changed.
        }
    }
    
    // MARK: - Introspection
    
    func getCapabilities() -> [String : Any] {
        return configQueue.sync {
            let availableMonitors = MonitorType.allCases.map { monitorType -> [String: Any] in
                let settings = self.currentConfig.monitorSettings[monitorType.rawValue]
                return [
                    "name": monitorType.rawValue,
                    "isEnabledByDefaultInCurrentConfig": settings?.isEnabled ?? false, // Reflects current loaded config
                    "configurableParameters": Self.describeParameters(for: monitorType)
                ]
            }
            
            return [
                "appName": self.appName,
                "configSchemaVersion": self.currentConfig.schemaVersion,
                "configFileLocation": self.configFileURL.path,
                "availableEventMonitors": availableMonitors,
                "availableEventTypes": RedEyeEventType.allCases.map { $0.rawValue }, // Assuming RedEyeEventType is CaseIterable
                "generalSettingsFields": [
                    "showPluginPanelOnHotkeyCapture: Bool"
                ]
            ]
        }
    }

    // Helper for getCapabilities to describe parameters for each monitor type
    private static func describeParameters(for monitorType: MonitorType) -> [String: String] {
        switch monitorType {
        case .fsEventMonitorManager:
            return ["paths": "[String] (e.g., [\"~/Documents\", \"/tmp\"])"]
        case .appActivationMonitor:
            return ["enableBrowserURLCapture": "Bool (for Safari URL PoC)"]
        case .keyboardMonitorManager:
            return ["exampleDebounceInterval": "Double (seconds, hypothetical example)"]
        // Add descriptions for other monitors as they get configurable parameters
        default:
            return ["note": "No specific parameters defined for this monitor type yet."]
        }
    }
}

// JSONValue.debugDescription for cleaner logging in setMonitorParameters (add to RedEye/IPC/IPCCommand.swift if not already there)
extension JSONValue {
    var debugDescription: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .array(let a): return "[" + a.map { $0.debugDescription }.joined(separator: ", ") + "]"
        case .dictionary(let dict): return "[" + dict.map { "\"\($0.key)\": \($0.value.debugDescription)" }.joined(separator: ", ") + "]"
        case .null: return "null"
        }
    }
}

// Define potential errors
enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case directoryCreationFailed(Error)
    case serializationFailed(Error)
    case deserializationFailed(Error)
    case fileReadFailed(Error)
    case fileWriteFailed(Error)
    case unknownMonitorType(String)
    case invalidParameter(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Configuration file not found."
        case .directoryCreationFailed(let err): return "Failed to create configuration directory: \(err.localizedDescription)"
        case .serializationFailed(let err): return "Failed to serialize configuration: \(err.localizedDescription)"
        case .deserializationFailed(let err): return "Failed to deserialize configuration: \(err.localizedDescription)"
        case .fileReadFailed(let err): return "Failed to read configuration file: \(err.localizedDescription)"
        case .fileWriteFailed(let err): return "Failed to write configuration file: \(err.localizedDescription)"
        case .unknownMonitorType(let type): return "Unknown monitor type encountered: \(type)."
        case .invalidParameter(let desc): return "Invalid configuration parameter: \(desc)."
        }
    }
}
