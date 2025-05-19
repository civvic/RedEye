// RedEye/Managers/MonitorProtocols.swift

import Foundation

/// Protocol for components that have a clearly defined start and stop lifecycle.
protocol MonitorLifecycleManaging: AnyObject {
    /// Starts the component's operations.
    /// Implementation should be idempotent (safe to call multiple times if already started, though typically guarded).
    func start()

    /// Stops the component's operations and releases resources.
    /// Implementation should be idempotent.
    func stop()
}

/// Protocol for monitor components that are configurable via `MonitorSpecificConfig`.
protocol MonitorConfigurable: AnyObject {
    /// The unique type identifier for this monitor.
    var monitorType: MonitorType { get }

    /// Applies a new configuration to the monitor.
    /// This might be called during initial setup or if live configuration updates are implemented.
    /// - Parameter config: The specific configuration for this monitor.
    /// - Parameter generalSettings: The general application settings, which might also influence the monitor.
    /// - Returns: True if configuration was applied successfully and the monitor is now considered active based on this config, false otherwise.
    @discardableResult
    func applyConfiguration(config: MonitorSpecificConfig, generalSettings: GeneralAppSettings?) -> Bool
    
    /// Indicates if the monitor is currently enabled and active based on its last applied configuration.
    var isCurrentlyActive: Bool { get }
}
