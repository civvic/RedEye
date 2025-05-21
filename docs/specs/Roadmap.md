**Version:** 0.4 (Draft)
**Last Updated:** May 20, 2025

### 🧭 Purpose

RedEye is a lightweight macOS menu bar "sensorium" application designed to capture a wide array of user gestures and system events, communicating them via IPC (WebSockets) to external 'Agent' applications.

Following v0.3, which significantly expanded foundational System Event capture and refactored internal event/IPC handling, **v0.4 focuses on maturing RedEye into a highly configurable and robust sensorium.** Key goals include implementing a comprehensive configuration system (file and IPC-based), refining the IPC protocol to be configuration-centric, enabling server-side event filtering for agents, and further improving developer experience through code refactoring, enhanced logging, expanded testing, and dedicated documentation efforts.

### 🎯 Target User

*   Developers and systems requiring a **highly configurable and efficient component** to capture macOS contextual events and feed them to other applications or complex workflows.
*   Applications needing a macOS-native agent that can be **dynamically configured at runtime** and provide **introspectable capabilities**.

### ✅ v0.3 Recap (Completed)

Version 0.3 successfully delivered:
*   New System Event Monitors: File System (`FSEvents`) and Global Keyboard (`CGEventTap`), including permission handling.
*   Infrastructure Refactoring: Implemented `MainEventBus` (replacing `EventManager`) and `IPCCommandHandler` (decoupling from `WebSocketServerManager`).
*   Developer Experience: Added `isEnabled` toggles for all event monitors and hotkey UI.
*   Research: Analysis of Hazel and Hammerspoon documented in `TechScape.md`.
*   Synthetic Event PoC: Attempted Safari URL capture (experimental, blocked by OS permissions).
*   Unit Tests: Initial tests for `MainEventBus`.
*   Updated project documentation (PRD, Roadmap, Architecture, Release Notes).

### ራ v0.4 Vision & Scope

**Primary Goal for v0.4:** Transform RedEye into a more mature, configurable, and well-documented sensorium by implementing a robust configuration system, refining IPC for configuration, enabling server-side event filtering, and enhancing developer quality-of-life through refactoring, logging, testing, and documentation.

**Key Objectives for v0.4:**
1.  **Implement Configuration System (Phase 1):** Allow RedEye's behavior (active monitors, monitor parameters) to be configured via static files (e.g., JSON/YAML) and basic runtime IPC commands. **(COMPLETED - Phase 1.A: JSON file ~/.redeye/config.json loading/saving, default generation, ConfigurationManager, IPC for get/set monitor state/params, get general settings, get capabilities, reset config. IPC changes are persisted.)**
2.  **Refactor IPC for Configuration:** Shift the primary role of IPC commands from general actions to configuration management, introspection, and filtered event subscription requests. Implement basic ACK/NACK for config commands.
3.  **Enable Server-Side Event Filtering (Phase 1):** Allow IPC clients (Agents) to request filtered streams of events from RedEye, reducing data transfer.
4.  **Improve Developer Experience & Code Quality:**
    *   Refactor `AppDelegate` initialization into an `AppCoordinator`.
    *   Decouple text-fetching logic from `HotkeyManager` into a `TextCaptureService`.
    *   Enhance logging capabilities (organization, potential for runtime adjustments).
    *   Expand unit and integration test coverage.
5.  **Establish Comprehensive Documentation:** Create and maintain documentation for Users (README), Developers (Developer Guide), and Agent/System Integrators (IPC Reference).

### 🔧 Core Features (Focus for v0.4)

1.  **Configuration System (Phase 1):**
    *   **Static File Configuration:** **[COMPLETED]** Loads from ~/.redeye/config.json, creates with defaults if missing. Supports enabling monitors, FSEvent paths, general app toggles.
    *   **IPC for Runtime Configuration & Introspection:** **[COMPLETED]** Commands for `getConfig`, getMonitorSetting(s), `setMonitorEnabled`, setMonitorParameters, getGeneralSettings, `setGeneralSettings`, `getCapabilities`, `resetConfigToDefaults` implemented. Changes are persisted.
    *   **`ConfigurationManager`:** **[COMPLETED]** Manages loading, defaults, access, IPC-driven changes, and persistence to config.json.

2.  **Refined IPC Protocol (Configuration-Centric):**
    *   Redefine `IPCAction` enum and associated `IPCCommandHandler` logic to focus on commands like:
        *   `setConfigValue`, `getConfigValue`
        *   `setMonitorEnabled`, `getMonitorStatus`
        *   `setMonitorParameters` (e.g., FSEvent paths)
        *   `getCapabilities`
        *   `subscribeWithFilter` (see below)
    *   Implement basic ACK/NACK responses for critical configuration commands.
    *   Provide more detailed error reporting for IPC command failures.

3.  **Server-Side Event Filtering for IPC (Phase 1):**
    *   Allow IPC clients (Agents) to specify filters when subscribing to events (e.g., by `RedEyeEventType`, source application for app events, path prefix for FS events).
    *   `WebSocketServerManager` (or a new `IPCSubscriptionManager`) will apply these filters before sending events to specific clients.
    *   Requires a new IPC command like `subscribeToEvents(filters: [FilterDescription])`.

4.  **Core Component Refactoring:**
    *   **`AppCoordinator`:** New class to handle manager initialization and application lifecycle logic, reducing `AppDelegate`'s responsibilities.
    *   **`TextCaptureService`:** New service to encapsulate Accessibility-based text-fetching logic, used by `HotkeyManager`.
    *    Define `MonitorLifecycleManaging` and `MonitorConfigurable` protocols: Implemented by **BaseMonitorManager** to provide clear contracts. **[COMPLETED]**

5.  **Logging Enhancements (Phase 1):**
    *   Standardize logger instantiation (e.g., via a `Loggable` protocol or helper).
    *   Improve organization of logging categories and levels.
    *   (Investigate: Runtime log level adjustment capabilities).

6.  **Expanded Testing:**
    *   Increase unit test coverage for new components (`ConfigurationManager`, `AppCoordinator`, `TextCaptureService`, `IPCCommandHandler` updates, filtering logic).
    *   Introduce basic integration tests for key workflows (e.g., IPC config change affecting behavior).

7.  **Comprehensive Documentation:**
    *   **User Documentation (`README.md`):** Installation, basic configuration via file, troubleshooting.
    *   **Developer Documentation (`DEVELOPER_GUIDE.md`):** Project architecture, how to add new event monitors/features, testing guidelines, contribution process.
    *   **Agent/System Integration Documentation (`IPC_REFERENCE.md`):** Detailed specification of all IPC commands (requests, responses, payloads, ACKs/NACKs), event object schemas, available event types, filter syntax, and capability discovery.

### ❌ Not in Scope for v0.4 (Examples)

*   Advanced Synthetic Event generation (beyond foundational capabilities).
*   Complex rule engine for Compound Events within RedEye itself.
*   UI for configuration (configuration is via files and IPC).
*   Support for IPC transports other than WebSockets.
*   Full hierarchical/layered configuration merging (Phase 1 focuses on static file + IPC overrides).
*   Advanced EventBus features like subscriber-specified delivery queues (beyond main-thread delivery).

### 💡 Future Considerations (Beyond v0.4)
*   Phase 2 of Configuration System (hierarchical merging, more dynamic sources).
*   Advanced Synthetic Event generation.
*   Rule engine for Compound Events.
*   UI for configuration and status monitoring.
*   Support for additional IPC transports.
