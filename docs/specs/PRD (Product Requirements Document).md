**Product Requirements Document - RedEye**

**Version:** 0.4 (Partial Completion) 
**Last Updated:** May 21, 2025

### 🧭 Purpose 
RedEye is a lightweight macOS menu bar "sensorium" application designed to capture a wide array of user gestures and system events, communicating them via IPC (WebSockets) to external 'Agent' applications.

### 🎯 Target User
*   Developers and systems requiring a **highly configurable and efficient component** to capture macOS contextual events and feed them to other applications or complex workflows.
*   Applications needing a macOS-native agent that can be **dynamically configured at runtime** and provide **introspectable capabilities**.

### ✅ v0.3 Recap (Completed)
*   New System Event Monitors: File System (`FSEvents`) and Global Keyboard (`CGEventTap`), including permission handling.
*   Infrastructure Refactoring: Implemented `MainEventBus` (replacing `EventManager`) and `IPCCommandHandler` (decoupling from `WebSocketServerManager`).
*   Developer Experience: Added `isEnabled` toggles for all event monitors and hotkey UI.
*   Research: Analysis of Hazel and Hammerspoon documented in `TechScape.md`.
*   Synthetic Event PoC: Attempted Safari URL capture (experimental, blocked by OS permissions).
*   Unit Tests: Initial tests for `MainEventBus`.
*   Updated project documentation (PRD, Roadmap, Architecture, Release Notes for v0.3).

### ራ v0.4 Vision & Scope (Updated Status)

**Primary Goal for v0.4 (Original):** Transform RedEye into a more mature, configurable, and well-documented sensorium by implementing a robust configuration system, refining IPC for configuration, enabling server-side event filtering, and enhancing developer quality-of-life through refactoring, logging, testing, and documentation.

**Current Status of v0.4 Goals:**
*   **Configuration System & IPC Refinements:** Largely **COMPLETED**. RedEye is now highly configurable via file and IPC.
*   **Server-Side Event Filtering:** **DEFERRED** to a future version.
*   **Developer Experience & Code Quality (Refactoring, Logging, Testing):** **SIGNIFICANT PROGRESS**. Major refactors (AppCoordinator, TextCaptureService) and logging system overhaul completed. Comprehensive testing expanded for core config, some areas deferred.
*   **Comprehensive Documentation:** **IN PROGRESS**. IPC Reference drafted, core dev docs updated. User-facing docs (README) improved.

**Key Objectives for v0.4 (Updated Status):**
1.  **Implement Configuration System (Phase 1):** Allow RedEye's behavior (active monitors, monitor parameters, logging level) to be configured via static files (`~/.redeye/config.json`) and basic runtime IPC commands. **[COMPLETED]**
2.  **Refactor IPC for Configuration:** Shift the primary role of IPC commands from general actions to configuration management, introspection, and filtered event subscription requests. Implement basic ACK/NACK/Data responses for config commands. **[COMPLETED]**
3.  **Enable Server-Side Event Filtering (Phase 1):** Allow IPC clients (Agents) to request filtered streams of events from RedEye, reducing data transfer. **[DEFERRED to v0.5+]**
4.  **Improve Developer Experience & Code Quality:**
    *   Refactor `AppDelegate` initialization into an `AppCoordinator`. **[COMPLETED]**
    *   Decouple text-fetching logic from `HotkeyManager` into a `TextCaptureService`. **[COMPLETED]**
    *   Enhance logging capabilities (organization, runtime adjustments via config, improved context). **[COMPLETED]**
    *   Expand unit and integration test coverage. **[PARTIALLY COMPLETED - Core config tested. Further expansion deferred.]**
5.  **Establish Comprehensive Documentation:** Create and maintain documentation for Users (README), Developers (Developer Guide), and Agent/System Integrators (IPC Reference). **[IN PROGRESS - IPC Ref created, Arch updated, README updated. Developer Guide needs focus.]**

### 🔧 Core Features (Focus for v0.4 - Current State)

1.  **Configuration System (Phase 1): [COMPLETED]**
    *   **Static File Configuration:** RedEye loads initial settings from `~/.redeye/config.json`. Creates with defaults if missing. Configurable items:
        *   Enabled state of event monitors.
        *   Parameters for monitors (e.g., paths for `FSEventMonitorManager`, `enableBrowserURLCapture` for `appActivationMonitor`).
        *   General app settings (e.g., `showPluginPanelOnHotkeyCapture`, `logLevel`).
    *   **IPC for Runtime Configuration & Introspection:**
        *   Commands implemented: `getConfig`, `getMonitorSetting(s)`, `setMonitorEnabled`, `getMonitorParameters`, `setMonitorParameters`, `getGeneralSettings`, `setGeneralSettings`, `getCapabilities`, `resetConfigToDefaults`.
        *   Changes made via IPC are persisted to `config.json`.
    *   **`ConfigurationManager`:** Central component managing config loading, defaults, access, runtime changes, and persistence.
    *   **Log Level Configuration:** Global application log level (`RedEyeLogger.currentLevel`) is now configurable via `generalSettings.logLevel` in `config.json` and via IPC through `setGeneralSettings`.

2.  **Refined IPC Protocol (Configuration-Centric): [COMPLETED]**
    *   `IPCAction` enum and `IPCCommandHandler` logic now primarily focus on configuration and introspection commands.
    *   Implemented structured JSON responses (status, message, data, commandId) for all new configuration commands.

3.  **Server-Side Event Filtering for IPC (Phase 1): [DEFERRED]**
    *   (Original description remains, but marked as deferred)

4.  **Core Component Refactoring: [COMPLETED]**
    *   **`AppCoordinator`:** New class handles manager initialization and application lifecycle logic, reducing `AppDelegate`'s responsibilities.
    *   **`TextCaptureService`:** New service encapsulates Accessibility-based text-fetching logic, used by `HotkeyManager`.
    *   **`BaseMonitorManager` & Protocols:** Introduced `BaseMonitorManager` (inheriting from `MonitorLifecycleManaging`, `MonitorConfigurable`, `Loggable`) to standardize monitor configuration handling and lifecycle. All event monitors refactored.

5.  **Logging Enhancements (Phase 1): [COMPLETED]**
    *   **`Loggable` Protocol:** Implemented for instance-based logging with automatic context (file, line, function) and reduced boilerplate (`self.info(...)`).
    *   **`RedEyeLogger.LogLevel`:** Defined log levels (`fault` to `trace`).
    *   **Configurable Log Level:** `RedEyeLogger.currentLevel` set from `config.json` and updatable via IPC.
    *   Improved organization and consistency of logging calls.

6.  **Expanded Testing: [PARTIALLY COMPLETED]**
    *   Unit tests for `ConfigurationManager` and `MainEventBus` are in place.
    *   Manual integration testing performed for the configuration system.
    *   Further expansion of unit/integration tests for other new/refactored components (e.g., `AppCoordinator`, `TextCaptureService`, specific monitor logic beyond base) is deferred.

7.  **Comprehensive Documentation: [IN PROGRESS]**
    *   **User Documentation (`README.md`):** Updated with configuration details.
    *   **Developer Documentation (`DEVELOPER_GUIDE.md`):** Needs creation/significant update to reflect v0.4 architecture and development patterns.
    *   **Agent/System Integration Documentation (`IPC_REFERENCE.md`):** Drafted with all current IPC commands and event structures.
    *   **Architecture Documentation (`Architecture.md`):** Updated for v0.4.
    *   Project documentation now managed in `/docs` under Git.

### 🔒 Permissions Required (v0.4)
-   **Accessibility Access:** (Existing) Still required.
*   **Input Monitoring:** (New Requirement) **Required and Implemented** by `KeyboardMonitorManager`.
*   **Automation (Per-Application):** (New Requirement for PoC) Attempted for Safari. `NSAppleEventsUsageDescription` added. **OS-level issues prevented reliable granting for RedEye during v0.3.**
*   **Full Disk Access:** (Potential Requirement) Awareness added for `FSEvents` if monitoring broad locations. No active requirement for default paths.

### ❌ Not in Scope for v0.4 (Final)
*   **Server-Side Event Filtering.** (Deferred)
*   Advanced Synthetic Event generation (beyond foundational capabilities and the experimental Safari URL capture).
*   Complex rule engine for Compound Events within RedEye itself.
*   UI for configuration (configuration remains via files and IPC).
*   Support for IPC transports other than WebSockets.
*   Full hierarchical/layered configuration merging (Phase 1 focused on static file + IPC overrides with persistence).
*   Advanced EventBus features like subscriber-specified delivery queues.
*   Comprehensive automated integration or UI testing.

### 💡 Future Considerations (Beyond v0.4)
*   **Server-Side Event Filtering.**
*   **Live Configuration Reloading** for monitors/services without app restart.
*   **Phase 2 of Configuration System** (hierarchical merging, more dynamic sources).
*   **UI for configuration and status monitoring.**
*   **Expanded Test Automation** (Unit, Integration, UI).
*   **Revisit Browser URL Capture / Synthetic Events:** Investigate TCC/Automation permission issues further. Explore alternative methods for application-specific event capture if AppleScript remains problematic or too limited.
