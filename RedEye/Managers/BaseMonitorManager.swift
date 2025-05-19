// RedEye/Managers/BaseMonitorManager.swift

import Foundation

class BaseMonitorManager: MonitorLifecycleManaging, MonitorConfigurable {

    let monitorType: MonitorType
    let eventBus: EventBus?
    private weak var configManager: ConfigurationManaging?
    private(set) var currentMonitorConfig: MonitorSpecificConfig?
    private(set) var currentGeneralAppSettings: GeneralAppSettings?
    private(set) var isCurrentlyActive: Bool = false
    var logCategory: String { return "\(String(describing: type(of: self)))" }

    init(monitorType: MonitorType, eventBus: EventBus?, configManager: ConfigurationManaging?) {
        self.monitorType = monitorType
        self.eventBus = eventBus
        self.configManager = configManager
        RedEyeLogger.info("\(monitorType.rawValue): Initialized. Will apply config on start().", category: logCategory)
    }

    deinit {
        RedEyeLogger.info("\(monitorType.rawValue): Deinitializing. Ensuring it's stopped.", category: logCategory)
        // Automatically stop when deinitializing to release resources, if not already stopped.
        // This relies on stopMonitoring() being safe to call even if not fully started.
        if isCurrentlyActive { // Only call performStop if it was active
            stopMonitoring()
        }
    }

    // MARK: - MonitorLifecycleManaging Conformance

    final func start() { // This is the public method clients call
        guard let configProvider = self.configManager else {
            RedEyeLogger.error("\(monitorType.rawValue): ConfigurationManager is not available. Cannot start.", category: logCategory)
            isCurrentlyActive = false
            return
        }

        guard let specificConfig = configProvider.getMonitorSetting(for: self.monitorType) else {
            RedEyeLogger.error("\(monitorType.rawValue): Could not retrieve specific monitor settings. Cannot start.", category: logCategory)
            isCurrentlyActive = false
            return
        }
        let generalSettings = configProvider.getGeneralSettings()
        
        if applyConfiguration(config: specificConfig, generalSettings: generalSettings) {
            RedEyeLogger.info("\(monitorType.rawValue): Configuration applied (indicates enabled). Attempting specific monitoring start.", category: logCategory)
            if self.startMonitoring() { // Call the overridable method
                self.isCurrentlyActive = true // Set by base on success
                RedEyeLogger.info("\(monitorType.rawValue): Specific monitoring reported SUCCESSFUL start.", category: logCategory)
            } else {
                self.isCurrentlyActive = false // Set by base on failure
                RedEyeLogger.error("\(monitorType.rawValue): Specific monitoring reported FAILED to start. Ensuring it is stopped.", category: logCategory)
                // Call stopMonitoring() to ensure any partial setup by the subclass is cleaned up.
                self.stopMonitoring() // Call the overridable stop
            }
        } else {
            // Configuration indicates monitor should be disabled
            RedEyeLogger.info("\(monitorType.rawValue): Configuration indicates monitor should not be active (disabled). Ensuring specific monitoring is stopped.", category: logCategory)
            self.isCurrentlyActive = false // Ensure state reflects disabled config
            self.stopMonitoring() // Call the overridable stop
        }
    }

    final func stop() { // This is the public method clients call
        RedEyeLogger.info("\(monitorType.rawValue): Explicit stop called. Stopping specific monitoring.", category: logCategory)
        stopMonitoring()
        isCurrentlyActive = false
    }

    // MARK: - MonitorConfigurable Conformance

    @discardableResult
    func applyConfiguration(config: MonitorSpecificConfig, generalSettings: GeneralAppSettings?) -> Bool {
        self.currentMonitorConfig = config
        self.currentGeneralAppSettings = generalSettings
        
        RedEyeLogger.info("\(monitorType.rawValue): Applying configuration. isEnabled: \(config.isEnabled).", category: logCategory)
        
        if config.isEnabled {
            // isCurrentlyActive will be definitively set by the result of startMonitoring() call,
            // or if start() short-circuits. Here, we just indicate if config *allows* activation.
            RedEyeLogger.info("\(monitorType.rawValue): Configured as ENABLED.", category: logCategory)
            return true
        } else {
            isCurrentlyActive = false // If config says disabled, it's not active.
            RedEyeLogger.info("\(monitorType.rawValue): Configured as DISABLED.", category: logCategory)
            return false
        }
    }

    // MARK: - Methods for Subclass Override

    /// Subclasses MUST override this to implement their specific startup logic.
    /// Called by the public `start()` method if configuration allows.
    /// - Returns: `true` if monitoring started successfully, `false` otherwise.
    func startMonitoring() -> Bool { // << MODIFIED: Signature returns Bool
        RedEyeLogger.debug("\(monitorType.rawValue): startMonitoring() -> Bool was called but NOT overridden by subclass \(String(describing: type(of: self))). This monitor will not effectively start.", category: logCategory)
        return false // Default to failure
    }

    /// Subclasses MUST override this to implement their specific shutdown and cleanup logic.
    /// Called by the public `stop()` method, and by `start()` if starting fails or config disables.
    func stopMonitoring() { // << No change in signature, but context is important
        RedEyeLogger.debug("\(monitorType.rawValue): stopMonitoring() was called but NOT overridden by subclass \(String(describing: type(of: self))). Resources may not be cleaned up.", category: logCategory)
    }
}
