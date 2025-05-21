**Version:** 0.4.0 (Phase 1.A - Configuration System Implemented)
**Last Updated:** May 20, 2025 

### 1. Introduction

This document provides an overview of the technical architecture of RedEye as of version 0.4.0, focusing on the enhancements introduced in this development cycle. RedEye continues its evolution as a lightweight macOS menu bar "sensorium" application designed to capture user gestures and system events, communicating them via IPC (WebSockets) to external 'Agent' applications.

Following v0.3, which expanded System Event capture and refactored internal event/IPC handling, **v0.4.0 (Phase 1.A) has focused on maturing RedEye by implementing the first phase of a robust Configuration System.** This allows RedEye's behavior (active monitors, monitor parameters) to be configured via a JSON file (`~/.redeye/config.json`) and runtime IPC commands.

Key architectural changes in this phase include:
*   Introduction of a central **`ConfigurationManager`** responsible for loading, managing, and persisting application settings.
*   Definition of a structured **`RedEyeConfig`** model for all configurable aspects.
*   Implementation of a **`BaseMonitorManager`** class and associated `MonitorLifecycleManaging` and `MonitorConfigurable` protocols to standardize how event monitor managers consume configuration and manage their lifecycle.
*   Refactoring of all existing event monitor managers to inherit from `BaseMonitorManager`.
*   Expansion of the **IPC command set** handled by `IPCCommandHandler` to include configuration-related actions (get/set monitor states, parameters, capabilities) with responses sent back to clients.
*   Updates to `WebSocketServerManager` to facilitate these request-response IPC interactions.

This phase lays a strong foundation for a highly configurable and robust sensorium as envisioned for v0.4 and beyond.

### 2. Core Components & Structure (Updated for v0.4.0)

RedEye remains a Swift-based macOS menu bar application.

**Key Architectural Changes in v0.4.0 (Phase 1.A):**

*   **Configuration System:**
    *   **`ConfigurationManager`:** New central component. Manages `RedEyeConfig` loaded from `~/.redeye/config.json`. Creates this file with defaults if it doesn't exist. Provides methods for other components to access configuration and for IPC to modify settings at runtime. Changes made via IPC are persisted back to the file.
    *   **`RedEyeConfig.swift`:** Defines the `Codable` structs for configuration:
        *   `RedEyeConfig`: Top-level structure (schema version, monitor settings, general app settings).
        *   `MonitorType` (enum): Identifies configurable monitor managers.
        *   `MonitorSpecificConfig`: Holds `isEnabled` status and `parameters` (e.g., paths for FSEvents, `enableBrowserURLCapture` for AppActivation) for each monitor type.
        *   `GeneralAppSettings`: Holds global settings (e.g., `showPluginPanelOnHotkeyCapture`).
*   **Managerial Abstractions:**
    *   **`MonitorProtocols.swift`:**
        *   `MonitorLifecycleManaging`: Protocol for `start()` and `stop()` methods.
        *   `MonitorConfigurable`: Protocol for applying configuration and querying active state.
    *   **`BaseMonitorManager.swift`:** New abstract base class for event monitor managers.
        *   Implements `MonitorLifecycleManaging` and `MonitorConfigurable`.
        *   Holds references to `ConfigurationManager` and optionally `EventBus`.
        *   Handles common logic for fetching `MonitorSpecificConfig` and `GeneralAppSettings`.
        *   Orchestrates calling `startMonitoring() -> Bool` (overridden by subclasses) based on `isEnabled` from config, and manages the `isCurrentlyActive` state.
        *   Provides `stop()` which calls the subclass's `stopMonitoring()` override.
*   **Refactored Event Monitor Managers:** All existing event monitor managers (`AppActivationMonitor`, `FSEventMonitorManager`, `KeyboardMonitorManager`, `InputMonitorManager`, `HotkeyManager`) now:
    *   Inherit from `BaseMonitorManager`.
    *   Receive `ConfigurationManager` (and `EventBus` where applicable) in their `init` and pass them to `super.init()`.
    *   Override `startMonitoring() -> Bool` to implement their specific setup logic and report success/failure.
    *   Override `stopMonitoring()` for specific cleanup.
    *   Rely on `BaseMonitorManager` for configuration access and primary `isEnabled` checks.
    *   Removed their previous standalone `isEnabled` properties and direct developer toggles.
*   **IPC Enhancements:**
    *   **`IPCCommandHandler`:** Now takes `ConfigurationManager` in its `init`. Handles new configuration-related `IPCAction`s. Returns a `String?` (JSON response) to `WebSocketServerManager`.
    *   **`IPCCommand.swift`:** `IPCAction` enum expanded with cases like `getConfig`, `setMonitorEnabled`, `getCapabilities`, etc. New payload structs defined.
    *   **`WebSocketServerManager`:** Its `onText` handler now awaits the response from `IPCCommandHandler` and sends it back to the originating client, enabling request-response for config commands.

**App Folder:**
*   **`AppDelegate.swift`**:
    *   Instantiates `ConfigurationManager` early.
    *   Instantiates `IPCCommandHandler` with `ConfigurationManager`.
    *   Passes `ConfigurationManager` (and `EventBus` where needed) to monitor managers during their initialization.
    *   Calls the `start()` (from `BaseMonitorManager`) method on each monitor manager during `applicationDidFinishLaunching`.
    *   Calls `stop()` on monitor managers during `applicationWillTerminate`.
    *   No longer directly sets `isEnabled` flags on managers.
*   **`main.swift`**: (No change) Entry point.

**Config Folder (New):**
*   **`RedEyeConfig.swift`**: Defines the `Codable` configuration structures (`RedEyeConfig`, `MonitorType`, `MonitorSpecificConfig`, `GeneralAppSettings`) and the `defaultConfig()` factory.
*   **`ConfigurationManager.swift`**: Implements `ConfigurationManaging` protocol. Handles file I/O for `~/.redeye/config.json`, default creation, access, and modification of `RedEyeConfig`.

**Events Folder:**
*   **`RedEyeEvent.swift`**: `RedEyeEventType` now conforms to `CaseIterable`. (No other direct changes in this phase).
*   **`EventBus.swift`**: (No change).
*   **`MainEventBus.swift`**: (No change).

**IPC Folder:**
*   **`IPCCommand.swift`**: `IPCAction` enum significantly expanded for configuration commands. New `Codable` payload structs for these commands (e.g., `MonitorTypePayload`, `SetMonitorEnabledPayload`). Defines `IPCResponseWrapper` for standardizing response structure.
*   **`IPCCommandHandler.swift`**:
    *   Modified `init` to accept `ConfigurationManager`.
    *   `handleRawCommand` now returns `String?` (JSON response).
    *   Implements handlers for new configuration `IPCAction`s, interacting with `ConfigurationManager`.
    *   Uses helper methods to decode payloads and create structured JSON responses (ACK/NACK/data).

**Managers Folder:**
*   **`MonitorProtocols.swift` (New File):** Defines `MonitorLifecycleManaging` and `MonitorConfigurable` protocols.
*   **`BaseMonitorManager.swift` (New File):** Abstract base class implementing `MonitorLifecycleManaging` and `MonitorConfigurable`. Provides common configuration handling and lifecycle orchestration for monitor managers.
*   **Event Monitor Managers (`AppActivationMonitor`, `FSEventMonitorManager`, `HotkeyManager`, `InputMonitorManager`, `KeyboardMonitorManager`):**
    *   All now inherit from `BaseMonitorManager`.
    *   Removed internal `isEnabled` properties; behavior now driven by configuration fetched via `BaseMonitorManager`.
    *   `init` methods updated to accept `ConfigurationManager` (and other dependencies) and call `super.init()`.
    *   Implement `override func startMonitoring() -> Bool` and `override func stopMonitoring()`.
*   **`PluginManager.swift`**: (No architectural changes in this phase).
*   **`UIManager.swift`**: (No architectural changes in this phase, but `HotkeyManager` which uses it is refactored).
*   **`WebSocketServerManager.swift`**:
    *   Its `onText` handler for incoming client messages now awaits a response string from `IPCCommandHandler.handleRawCommand()` and sends this response back to the client using `try await ws.send()`.

**(UI Folder, Utilities Folder sections remain largely the same as v0.3 unless indirectly affected.)**

### 3. Key Workflows (Updated for v0.4.0)

1.  **Application Startup:**
    *   `AppDelegate.applicationDidFinishLaunching`:
        1.  Initializes `ConfigurationManager`. This involves loading `~/.redeye/config.json` or creating it with defaults. `currentConfig` is now populated.
        2.  Initializes `EventBus`.
        3.  Initializes `IPCCommandHandler` with `ConfigurationManager`.
        4.  Initializes all other managers, including event monitor managers. Monitor managers (now `BaseMonitorManager` subclasses) are provided with `ConfigurationManager` (and `EventBus` if needed).
        5.  `AppDelegate` calls `start()` on each monitor manager.
        6.  Inside each monitor's `start()` (from `BaseMonitorManager`):
            *   The monitor's specific configuration (`MonitorSpecificConfig`) is fetched from `ConfigurationManager`.
            *   If `MonitorSpecificConfig.isEnabled` is true, the base manager calls the subclass's overridden `startMonitoring() -> Bool` method.
            *   The subclass attempts its specific setup (e.g., creating event taps, registering observers). If successful, it returns `true`; `BaseMonitorManager` then sets `isCurrentlyActive = true`. If it fails, it returns `false`; `BaseMonitorManager` sets `isCurrentlyActive = false` and ensures `stopMonitoring()` is called for cleanup.
    *   `WebSocketServerManager` starts its server and subscribes to `EventBus`.

2.  **Event Capturing & Broadcasting:**
    *   This flow is fundamentally the same as v0.3, but a monitor will only capture and publish events if it was successfully started based on its configuration (i.e., `isCurrentlyActive` is true).
    *   Example: `KeyboardMonitorManager.handleEventTap` first checks `self.isCurrentlyActive` before processing a keyboard event.

3.  **IPC Command Reception & Response (Configuration Example - `setMonitorEnabled`):**
    1.  An external WebSocket client sends a JSON command:
        `{ "action": "setMonitorEnabled", "commandId": "cmd123", "payload": { "monitorType": "keyboardMonitorManager", "isEnabled": false } }`
    2.  `WebSocketServerManager.onText` receives the raw string.
    3.  It calls `await ipcCommandHandler.handleRawCommand(commandString, clientID)`.
    4.  `IPCCommandHandler`:
        *   Decodes the string to `IPCReceivedCommand`.
        *   Identifies `action` as `.setMonitorEnabled`.
        *   Decodes `payload` into `SetMonitorEnabledPayload`.
        *   Calls `try configManager.setMonitorEnabled(type: .keyboardMonitorManager, isEnabled: false)`.
    5.  `ConfigurationManager`:
        *   Updates `currentConfig.monitorSettings["keyboardMonitorManager"]?.isEnabled = false`.
        *   Calls `performSaveConfiguration` to persist the updated `RedEyeConfig` to `~/.redeye/config.json`.
    6.  `IPCCommandHandler` (if `configManager` call succeeds):
        *   Creates a success JSON response string, e.g.,
          `{ "commandId": "cmd123", "status": "success", "message": "Monitor 'keyboardMonitorManager' enabled state set to false." }`
    7.  `WebSocketServerManager`:
        *   Receives the response string from `handleRawCommand`.
        *   Calls `try await ws.send(responseString)` to send the JSON response back to the specific client.

### 4. Configuration System (`config.json`)

*   **Location:** `~/Library/Application Support/RedEye/config.json`
    *   The `RedEye` subdirectory and `config.json` file are created automatically by `ConfigurationManager` with default settings if they do not exist.
*   **Format:** JSON.
*   **Structure:** Defined by the `RedEyeConfig`, `MonitorSpecificConfig`, and `GeneralAppSettings` Swift structs.
    *   `schemaVersion` (String): Version of the configuration schema.
    *   `monitorSettings` (Dictionary): Keys are `MonitorType.rawValue` strings (e.g., "keyboardMonitorManager"). Values are `MonitorSpecificConfig` objects.
        *   `MonitorSpecificConfig`: Contains `type` (String, redundant but for clarity in JSON), `isEnabled` (Bool), and `parameters` (Dictionary `[String: JSONValue]`, e.g., `{"paths": ["~/Documents"]}`).
    *   `generalSettings` (Object): Contains global settings like `showPluginPanelOnHotkeyCapture` (Bool).
*   **Management:**
    *   Loaded at startup by `ConfigurationManager`.
    *   Can be modified at runtime via IPC commands. Changes are persisted to the file.
    *   Provides the single source of truth for configurable application behavior.

### 5. External Dependencies
    * (No change from v0.3 for this feature - WebSocketKit, KeyboardShortcuts, CoreServices, ApplicationServices, etc.)

### 6. Permissions Required
    * (No new permissions directly required by the configuration system itself. Existing permissions for monitors still apply.)

### 7. Build & Development
*   Unit tests for `ConfigurationManager` have been implemented to verify file operations, default generation, and get/set logic.
*   Monitor managers now inherit from `BaseMonitorManager`, simplifying their structure and standardizing config access.

### 8. Future Considerations & Potential Refinements (Post v0.4 Phase 1.A)
*   **Live Configuration Reloading:** Notify managers if the config file is changed externally or if an IPC command modifies a part of the config they depend on, so they can re-read and apply changes without an app restart.
*   **Configuration UI:** Develop a user interface for modifying settings (potentially using `sindresorhus/Settings`).
*   **Hierarchical Configuration:** Expand `ConfigurationManager` to merge settings from multiple sources (e.g., global defaults, user file, agent-provided overrides).
*   **Schema Migration:** Implement logic in `ConfigurationManager` to handle migration of `config.json` if `schemaVersion` changes.
*   **Refined IPC Error Codes:** Standardize error codes within IPC responses for better client-side error handling.
