# RedEye Project Roadmap

**Version:** 0.4 (Completed Features Review)
**Last Updated:** May 21, 2025

### 🧭 Purpose
RedEye is a lightweight macOS menu bar "sensorium" application designed to capture a wide array of user gestures and system events, communicating them via IPC (WebSockets) to external 'Agent' applications.

Following v0.3, which significantly expanded foundational System Event capture and refactored internal event/IPC handling, **v0.4 focused on maturing RedEye into a highly configurable and robust sensorium, alongside significant code quality and developer experience improvements.**

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

### ራ v0.4 Vision & Scope (End of Version Status)

**Primary Goal for v0.4 (Achieved in Part):** Transform RedEye into a more mature, configurable, and well-documented sensorium by implementing a robust configuration system, refining IPC for configuration, enhancing developer quality-of-life through refactoring, logging, testing, and documentation. Server-side event filtering was deferred.

**Key Objectives for v0.4 & Final Status:**
1.  **Implement Configuration System (Phase 1):** Allow RedEye's behavior (active monitors, monitor parameters, logging level) to be configured via static files (`~/.redeye/config.json`) and basic runtime IPC commands.
    *   **Status: [COMPLETED]**
    *   Details: `ConfigurationManager` implemented for JSON file (`~/.redeye/config.json`) loading/saving, default generation. IPC commands for getting/setting monitor enabled states, parameters, general settings (including log level), and retrieving capabilities are functional. Changes made via IPC are persisted.
2.  **Refactor IPC for Configuration:** Shift the primary role of IPC commands from general actions to configuration management, introspection, and filtered event subscription requests. Implement basic ACK/NACK/Data responses for config commands.
    *   **Status: [COMPLETED]**
    *   Details: IPC actions now heavily feature configuration. Structured JSON responses (status, message, data, commandId) are implemented for these commands.
3.  **Enable Server-Side Event Filtering (Phase 1):** Allow IPC clients (Agents) to request filtered streams of events from RedEye, reducing data transfer.
    *   **Status: [DEFERRED to v0.5+]**
4.  **Improve Developer Experience & Code Quality:**
    *   Refactor `AppDelegate` initialization into an `AppCoordinator`.
        *   **Status: [COMPLETED]**
    *   Decouple text-fetching logic from `HotkeyManager` into a `TextCaptureService`.
        *   **Status: [COMPLETED]**
    *   Enhance logging capabilities (organization, runtime adjustments via config, improved context).
        *   **Status: [COMPLETED]** (New `Loggable` protocol, instance loggers, `LogLevel` enum, config-driven global level).
    *   Expand unit and integration test coverage.
        *   **Status: [PARTIALLY COMPLETED]** (Unit tests for `ConfigurationManager` and `MainEventBus` added. Manual integration tests for config system performed. Further expansion deferred).
5.  **Establish Comprehensive Documentation:** Create and maintain documentation for Users (README), Developers (Developer Guide), and Agent/System Integrators (IPC Reference).
    *   **Status: [IN PROGRESS]**
    *   Details: `IPC_REFERENCE.md` drafted. `Architecture.md` (v0.4) created. `README.md` updated. `DEVELOPER_GUIDE.md` requires focus. Project documentation now managed in `/docs` under Git.

### 🔧 Core Features Delivered in v0.4

1.  **Configuration System:**
    *   **Static File Configuration (`~/.redeye/config.json`):** For default monitor states, parameters (e.g., FSEvent paths), general settings (e.g., hotkey UI panel, log level). Auto-creation with defaults.
    *   **IPC for Runtime Configuration:** Commands for get/set monitor enabled state, parameters; get/set general settings; get capabilities; get full config; reset to defaults. Changes persist to file.
    *   **`ConfigurationManager`:** Central component for all configuration logic.
2.  **Refined IPC Protocol:**
    *   New IPC actions focused on configuration.
    *   Standardized JSON response format for commands.
3.  **Core Component Refactoring:**
    *   **`AppCoordinator`:** Manages application component initialization and lifecycle.
    *   **`TextCaptureService`:** Decouples text-capture logic.
    *   **`BaseMonitorManager` & Protocols (`MonitorLifecycleManaging`, `MonitorConfigurable`):** Standardizes event monitor structure, configuration consumption, and lifecycle.
4.  **Logging Enhancements:**
    *   **`Loggable` protocol** and instance-based logging for cleaner, context-rich logs.
    *   **`RedEyeLogger.LogLevel`** and config-driven global log level.
5.  **Documentation Structure:**
    *   All project documentation moved into `/docs` directory under Git version control.
    *   Initial draft of `IPC_REFERENCE.md`.
    *   Updated `README.md` and `Architecture.md`.

### ❌ Not Delivered in v0.4 (Moved from Scope)

*   **Server-Side Event Filtering (Phase 1):** Deferred to a future version (e.g., v0.5).
*   **Comprehensive Automated Testing:** While some unit tests were added, broad automated testing (especially integration/UI) remains a future goal.

### 💡 Future Considerations (Lead-in to v0.5+ Planning)
*   **Server-Side Event Filtering.**
*   **Live Configuration Reloading** (for non-restart updates).
*   **UI for Configuration.**
*   **Advanced Synthetic Events.**
*   **Rule Engine for Compound Events.**
*   **Expanded Test Automation.**
*   **Completion of `DEVELOPER_GUIDE.md` and other documentation.**
*   *(Other items from previous roadmaps/PRDs remain relevant for longer-term vision).*
