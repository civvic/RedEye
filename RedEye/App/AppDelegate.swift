// RedEye/App/AppDelegate.swift

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    // Core services/managers that don't depend on much else initially
    let eventBus: EventBus = MainEventBus()
    var configurationManager: ConfigurationManaging?
    var ipcCommandHandler: IPCCommandHandler?

    var pluginManager: PluginManager?
    var uiManager: UIManager?
    var webSocketServerManager: WebSocketServerManager?
    
    // Event emitting managers:
    var hotkeyManager: HotkeyManager?
    var inputMonitorManager: InputMonitorManager?
    var appActivationMonitor: AppActivationMonitor?
    var fsEventMonitorManager: FSEventMonitorManager?
    var keyboardMonitorManager: KeyboardMonitorManager?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        _ = self.checkAndRequestAccessibilityPermissions() // Result ignored for now
        
        // --- Manager Initialization Order ---
        // 1. Configuration Manager (needed by other managers)
        self.configurationManager = ConfigurationManager()
        guard let configManager = self.configurationManager else {
            RedEyeLogger.fault("CRITICAL: ConfigurationManager could not be initialized in AppDelegate. RedEye will not function correctly.", category: "AppDelegate")
            // Consider a more graceful shutdown or error display if this happens.
            // For now, app might continue but config-dependent features will fail.
            // If ConfigurationManager's init itself can fatalError for critical issues, that's another approach.
            return // Or NSApp.terminate(nil) if unrecoverable
        }
        RedEyeLogger.info("ConfigurationManager loaded/initialized.", category: "AppDelegate")

        // 2. IPC Command Handler (depends on ConfigurationManager)
        self.ipcCommandHandler = IPCCommandHandler(configManager: configManager) // << MODIFIED
        guard let ipcHandler = self.ipcCommandHandler else {
            fatalError("CRITICAL ERROR: IPCCommandHandler could not be initialized.")
        }
        RedEyeLogger.info("IPCCommandHandler initialized.", category: "AppDelegate")

        // 3. Other Managers (Plugin, UI, Monitors, Servers)
        self.pluginManager = PluginManager()
        self.webSocketServerManager = WebSocketServerManager(eventBus: self.eventBus, ipcCommandHandler: ipcHandler)
        
        guard let pManager = self.pluginManager, self.webSocketServerManager != nil else {
            fatalError("CRITICAL ERROR: PluginManager or WebSocketServerManager could not be initialized.")
        }

        self.uiManager = UIManager(pluginManager: pManager)
        guard let uiMgr = self.uiManager else { fatalError("CRITICAL ERROR: UIManager could not be initialized.") }

        // Initialize Monitor Managers (they now take configManager)
        self.hotkeyManager = HotkeyManager(eventBus: self.eventBus, uiManager: uiMgr, configManager: configManager)
        self.inputMonitorManager = InputMonitorManager(configManager: configManager) // Delegate set below
        self.appActivationMonitor = AppActivationMonitor(eventBus: self.eventBus, configManager: configManager)
        self.fsEventMonitorManager = FSEventMonitorManager(eventBus: self.eventBus, configManager: configManager)
        self.keyboardMonitorManager = KeyboardMonitorManager(eventBus: self.eventBus, configManager: configManager)
        
        // Set delegates if needed (after both objects are initialized)
        self.inputMonitorManager?.delegate = self.hotkeyManager
        
        RedEyeLogger.info("All core managers initialized.", category: "AppDelegate")

        // --- Start Services ---
        // Call the 'start()' method from BaseMonitorManager for monitor managers.
        // Managers will internally check their 'isEnabled' status from config.
        self.webSocketServerManager?.startServer() // This one is not a BaseMonitorManager subclass

        self.hotkeyManager?.start()
        self.inputMonitorManager?.start()
        self.appActivationMonitor?.start()
        self.fsEventMonitorManager?.start()
        self.keyboardMonitorManager?.start()

        RedEyeLogger.info("All services/monitors started (or attempted based on configuration).", category: "AppDelegate")

        // --- Status item setup code ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        RedEyeLogger.info("RedEye application finished launching. All managers initialized. Monitors started (or ready, based on config).", category: "AppDelegate")
        
#if DEBUG
        RedEyeLogger.isVerboseLoggingEnabled = true
        print("RedEye Dev Note: Verbose debug logging is ENABLED (DEBUG build).")
#else
        print("RedEye Info: Verbose debug logging is DISABLED (Release build).")
#endif
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        RedEyeLogger.info("RedEye application will terminate. Stopping services...", category: "AppDelegate")
        // Call 'stop()' method from BaseMonitorManager for monitor managers.
        self.keyboardMonitorManager?.stop()
        self.fsEventMonitorManager?.stop()
        self.appActivationMonitor?.stop()
        self.inputMonitorManager?.stop()
        self.hotkeyManager?.stop()
        self.webSocketServerManager?.stopServer() // Not a BaseMonitorManager subclass
        RedEyeLogger.info("All services/monitors stopped.", category: "AppDelegate")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @discardableResult // Allow ignoring return value
    func checkAndRequestAccessibilityPermissions() -> Bool {
        // Check status first without prompting
        let currentStatus = AXIsProcessTrusted()
        if currentStatus {
            RedEyeLogger.info("Accessibility permissions: Granted.", category: "AppDelegate")
            return true
        } else {
            RedEyeLogger.info("Accessibility permissions: Not granted. Requesting...", category: "AppDelegate")
            // Use prompt option
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if !accessEnabled {
                RedEyeLogger.error("Accessibility permissions still not granted after prompt (or prompt failed). The user may need to grant manually in System Settings.", category: "AppDelegate")
            } else {
                // Note: Even if it returns true here, sometimes a restart is needed for changes to fully apply.
                RedEyeLogger.info("Accessibility permissions prompt acknowledged. Status may require app restart to be fully effective if granted.", category: "AppDelegate")
            }
            return accessEnabled
        }
    }
}
