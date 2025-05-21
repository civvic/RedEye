## v0.3
**Release Date:** May 14, 2025

### Overview

Version 0.3.0 of RedEye significantly expands its event "sensing" capabilities and undertakes crucial internal refactoring to prepare for future growth. This release introduces monitoring for File System events and global Keyboard events, alongside a comprehensive research initiative into related macOS automation tools. A major infrastructure overall establishes a new EventBus system and decouples IPC command handling.

### ✨ New Features & Enhancements

1.  **File System Event Monitoring (`FSEventMonitorManager`):**
    *   RedEye can now monitor specified directories (defaulting to user's Documents and Downloads) for file system changes.
    *   Captures events for item creation, deletion, modification, and renaming.
    *   Emits a new `.fileSystemEvent` (`RedEyeEvent`) containing the affected path and detailed event flags.
    *   Includes awareness for potential Full Disk Access permission requirements if configured to monitor broader locations.

2.  **Global Keyboard Event Monitoring (`KeyboardMonitorManager`):**
    *   Monitors global keyboard activity, including key down, key up, and modifier flag changes using `CGEventTap`.
    *   Emits a new `.keyboardEvent` (`RedEyeEvent`) with details such as key code, character representation (if available), and modifier states.
    *   Implements the necessary "Input Monitoring" permission request and handling flow, guiding the user if permission is needed.

3.  **Infrastructure Refactoring Phase 1:**
    *   **EventBus System:** Introduced `MainEventBus`, a central, decoupled event bus.
        *   `EventManager` has been removed. All event source managers now publish events directly to the `MainEventBus`.
        *   `WebSocketServerManager` now subscribes to the `MainEventBus` to receive all events for broadcasting.
        *   This provides a more scalable and maintainable internal event propagation architecture.
    *   **IPC Command Handler (`IPCCommandHandler`):**
        *   Created a dedicated `IPCCommandHandler` class.
        *   All logic for parsing, routing, and handling incoming IPC commands (e.g., `logMessageFromServer`) has been moved from `WebSocketServerManager` to this new handler.
        *   `WebSocketServerManager`'s role in handling incoming messages is now simplified to passing raw command strings to `IPCCommandHandler`.

4.  **Developer Experience Improvements:**
    *   **Event Monitor Toggles:** All core event monitors (`FSEventMonitorManager`, `KeyboardMonitorManager`, `AppActivationMonitor`, `InputMonitorManager`) now have an internal `isEnabled` flag. These are set to `false` by default in `AppDelegate`, allowing developers to selectively enable monitors during development and testing to reduce log noise.
    *   **Hotkey UI Toggle:** `HotkeyManager` now has an `isHotkeyUiEnabled` flag to control the visibility of the UI panel for hotkey-triggered text captures, separate from event emission.

5.  **Tech Landscape Research (`TechScape.md`):**
    *   Conducted and documented research into macOS automation tools Hazel (for FSEvents and rule-based automation) and Hammerspoon (for broad event handling, Lua scripting, and system interaction APIs).
    *   Findings have been used to inform RedEye's design choices and future roadmap.

6.  **Unit Tests (Initial Set):**
    *   Introduced XCTest unit tests for the new `MainEventBus` component, covering core functionalities like subscription, publication, and asynchronous delivery.

### 🚧 Experimental Features & Known Issues

*   **Browser URL Capture PoC (Safari via AppleScript):**
    *   Logic to capture the current URL and title from Safari upon its activation (emitting a `.browserNavigation` event) was implemented as a Proof-of-Concept for synthetic event generation.
    *   **Status:** This feature is **disabled by default** and considered **experimental/blocked**.
    *   **Issue:** During development, persistent and inconsistent OS-level TCC/Automation permission issues on the macOS (Sequoia Beta) test environment prevented RedEye from reliably obtaining the necessary permissions to control Safari via AppleScript. The system often failed to prompt for or allow manual granting of these permissions for the RedEye application.
    *   The code for this PoC remains for learning purposes and potential future revisiting if the OS permission behavior stabilizes.

### 🔒 Required Permissions (Summary for v0.3)

*   **Accessibility:** For text selection and frontmost application details.
*   **Input Monitoring:** For global keyboard event capture (`KeyboardMonitorManager`).
*   **Automation (Safari - for PoC):** Attempted; OS issues prevented reliable granting for RedEye in v0.3.
*   **Full Disk Access (Potential):** If `FSEventMonitorManager` is configured for paths outside user's standard folders.

### 🚀 Future Considerations

*   Revisit and resolve TCC/Automation permission issues for browser/application interaction.
*   Expand the range of System and Synthetic events.
*   Further develop the IPC command system.
*   Implement a comprehensive user/agent configuration system.
*   Continue expanding test coverage.

----

## v0.2
**Release Date:** May 11, 2025

### Summary

RedEye v0.2.0 significantly expands upon the v0.1 MVP, transforming the application into a more versatile macOS "sensorium" and an Inter-Process Communication (IPC) hub. This version introduces a WebSocket server for bidirectional communication with an external main application, new event capture mechanisms including shortcut-less text selection (mouse-based) and application activation monitoring, and an evolved event structure to support these new capabilities.

The core objective of v0.2 was to lay the groundwork for RedEye to act as a rich contextual event feeder and action executor for more complex, potentially cross-platform systems.

### Key Milestones Achieved in v0.2

1.  **Robust Inter-Process Communication (IPC) Hub via WebSockets:**
    *   Successfully implemented a WebSocket server (`WebSocketServerManager` using `WebSocketKit`/SwiftNIO) hosted by RedEye on `localhost:8765`.
    *   The server manages multiple client connections, disconnections, and basic error scenarios.
    *   **Event Streaming:** All captured `RedEyeEvent` objects are serialized to JSON and broadcast to all connected WebSocket clients.
    *   **Command Reception (Stub):** RedEye can now receive JSON-formatted commands from WebSocket clients. A basic command structure (`IPCReceivedCommand`) and a stub handler for a `logMessageFromServer` action have been implemented, demonstrating the ability to parse and route incoming commands. Command processing is offloaded to Swift Concurrency `Task`s.

2.  **Expanded Event Capture Mechanisms:**
    *   **Shortcut-less Text Selection Trigger:**
        *   Implemented global mouse event monitoring (`leftMouseDown`, `leftMouseUp`) using `NSEvent.addGlobalMonitorForEvents` via a new `InputMonitorManager`.
        *   Developed heuristics to distinguish between simple clicks and potential text selection drags.
        *   Upon a qualifying mouse-up event, RedEye now attempts to capture selected text using the Accessibility API (handled by `HotkeyManager` as a delegate).
        *   Basic debouncing logic was added to avoid event emission for empty selections or selections identical to the previous mouse-based selection.
    *   **Application Activation Trigger:**
        *   Implemented an `AppActivationMonitor` that uses `NSWorkspace.shared.notificationCenter` to observe `didActivateApplicationNotification`.
        *   When the frontmost application changes, an `.applicationActivated` `RedEyeEvent` is generated and emitted, including the name, bundle ID, and PID of the newly active application.
        *   Basic de-duplication for activation events is in place.

3.  **Refined Event Structure (`RedEyeEvent`):**
    *   Introduced a new `RedEyeEventType`: `.applicationActivated`.
    *   The `metadata` field in `RedEyeEvent` is now utilized to store additional context, such as the `trigger` type for text selections ("hotkey" or "mouse\_selection") and `pid` for application activations.

4.  **Maintained & Enhanced Core v0.1 Features:**
    *   **Core Application & Hotkey Trigger:** The Swift macOS menu bar app structure and the ⌘⇧C hotkey for text selection remain fully functional.
    *   **Floating UI Placeholder:** The UI panel continues to appear for text selection events (both hotkey and mouse-triggered) and can invoke the stub `echo_plugin.sh`.
    *   **Structured Logging:** `RedEyeLogger` has been used extensively for diagnostics throughout v0.2 development.
    *   **PluginManager:** Local plugin execution via `PluginManager` is still present, though the focus for v0.2 was on IPC.

### Permissions Status for v0.2

*   **Accessibility Access:** Remains essential for text selection and frontmost application details.
*   **Input Monitoring:** **Not required** for the current v0.2 implementation. Shortcut-less text selection was achieved using `NSEvent.addGlobalMonitorForEvents` in conjunction with Accessibility, without needing to enable explicit Input Monitoring permissions. This may change if future features require `CGEventTap`.

### Known Issues & Limitations in v0.2

*   **IPC Command Acknowledgement:** The optional phase of sending ack/nack responses for received IPC commands was deferred and is not implemented in v0.2. Clients will not receive explicit confirmation of command success/failure.
*   **IPC Command Set:** Only a single stub command (`logMessageFromServer`) is implemented for IPC reception. The framework is in place, but no complex actions are yet executable via IPC.
*   **WebSocket Server Error Handling:** While basic connection/disconnection and decoding errors are logged, comprehensive error handling and recovery mechanisms for the WebSocket server and IPC layer are minimal.
*   **`WebSocketServerManager` Complexity:** This manager has accumulated multiple responsibilities (server lifecycle, connection management, event broadcasting, command parsing/routing) and is a candidate for refactoring to improve separation of concerns.
*   **Payload Decoding for IPC Commands:** The current method for decoding specific command payloads (e.g., `LogMessagePayload`) from the generic `[String: JSONValue]` is functional but involves a somewhat inefficient two-step process (to `Data` then to struct) that could be optimized.
*   **UI Polish:** The floating UI remains a basic placeholder as in v0.1. Advanced PopClip-like behaviors are not yet implemented.
*   **Configuration:** No new user-configurable preferences were added in v0.2.
*   **Local Plugin System:** No significant enhancements were made to the local plugin system; its future role is under consideration.

### Future Outlook (Post v0.2)

RedEye v0.2 has successfully established the foundational IPC and expanded event capture capabilities. Future versions (v0.3 and beyond) will likely focus on:
*   Expanding the set of IPC commands RedEye can execute on behalf of a main application (e.g., text manipulation, requesting system information).
*   Implementing robust ack/nack for IPC commands.
*   Further expanding the range of captured system/user events (e.g., file events, detailed browser events, keyboard events if `CGEventTap` is adopted).
*   Refactoring core managers for better separation of concerns and maintainability.
*   Beginning work on the polished Floating UI.
*   Introducing user configuration options.

----

## v0.1
**Release Date:** May 10, 2025
**Project:** RedEye

### Summary

This initial MVP (v0.1.0) of RedEye establishes the foundational capabilities of a macOS menu bar application. It is designed for capturing contextual system events (starting with hotkey-triggered text selection) and enabling interaction with external script-based plugins. This version serves as a proof of concept for core functionalities and provides a base for future expansion into a more comprehensive "sensorium" application.

### Key Milestones Achieved in v0.1

1.  **Core Application Setup & Menu Bar Presence:**
    *   Successfully created a Swift-based macOS menu bar application using AppKit.
    *   Implemented an `NSStatusItem` providing a persistent presence in the system menu bar with a "Quit RedEye" option.
    *   Established an explicit application entry point (`main.swift`) and application delegate (`AppDelegate.swift`) for reliable initialization as an agent app (`LSUIElement`).

2.  **Text Selection Trigger via Hotkey:**
    *   Integrated the `KeyboardShortcuts` third-party library for robust global hotkey registration (⌘⇧C).
    *   Utilized the macOS Accessibility API (`AXUIElement`) to accurately capture selected text and obtain details (name, bundle ID) of the frontmost application.

3.  **Event System Foundation:**
    *   Defined a standardized `RedEyeEvent` struct (`RedEyeEvent.swift`), which is `Codable` for easy serialization. It includes fields for a unique ID, timestamp, event type, source application details, context text, and optional metadata.
    *   Implemented an `EventManager` (`EventManager.swift`) to centrally process these events. In v0.1, it serializes `RedEyeEvent` instances to pretty-printed JSON and logs them to the console.

4.  **Plugin Manager & Stub Execution:**
    *   Created a `PluginManager` (`PluginManager.swift`) that discovers executable shell scripts from a predefined directory (`~/Library/Application Support/RedEye/Plugins/`).
    *   Successfully executed a sample `echo_plugin.sh` by launching it as an external `Process`.
    *   Demonstrated passing the captured selected text to the plugin's standard input (stdin) and capturing the plugin's output from standard output (stdout) and standard error (stderr).

5.  **Floating UI Placeholder:**
    *   Developed a custom, borderless, non-activating `NSPanel` (`PluginActionsPanel.swift`) to serve as a placeholder for a PopClip-style UI.
    *   Managed the panel's content and lifecycle using `PluginActionsViewController.swift` and a `UIManager.swift`.
    *   The panel appears near the mouse cursor when the text selection hotkey is triggered.
    *   A button within the panel successfully triggers the execution of the `echo_plugin.sh` (via `UIManager` -> `PluginManager`).
    *   The panel dismisses after a plugin action is performed.

6.  **Structured Logging & Development Mode:**
    *   Implemented `RedEyeLogger.swift`, a utility wrapper around Apple's `os.Logger` framework.
    *   Provides structured, categorized, and level-based logging (`info`, `debug`, `error`, `fault`).
    *   Verbose debug logging (`RedEyeLogger.debug`) is automatically enabled for `DEBUG` builds via a programmatic switch in `AppDelegate`, facilitating easier development and troubleshooting.

7.  **Project Organization:**
    *   Source code files were organized into logical groups/folders (`App`, `Events`, `Managers`, `UI`, `Utilities`) within the Xcode project to enhance maintainability and readability.

### Known Issues & Limitations in v0.1

*   **UI Polish:** The floating UI is a basic placeholder. Advanced PopClip-like behaviors (e.g., appearance timing based on mouse stop, sophisticated dismissal on mouse-out or Escape key, hover effects) are not implemented. Escape key dismissal for the panel is not reliably functional.
*   **Plugin System:** The current plugin system is a minimal stub. It only supports a single, predefined `echo` shell script and relies on a very simple filename-based discovery and stdin/stdout contract. There are no manifest files, no support for other plugin types (e.g., JavaScript, Python directly), and no UI for managing plugins.
*   **Configuration:** No user-configurable preferences exist (e.g., for plugin directory, hotkey customization, enabling/disabling features).
*   **Event Triggers:** Event capture is limited to hotkey-based text selection. No other system or user events are monitored.
*   **Inter-Process Communication (IPC):** IPC with other applications is not implemented in v0.1.
*   **Error Handling:** While basic error logging is in place, comprehensive error handling and recovery mechanisms are minimal.

### Future Outlook

RedEye v0.1 provides a solid foundation. Future versions will focus on expanding event capture capabilities, implementing robust IPC (Inter-Process Communication) via WebSockets, evolving the plugin system, and refining the user interface and experience.