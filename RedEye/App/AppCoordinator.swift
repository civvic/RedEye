// RedEye/App/AppCoordinator.swift

import Foundation // Or Cocoa if any AppKit types are needed directly, but likely just Foundation for now

class AppCoordinator {

    private static let logCategory = "AppCoordinator"

    // Core services/managers
    let eventBus: EventBus
    let configurationManager: ConfigurationManaging
    let ipcCommandHandler: IPCCommandHandler

    // Other managers
    let pluginManager: PluginManager
    let uiManager: UIManager // UIManager might need access to other managers or coordinators later
    let webSocketServerManager: WebSocketServerManager
    
    // Event emitting managers (BaseMonitorManager subclasses)
    let hotkeyManager: HotkeyManager
    let inputMonitorManager: InputMonitorManager
    let appActivationMonitor: AppActivationMonitor
    let fsEventMonitorManager: FSEventMonitorManager
    let keyboardMonitorManager: KeyboardMonitorManager
    
    // TODO: Consider if any other services previously in AppDelegate need to be here.

    init() {
        RedEyeLogger.info("AppCoordinator initializing...", category: AppCoordinator.logCategory)

        // --- Initialize Core Services ---
        self.eventBus = MainEventBus()
        self.configurationManager = ConfigurationManager() // Assumes ConfigurationManager() is the correct public init
        
        // IPCCommandHandler depends on ConfigurationManager
        self.ipcCommandHandler = IPCCommandHandler(configManager: self.configurationManager)
        
        // --- Initialize Other Managers ---
        self.pluginManager = PluginManager()
        
        // WebSocketServerManager depends on EventBus and IPCCommandHandler
        self.webSocketServerManager = WebSocketServerManager(eventBus: self.eventBus, ipcCommandHandler: self.ipcCommandHandler)
        
        // UIManager depends on PluginManager
        self.uiManager = UIManager(pluginManager: self.pluginManager)
        
        // --- Initialize Monitor Managers ---
        // These depend on EventBus (optional for some), ConfigurationManager, and potentially UIManager
        
        self.hotkeyManager = HotkeyManager(
            eventBus: self.eventBus,
            uiManager: self.uiManager,
            configManager: self.configurationManager
        )
        
        self.inputMonitorManager = InputMonitorManager(configManager: self.configurationManager)
        // Delegate setup: InputMonitorManager's delegate is HotkeyManager
        self.inputMonitorManager.delegate = self.hotkeyManager
        
        self.appActivationMonitor = AppActivationMonitor(
            eventBus: self.eventBus,
            configManager: self.configurationManager
        )
        
        self.fsEventMonitorManager = FSEventMonitorManager(
            eventBus: self.eventBus,
            configManager: self.configurationManager
        )
        
        self.keyboardMonitorManager = KeyboardMonitorManager(
            eventBus: self.eventBus,
            configManager: self.configurationManager
        )
        
        RedEyeLogger.info("All managers initialized within AppCoordinator.", category: AppCoordinator.logCategory)
    }

    /// Starts all necessary services and monitors.
    func start() {
        RedEyeLogger.info("AppCoordinator starting services...", category: AppCoordinator.logCategory)
        
        // Start servers first, then monitors
        webSocketServerManager.startServer()

        // Start monitor managers (which now use their config to decide if they actually activate)
        hotkeyManager.start()
        inputMonitorManager.start()
        appActivationMonitor.start()
        fsEventMonitorManager.start()
        keyboardMonitorManager.start()
        
        RedEyeLogger.info("All services/monitors started by AppCoordinator.", category: AppCoordinator.logCategory)
    }

    /// Stops all services and monitors gracefully.
    func stop() {
        RedEyeLogger.info("AppCoordinator stopping services...", category: AppCoordinator.logCategory)
        
        // Stop monitors first
        keyboardMonitorManager.stop()
        fsEventMonitorManager.stop()
        appActivationMonitor.stop()
        inputMonitorManager.stop()
        hotkeyManager.stop()
        
        // Stop servers
        webSocketServerManager.stopServer()
        
        // Other cleanup if necessary (e.g., for PluginManager or UIManager if they had stop methods)
        
        RedEyeLogger.info("All services/monitors stopped by AppCoordinator.", category: AppCoordinator.logCategory)
    }
}
