// RedEye/App/AppDelegate.swift

import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    var hotkeyManager: HotkeyManager?
    var eventManager: EventManager?
    var pluginManager: PluginManager?
    var uiManager: UIManager?
    var webSocketServerManager: WebSocketServerManager?
    var inputMonitorManager: InputMonitorManager? // For mouse-based selection
    var appActivationMonitor: AppActivationMonitor?
    var fsEventMonitorManager: FSEventMonitorManager?
    var keyboardMonitorManager: KeyboardMonitorManager? // <<< NEW Property

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check and request Accessibility permissions (already needed for text selection)
        _ = self.checkAndRequestAccessibilityPermissions() // Result ignored for now
        
        // --- Manager Initialization Order ---
        // Generally: Utils -> Core Logic -> Monitors/Servers -> UI-related
        
        // 1. Plugin Manager (Standalone)
        self.pluginManager = PluginManager()
        
        // 2. WebSocket Server (Needed by EventManager)
        self.webSocketServerManager = WebSocketServerManager()

        // 3. Event Manager (Needs WebSocketServer, Acts as Delegate for Monitors)
        guard let pManager = self.pluginManager, let wsManager = self.webSocketServerManager else {
            fatalError("CRITICAL ERROR: PluginManager or WebSocketServerManager could not be initialized.")
        }
        // EventManager now also acts as KeyboardEventMonitorDelegate
        self.eventManager = EventManager(webSocketServerManager: wsManager)
        guard let evtManager = self.eventManager else {
             fatalError("CRITICAL ERROR: EventManager could not be initialized.")
        }

        // 4. UI Manager (Needs PluginManager)
        self.uiManager = UIManager(pluginManager: pManager)
        guard let uiMgr = self.uiManager else {
            fatalError("CRITICAL ERROR: UIManager could not be initialized.")
        }

        // 5. Hotkey Manager (Needs EventManager, UIManager, acts as InputMonitor delegate)
        self.hotkeyManager = HotkeyManager(eventManager: evtManager, uiManager: uiMgr)
        
        // 6. Input Monitor (Mouse Selection - Needs HotkeyManager as delegate)
        self.inputMonitorManager = InputMonitorManager()
        self.inputMonitorManager?.delegate = self.hotkeyManager // HotkeyManager implements the delegate protocol

        // 7. App Activation Monitor (Needs EventManager)
        self.appActivationMonitor = AppActivationMonitor(eventManager: evtManager)
        
        // 8. FS Event Monitor (Needs EventManager as delegate)
        self.fsEventMonitorManager = FSEventMonitorManager(delegate: evtManager) // Pass EventManager as delegate
        // Optional: Add developer toggle for FS Monitor here if needed
        // self.fsEventMonitorManager?.isEnabled = false // Example: Disable FS monitor

        // 9. Keyboard Monitor (Needs EventManager as delegate) <<< NEW
        self.keyboardMonitorManager = KeyboardMonitorManager(delegate: evtManager) // Pass EventManager as delegate
        // Optional: Add developer toggle for Keyboard Monitor
        // self.keyboardMonitorManager?.isEnabled = false // Example: Disable keyboard monitor
        
        // --- Start Services ---
        
        self.webSocketServerManager?.startServer()
        self.inputMonitorManager?.startMonitoring() // Start mouse monitor
        self.appActivationMonitor?.startMonitoring()
        self.fsEventMonitorManager?.startMonitoring() // Start FS monitor
        self.keyboardMonitorManager?.startMonitoring() // Start keyboard monitor <<< NEW
        
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
        // Stop in reverse order of start, generally
        keyboardMonitorManager?.stopMonitoring() // <<< NEW
        fsEventMonitorManager?.stopMonitoring()
        appActivationMonitor?.stopMonitoring()
        inputMonitorManager?.stopMonitoring()
        webSocketServerManager?.stopServer()
        // Other managers (HotkeyManager, EventManager, PluginManager, UIManager) don't have explicit stop methods currently.
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
