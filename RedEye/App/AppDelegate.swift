// RedEye/App/AppDelegate.swift

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    var hotkeyManager: HotkeyManager? // Doesn't emit events directly, controls UI/triggers text fetch
    var eventManager: EventManager?
    var pluginManager: PluginManager? // Doesn't emit system events
    var uiManager: UIManager?         // Doesn't emit system events
    var webSocketServerManager: WebSocketServerManager? // Doesn't emit system events itself
    
    // Event emitting managers:
    var inputMonitorManager: InputMonitorManager? // Mouse Selection -> textSelection event
    var appActivationMonitor: AppActivationMonitor? // App Activation -> applicationActivated event
    var fsEventMonitorManager: FSEventMonitorManager? // FS Change -> fileSystemEvent event
    var keyboardMonitorManager: KeyboardMonitorManager? // Keyboard -> keyboardEvent event
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions (already needed for text selection)
        _ = self.checkAndRequestAccessibilityPermissions() // Result ignored for now
        
        // --- Manager Initialization Order ---
        // Generally: Utils -> Core Logic -> Monitors/Servers -> UI-related
        
        // --- Manager Initialization ---
        self.pluginManager = PluginManager()
        self.webSocketServerManager = WebSocketServerManager()
        guard let pManager = self.pluginManager, let wsManager = self.webSocketServerManager else { fatalError("...") }
        self.eventManager = EventManager(webSocketServerManager: wsManager)
        guard let evtManager = self.eventManager else { fatalError("...") }
        self.uiManager = UIManager(pluginManager: pManager)
        guard let uiMgr = self.uiManager else { fatalError("...") }
        self.hotkeyManager = HotkeyManager(eventManager: evtManager, uiManager: uiMgr)
        self.inputMonitorManager = InputMonitorManager()
        self.inputMonitorManager?.delegate = self.hotkeyManager
        self.appActivationMonitor = AppActivationMonitor(eventManager: evtManager)
        self.fsEventMonitorManager = FSEventMonitorManager(delegate: evtManager)
        self.keyboardMonitorManager = KeyboardMonitorManager(delegate: evtManager)
        
        RedEyeLogger.info("Setting default monitor states (disabled). Modify in AppDelegate for testing.", category: "AppDelegate")
        self.inputMonitorManager?.isEnabled = true
        self.appActivationMonitor?.isEnabled = false
        self.appActivationMonitor?.isEnabledBrowserURLCapture = false
        self.fsEventMonitorManager?.isEnabled = false
        self.keyboardMonitorManager?.isEnabled = false
        
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
        webSocketServerManager?.stopServer()
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
