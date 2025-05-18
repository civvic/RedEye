// RedEye/Config/RedEyeConfig.swift

import Foundation

// Enum to identify different event monitors that can be configured
// CaseIterable allows us to easily get all monitor types for default configs or capabilities.
// Codable allows it to be saved/loaded from JSON.
enum MonitorType: String, Codable, CaseIterable, Identifiable {
    // Identifiable conformance using the rawValue or self if we want MonitorType directly as ID
    var id: String { self.rawValue }

    case hotkeyManager        // Manages ⌘⇧C text capture and hotkey UI panel
    case inputMonitorManager  // Manages shortcut-less mouse selection events
    case appActivationMonitor // Manages application activation events
    case fsEventMonitorManager // Manages File System Events
    case keyboardMonitorManager // Manages Global Keyboard Events
    // Future: case browserURLMonitor (if it becomes a dedicated monitor)
}

// Configuration for a single event monitor
struct MonitorSpecificConfig: Codable {
    var isEnabled: Bool
    var parameters: [String: JSONValue]? // Monitor-specific parameters

    // Example: For FSEvents, parameters could be {"paths": .array([.string("/path/to/watch")])}
    // Example: For Keyboard, parameters could be {"debounceInterval": .double(0.5)}
    // Example: For AppActivation, could include {"enableBrowserURLCapture": .bool(true)}
}

// Top-level configuration structure for RedEye
struct RedEyeConfig: Codable {
    var schemaVersion: String // To manage future config migrations, e.g., "1.0"
    
    // Configuration for each monitor, keyed by MonitorType.rawValue for easy lookup
    var monitorSettings: [String: MonitorSpecificConfig]

    // General UI or App-level settings that aren't tied to a single event monitor
    var generalSettings: GeneralAppSettings

    // Default initializer to create a baseline configuration
    init(schemaVersion: String, monitorSettings: [String: MonitorSpecificConfig], generalSettings: GeneralAppSettings) {
        self.schemaVersion = schemaVersion
        self.monitorSettings = monitorSettings
        self.generalSettings = generalSettings
    }
}

struct GeneralAppSettings: Codable {
    // This used to be HotkeyManager.isHotkeyUiEnabled
    // If the hotkey (e.g., Cmd+Shift+C) successfully captures text, should the plugin UI panel appear?
    var showPluginPanelOnHotkeyCapture: Bool
    
    // This used to be AppActivationMonitor.isEnabledBrowserURLCapture.
    // It's now a parameter of AppActivationMonitor, but we might have a global override
    // or it's managed within appActivationMonitor's MonitorSpecificConfig.
    // Let's assume for now specific experimental features are best inside their monitor's params.
    // var experimentalBrowserURLCaptureEnabled: Bool // Example
}

// --- Helper for creating default configurations ---
extension RedEyeConfig {
    static func
defaultConfig() -> RedEyeConfig {
        var defaultMonitorSettings: [String: MonitorSpecificConfig] = [:]

        for monitorType in MonitorType.allCases {
            var defaultIsEnabled = false
            var defaultParams: [String: JSONValue]? = nil

            // Set default enabled states and parameters based on existing AppDelegate logic
            switch monitorType {
            case .hotkeyManager:
                // HotkeyManager itself (text capture part) is implicitly always "running" if app is on.
                // Its isHotkeyUiEnabled was about the *panel*. This is now in GeneralAppSettings.
                // So, for the monitor itself, it's effectively always enabled.
                // We'll use its `isEnabled` to mean "is the hotkey registration active".
                defaultIsEnabled = true // Assume hotkey registration should be active by default
            case .inputMonitorManager:
                defaultIsEnabled = false // Was `inputMonitorManager?.isEnabled = false`
            case .appActivationMonitor:
                defaultIsEnabled = false // Was `appActivationMonitor?.isEnabled = false`
                // Browser URL capture toggle will be a parameter
                defaultParams = ["enableBrowserURLCapture": .bool(false)] // Was `appActivationMonitor?.isEnabledBrowserURLCapture = false`
            case .fsEventMonitorManager:
                defaultIsEnabled = false // Was `fsEventMonitorManager?.isEnabled = false`
                // Default paths for FSEvents (e.g., Documents, Downloads)
                // These would be loaded by FSEventMonitorManager itself if its parameter is nil/empty.
                // Or we can set an empty array to mean "use internal defaults".
                defaultParams = ["paths": .array([])] // Let FSEMM use its internal defaults if paths is empty
            case .keyboardMonitorManager:
                defaultIsEnabled = true // Was `keyboardMonitorManager?.isEnabled = true`
            }
            defaultMonitorSettings[monitorType.rawValue] = MonitorSpecificConfig(isEnabled: defaultIsEnabled, parameters: defaultParams)
        }

        let defaultGeneralSettings = GeneralAppSettings(
            showPluginPanelOnHotkeyCapture: false // Was `hotkeyManager?.isHotkeyUiEnabled = false`
        )
        
        return RedEyeConfig(
            schemaVersion: "1.0", // Current version of the config structure
            monitorSettings: defaultMonitorSettings,
            generalSettings: defaultGeneralSettings
        )
    }
}
