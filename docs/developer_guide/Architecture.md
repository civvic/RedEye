# RedEye Technical Architecture Overview (v0.4)

**Version:** 0.4.0 
**Last Updated:** May 21, 2025 

### 1. Introduction

This document provides an overview of the technical architecture of RedEye as of version 0.4.0. RedEye is a lightweight macOS menu bar "sensorium" application designed to capture a wide array of user gestures and system events, communicating them via IPC (WebSockets) to external 'Agent' applications.

Version 0.3 expanded System Event capture and refactored internal event/IPC handling. **Version 0.4.0 has significantly matured RedEye by implementing a robust Configuration System, further improving code quality through major refactoring (AppCoordinator, TextCaptureService), and enhancing the developer experience with an improved logging system.**

**Key Architectural Achievements in v0.4.0:**

*   **Configuration System:**
    *   A central **`ConfigurationManager`** now manages application settings loaded from `~/.redeye/config.json`, handling defaults and persistence.
    *   A structured **`RedEyeConfig`** model defines all configurable aspects, including monitor enablement, parameters, general app settings, and logging verbosity.
    *   IPC commands allow runtime querying and modification of the configuration by Agents.
*   **Core Component Refactoring:**
    *   **`AppCoordinator`:** Introduced to handle the initialization and lifecycle management of core managers, significantly simplifying `AppDelegate`.
    *   **`TextCaptureService`:** Accessibility API logic for capturing selected text has been decoupled from `HotkeyManager` into this dedicated service.
*   **Managerial Abstractions & Standardization:**
    *   **`BaseMonitorManager`** class and `MonitorLifecycleManaging`, `MonitorConfigurable` protocols standardize how event monitor managers consume configuration and manage their lifecycle (`start`/`stop`). All event monitors now inherit from `BaseMonitorManager`.
*   **Enhanced Logging System:**
    *   A new **`Loggable` protocol** and instance-based loggers (`self.info(...)`) provide cleaner, context-aware logging with reduced boilerplate.
    *   Log levels (`fault`, `error`, `warning`, `info`, `debug`, `trace`) are defined, and the application's global log verbosity (`RedEyeLogger.currentLevel`) can now be set via `config.json`.
*   **IPC Enhancements:**
    *   The IPC command set handled by `IPCCommandHandler` was expanded for comprehensive configuration management.
    *   `WebSocketServerManager` now supports request-response for these commands.
*   **Documentation Structure:** All project documentation (PRDs, Roadmaps, Architecture, User/Developer Guides, API References) is now managed under a `/docs` directory within the Git repository.

This version focuses on making RedEye more configurable, maintainable, and robust, laying a strong foundation for future feature development.

### 2. Core Components & Structure (v0.4.0)

RedEye is a Swift-based macOS menu bar application.

**Overall Application Flow Orchestration:**
*   **`AppDelegate`**: Minimalist. Handles `NSApplication` lifecycle callbacks and delegates core application setup and teardown to `AppCoordinator`. Manages the status bar item and initial permission requests (e.g., Accessibility).
*   **`AppCoordinator`**: Central class responsible for instantiating, wiring together, and managing the lifecycle (`start`/`stop`) of all core services and managers (e.g., `ConfigurationManager`, `EventBus`, `IPCCommandHandler`, `WebSocketServerManager`, all monitor managers, `TextCaptureService`).

**Key Components:**

**Config Folder (`RedEye/Config/`):**
*   **`RedEyeConfig.swift`**: Defines `Codable` data structures for application configuration:
    *   `RedEyeConfig`: Top-level struct (schema version, monitor settings, general app settings).
    *   `MonitorType` (enum): Identifies all configurable monitor managers (e.g., `keyboardMonitorManager`, `fsEventMonitorManager`).
    *   `MonitorSpecificConfig`: Holds `isEnabled` (Bool) and `parameters` (`[String: JSONValue]?`) for each monitor.
    *   `GeneralAppSettings`: Holds global settings like `showPluginPanelOnHotkeyCapture` (Bool) and `logLevel` (`RedEyeLogger.LogLevel?`).
    *   Includes `RedEyeConfig.defaultConfig()` for generating factory defaults.
*   **`ConfigurationManager.swift`**:
    *   Implements `ConfigurationManaging` protocol.
    *   Manages loading `RedEyeConfig` from `~/.redeye/config.json`.
    *   Creates `config.json` with defaults if missing or corrupt.
    *   Provides thread-safe methods for accessing and modifying configuration.
    *   Persists runtime configuration changes (e.g., from IPC commands) back to `config.json`.
    *   Sets `RedEyeLogger.currentLevel` based on loaded configuration.

**Events Folder (`RedEye/Events/`):**
*   **`RedEyeEvent.swift`**: Defines `RedEyeEvent` (struct) and `RedEyeEventType` (enum, now `CaseIterable`).
*   **`EventBus.swift`**: Defines `EventBus` and `EventBusSubscriber` protocols.
*   **`MainEventBus.swift`**: Concrete `EventBus` implementation for decoupled event propagation.

**IPC Folder (`RedEye/IPC/`):**
*   **`IPCCommand.swift`**:
    *   `IPCReceivedCommand`: Structure for incoming client commands.
    *   `IPCAction` (enum): Significantly expanded with actions for configuration management (e.g., `getConfig`, `setMonitorEnabled`, `getCapabilities`, `resetConfigToDefaults`).
    *   Defines various `Codable` payload structs for specific commands.
    *   `IPCResponseWrapper`: Generic struct to standardize the JSON format of responses to clients (`status`, `message`, `data`, `commandId`).
    *   `JSONValue` enum for flexible JSON payloads.
*   **`IPCCommandHandler.swift`**:
    *   Initialized with `ConfigurationManager`.
    *   Parses raw commands, routes based on `IPCAction`.
    *   Handles configuration commands by interacting with `ConfigurationManager`.
    *   Generates JSON response strings (success/error/data) for `WebSocketServerManager` to send back.

**Managers Folder (`RedEye/Managers/`):**
*   **`MonitorProtocols.swift`**:
    *   `MonitorLifecycleManaging`: Protocol defining `start()` and `stop()` methods.
    *   `MonitorConfigurable`: Protocol defining `monitorType`, `applyConfiguration(...)`, and `isCurrentlyActive`.
*   **`BaseMonitorManager.swift`**:
    *   Abstract base class for all event monitor managers.
    *   Implements `MonitorLifecycleManaging`, `MonitorConfigurable`, and `Loggable`.
    *   Handles common tasks: fetching configuration from `ConfigurationManager`, checking `isEnabled` status, calling subclass overrides for specific monitoring logic (`startMonitoring() -> Bool`, `stopMonitoring()`).
    *   Manages `isCurrentlyActive` state based on configuration and subclass startup success.
    *   Provides an `instanceLogger` via `Loggable` conformance.
*   **Event Monitor Managers** (e.g., `AppActivationMonitor.swift`, `FSEventMonitorManager.swift`, `HotkeyManager.swift`, `InputMonitorManager.swift`, `KeyboardMonitorManager.swift`):
    *   All now inherit from `BaseMonitorManager`.
    *   Receive `ConfigurationManager` (and `EventBus` where needed) via `super.init()`.
    *   Override `logCategoryForInstance: String` for specific logging.
    *   Implement `override func startMonitoring() -> Bool` for their specific setup (e.g., creating event taps, registering observers) and report success/failure.
    *   Implement `override func stopMonitoring()` for specific cleanup.
    *   Use `self.info(...)`, `self.debug(...)` etc., for logging, leveraging the `Loggable` protocol.
*   **`PluginManager.swift`**: (No major architectural changes in v0.4).
*   **`UIManager.swift`**: (No major architectural changes in v0.4). `HotkeyManager` still uses it.
*   **`WebSocketServerManager.swift`**:
    *   Initialized with `EventBus` and `IPCCommandHandler`.
    *   Subscribes to `EventBus` to broadcast `RedEyeEvent`s.
    *   For incoming client messages (`onText`):
        *   Passes raw command string to `IPCCommandHandler.handleRawCommand()`.
        *   Receives a response string (JSON) from `IPCCommandHandler`.
        *   Sends this response string back to the originating WebSocket client using `try await ws.send()`.

**Services Folder (`RedEye/Services/` - New):**
*   **`TextCaptureService.swift`**:
    *   New service dedicated to capturing selected text using macOS Accessibility APIs.
    *   Used by `HotkeyManager` to decouple text-capturing logic.
    *   Returns a `TextCaptureResult` struct (includes text, app info, and potential errors via `TextCaptureError` enum).
    *   Conforms to `Loggable`.

**Utilities Folder (`RedEye/Utilities/`):**
*   **`RedEyeLogger.swift`**:
    *   Defines `Loggable` protocol.
    *   Defines `RedEyeLogger.LogLevel` enum (`fault` to `trace`), which is `Codable`.
    *   `RedEyeLogger.currentLevel` (static var) controls global log verbosity, settable by `ConfigurationManager` from `config.json`.
    *   Static logging methods (`RedEyeLogger.info()`, etc.) check `currentLevel` and include file/line/function context.
    *   Extension methods for `Loggable` (`self.info()`, etc.) use an `instanceLogger` (configured with a specific category per type) and also check `currentLevel` and add context.
    *   Removed old `isVerboseLoggingEnabled` flag.

### 3. Key Workflows (v0.4.0)

1.  **Application Startup (Orchestrated by `AppCoordinator`):**
    1.  `AppDelegate.applicationDidFinishLaunching` creates and starts `AppCoordinator`.
    2.  `AppCoordinator.init()`:
        *   Instantiates `ConfigurationManager`, which loads `config.json` or creates defaults. `RedEyeLogger.currentLevel` is set from this config.
        *   Instantiates `EventBus`, `IPCCommandHandler` (with `ConfigurationManager`), `TextCaptureService`.
        *   Instantiates all other managers, including monitor managers (passing `ConfigurationManager`, `EventBus`, and other specific dependencies like `UIManager` or `TextCaptureService`).
    3.  `AppCoordinator.start()`:
        *   Calls `startServer()` on `WebSocketServerManager`.
        *   Calls `start()` on each monitor manager instance (which are `BaseMonitorManager` subclasses).
        *   Each monitor manager's `BaseMonitorManager.start()` sequence:
            *   Fetches its `MonitorSpecificConfig` and `GeneralAppSettings` from `ConfigurationManager`.
            *   Calls `applyConfiguration()` (sets `currentMonitorConfig`, returns if it *should* activate based on `isEnabled`).
            *   If configuration allows activation, calls the subclass's overridden `startMonitoring() -> Bool`.
            *   If subclass `startMonitoring()` returns `true`, `isCurrentlyActive` is set to `true`. If `false`, `isCurrentlyActive` is `false` and `stopMonitoring()` is called for cleanup.

2.  **Event Capturing & Broadcasting:**
    *   An active monitor manager (where `isCurrentlyActive` is `true`) captures a native macOS event.
    *   It creates a `RedEyeEvent` object.
    *   It calls `self.eventBus?.publish(event: anEvent)`.
    *   `MainEventBus` dispatches the event to subscribers (e.g., `WebSocketServerManager`).
    *   `WebSocketServerManager.handleEvent` serializes and broadcasts the event to connected clients.

3.  **IPC Command Processing (e.g., `setMonitorEnabled`):**
    1.  Agent sends JSON command: `{"action": "setMonitorEnabled", "payload": {"monitorType": "...", "isEnabled": ...}}`.
    2.  `WebSocketServerManager.onText` receives it.
    3.  Calls `await ipcCommandHandler.handleRawCommand(...)`.
    4.  `IPCCommandHandler`:
        *   Decodes command and payload.
        *   Identifies action, calls `configManager.setMonitorEnabled(...)`.
    5.  `ConfigurationManager`:
        *   Updates its in-memory `currentConfig`.
        *   Saves `currentConfig` to `~/.redeye/config.json`.
        *   *(Future: Could trigger a notification for live config updates within RedEye).*
    6.  `IPCCommandHandler` creates a JSON success/error response string.
    7.  `WebSocketServerManager` sends this response string back to the client.

4.  **Text Capture Flow (e.g., via Hotkey):**
    1.  User presses ⌘⇧C. `HotkeyManager`'s `KeyboardShortcuts` handler fires.
    2.  Handler checks if `HotkeyManager` `isCurrentlyActive`.
    3.  Calls `textCaptureService.captureSelectedTextFromFrontmostApp()`.
    4.  `TextCaptureService` uses Accessibility API to get selected text and source app info, returning a `TextCaptureResult`.
    5.  `HotkeyManager` creates a `.textSelection` `RedEyeEvent` using data from `TextCaptureResult`.
    6.  Publishes event to `EventBus`.
    7.  If `generalSettings.showPluginPanelOnHotkeyCapture` is true (from `ConfigurationManager`), calls `uiManager.showPluginActionsPanel(...)`.

### 4. Configuration System (`config.json`)

*   **Location:** `~/Library/Application Support/RedEye/config.json`. Automatically created with defaults if missing.
*   **Format:** JSON, defined by `RedEyeConfig` Swift struct.
*   **Key Contents:** `schemaVersion`, `monitorSettings` (per-monitor `isEnabled`, `parameters`), `generalSettings` (`showPluginPanelOnHotkeyCapture`, `logLevel`).
*   **Management:** Loaded/saved by `ConfigurationManager`. Modifiable via IPC. Changes require app restart for monitors to pick up, unless live reloading is implemented. IPC-driven log level changes are immediate.

### 5. External Dependencies
*   **WebSocketKit:** For WebSocket server implementation.
*   **KeyboardShortcuts:** For global hotkey management.
*   **macOS Frameworks:** AppKit, Foundation, CoreServices (FSEvents), ApplicationServices (Accessibility, CGEventTaps).

### 6. Permissions Required
*   **Accessibility:** For text capture.
*   **Input Monitoring:** For global keyboard events (if `KeyboardMonitorManager` is enabled).
*   **Full Disk Access (Potentially):** For `FSEventMonitorManager` if watching restricted paths.
*   **Automation (Safari - Experimental):** If `enableBrowserURLCapture` is used.

### 7. Build & Development
*   Xcode project (`RedEye.xcodeproj`).
*   Swift Package Manager for `WebSocketKit` and `KeyboardShortcuts`.
*   Unit tests for `ConfigurationManager` and `MainEventBus`.
*   Logging managed by `RedEyeLogger` (wrapper around `os.Logger`), with configurable levels.
*   All documentation now stored in `/docs` directory in the repository.

### 8. Future Considerations (Beyond v0.4 Initial Release)
*   **Server-Side Event Filtering for IPC Clients.**
*   **Live Configuration Reloading:** Allowing monitors and services to react to configuration changes (from file or IPC) without an app restart.
*   **Advanced Logging:** More granular per-module log level control at runtime if needed.
*   **Comprehensive Unit & Integration Testing:** Expand coverage for all components and workflows, potentially with UI test automation for key user interactions.
*   **Configuration UI:** A settings window for easier configuration management by the user.
*   **Schema Migration for `config.json`:** Robust handling of changes to the config file structure across versions.
*   *(Other items from previous architecture docs, e.g., advanced synthetic events, rule engine, remain long-term considerations).*
