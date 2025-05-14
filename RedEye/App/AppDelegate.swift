// RedEye/App/AppDelegate.swift

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    let eventBus: EventBus = MainEventBus()
    let ipcCommandHandler: IPCCommandHandler = IPCCommandHandler()

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
        // Generally: Utils -> Core Logic -> Monitors/Servers -> UI-related
        
        // --- Manager Initialization ---
        self.pluginManager = PluginManager()
        
        // WebSocketServerManager will now subscribe to the EventBus
        self.webSocketServerManager = WebSocketServerManager(eventBus: self.eventBus, ipcCommandHandler: self.ipcCommandHandler)
        
        guard let pManager = self.pluginManager, let wsManager = self.webSocketServerManager else {
            fatalError("CRITICAL ERROR: Core managers could not be initialized.")
        }

        self.uiManager = UIManager(pluginManager: pManager)
        guard let uiMgr = self.uiManager else { fatalError("CRITICAL ERROR: UIManager") }

        // Managers that previously used EventManager now get EventBus
        self.hotkeyManager = HotkeyManager(eventBus: self.eventBus, uiManager: uiMgr) // <<< MODIFIED
        
        self.inputMonitorManager = InputMonitorManager() // Delegate remains HotkeyManager
        self.inputMonitorManager?.delegate = self.hotkeyManager
        
        self.appActivationMonitor = AppActivationMonitor(eventBus: self.eventBus) // <<< MODIFIED
        self.fsEventMonitorManager = FSEventMonitorManager(eventBus: self.eventBus) // <<< MODIFIED
        self.keyboardMonitorManager = KeyboardMonitorManager(eventBus: self.eventBus) // <<< MODIFIED

        // --- Default Monitor States ---
        RedEyeLogger.info("Setting default monitor states (disabled). Modify in AppDelegate for testing.", category: "AppDelegate")
        self.inputMonitorManager?.isEnabled = false
        self.appActivationMonitor?.isEnabled = false
        self.appActivationMonitor?.isEnabledBrowserURLCapture = false
        self.fsEventMonitorManager?.isEnabled = false
        self.keyboardMonitorManager?.isEnabled = true
        
        // --- Start Services (will respect isEnabled flags) ---
        self.webSocketServerManager?.startServer()
        self.inputMonitorManager?.startMonitoring()
        self.appActivationMonitor?.startMonitoring()
        self.fsEventMonitorManager?.startMonitoring()
        self.keyboardMonitorManager?.startMonitoring()
        
        // --- Status item setup code ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "RedEye")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RedEye", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        RedEyeLogger.info("RedEye application finished launching. All managers initialized. Monitors started.", category: "AppDelegate")
        
        // Enable verbose logging for DEBUG builds
#if DEBUG
        RedEyeLogger.isVerboseLoggingEnabled = true
        print("RedEye Dev Note: Verbose debug logging is ENABLED (DEBUG build).")
#else
        print("RedEye Info: Verbose debug logging is DISABLED (Release build).")
#endif
        
        // Initial permission checks (Accessibility is checked above)
        // Input Monitoring check/prompt happens inside KeyboardMonitorManager.startMonitoring()
        // Future: Check other potential permissions here if needed (e.g., Full Disk Access if FSEvents configured broadly)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        RedEyeLogger.info("RedEye application will terminate. Stopping services...", category: "AppDelegate")
        keyboardMonitorManager?.stopMonitoring()
        fsEventMonitorManager?.stopMonitoring()
        appActivationMonitor?.stopMonitoring()
        inputMonitorManager?.stopMonitoring()
        webSocketServerManager?.stopServer() // WSSM will unsubscribe from eventBus internally
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // Renamed for clarity, as it can prompt.
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
