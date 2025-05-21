RedEye is a lightweight macOS menu bar application designed to act as a "sensorium." It captures a wide array of user gestures and system events, making them available via WebSockets to external 'Agent' applications for automation, context awareness, or advanced workflows.

## Core Features (v0.4)

*   **Extensive Event Monitoring:** Captures events such as:
    *   Application activations.
    *   Text selections (via hotkey ⌘⇧C or mouse-based selection).
    *   Global keyboard activity (key down, key up, modifier changes).
    *   File system changes in specified directories.
    *   (Experimental) Browser navigation details for Safari (URL/title on activation, subject to OS permissions).
*   **IPC via WebSockets:** Broadcasts captured events in JSON format to connected clients (Agents) running on `ws://localhost:8765`.
*   **Configurable Behavior:** RedEye's active monitors and their parameters can be configured via a JSON file, allowing users to tailor its operation to their needs.
*   **IPC Command Interface:** Allows connected Agents to:
    *   Query RedEye's capabilities.
    *   Read and modify RedEye's configuration at runtime (changes are persisted).
    *   Request RedEye to log messages.
*   **Menu Bar Interface:** Provides a simple menu bar icon for status and quitting the application.
*   **Plugin System (Basic):** Includes a foundational system for local plugins (further development planned for future versions).

## Installation & Setup (Placeholder)

*(This section will be updated once a build and distribution process is established.)*

1.  Download the latest version of RedEye (link to be provided).
2.  Move `RedEye.app` to your `/Applications` folder.
3.  Launch RedEye.

On first launch, RedEye may request the following permissions:
*   **Accessibility Access:** Required for capturing selected text and context from other applications.
*   **Input Monitoring:** Required by the Global Keyboard Event monitor. RedEye will prompt if this monitor is enabled in the configuration.

Please grant these permissions via **System Settings > Privacy & Security** for RedEye to function fully.

## Configuration

RedEye's behavior can be customized by editing its configuration file:

*   **Location:** `~/Library/Application Support/RedEye/config.json`

If this file or the `RedEye` directory does not exist when RedEye starts, it will be created automatically with default settings.

### Configuration Structure (`config.json`)

The `config.json` file allows you to control which event monitors are active and their specific parameters. Here's an overview of its structure:

```json
{
  "schemaVersion": "1.0",
  "monitorSettings": {
    "appActivationMonitor": {
      "isEnabled": false,
      "parameters": {
        "enableBrowserURLCapture": false
      }
    },
    "fsEventMonitorManager": {
      "isEnabled": false,
      "parameters": {
        "paths": [] // Example: ["~/Documents", "~/Desktop"]
      }
    },
    "hotkeyManager": { // For ⌘⇧C text capture hotkey
      "isEnabled": true, // Whether the hotkey itself is active
      "parameters": null
    },
    "inputMonitorManager": { // For mouse-based text selection
      "isEnabled": false,
      "parameters": null
    },
    "keyboardMonitorManager": {
      "isEnabled": true,
      "parameters": null
    }
  },
  "generalSettings": {
    "showPluginPanelOnHotkeyCapture": false,
    "logLevel": null // "fault", "error", "warning", "info", "debug", "trace" (or null for default)
  }
}
```

**Key Configuration Options:**

*   **`monitorSettings.<monitorName>.isEnabled` (boolean):**
    *   Set to `true` to enable a specific monitor, `false` to disable it.
    *   Available monitors (`<monitorName>`):
        *   `appActivationMonitor`
        *   `fsEventMonitorManager`
        *   `hotkeyManager`
        *   `inputMonitorManager`
        *   `keyboardMonitorManager`
*   **`monitorSettings.appActivationMonitor.parameters.enableBrowserURLCapture` (boolean):**
    *   If `appActivationMonitor` is enabled, set this to `true` to attempt capturing Safari's URL/title on activation (experimental, requires Automation permission for RedEye to control Safari).
*   **`monitorSettings.fsEventMonitorManager.parameters.paths` (array of strings):**
    *   If `fsEventMonitorManager` is enabled, provide an array of directory paths to monitor (e.g., `["~/Desktop", "/Users/Shared/Projects"]`).
    *   An empty array `[]` or a missing `paths` parameter will cause `fsEventMonitorManager` to use its internal default paths (typically Documents and Downloads). Paths starting with `~` are expanded.
*   **`generalSettings.showPluginPanelOnHotkeyCapture` (boolean):**
    *   If `true`, the small plugin action panel will appear near the selected text when text is captured using the ⌘⇧C hotkey.
*   **`generalSettings.logLevel` (string or null):**
    *   Controls the verbosity of RedEye's internal logging.
    *   Accepted values: `"fault"`, `"error"`, `"warning"`, `"info"`, `"debug"`, `"trace"`.
    *   If `null` or not present, RedEye uses a default level (typically `debug` for development builds, `info` for release builds).
    *   Changes to this setting in the file require an application restart to take full effect for initial logging, though IPC commands might change it live.

**Applying Configuration Changes:**
*   Changes made directly to `config.json` require a **restart of RedEye** to take effect.
*   Configuration can also be modified at runtime by connected Agents using IPC commands (see `IPC_Reference.md` for details). Runtime changes made via IPC are saved back to `config.json`.

## Permissions Required

RedEye may require the following macOS permissions depending on its configuration:

*   **Accessibility Access:** (System Settings > Privacy & Security > Accessibility)
    *   Needed for: Capturing selected text (`HotkeyManager`, `InputMonitorManager`).
*   **Input Monitoring:** (System Settings > Privacy & Security > Input Monitoring)
    *   Needed for: Global Keyboard Event monitoring (`KeyboardMonitorManager`). RedEye will only prompt for this if this monitor is enabled in your configuration.
*   **Full Disk Access (Potentially):** (System Settings > Privacy & Security > Full Disk Access)
    *   May be needed if `FSEventMonitorManager` is configured to monitor paths outside of RedEye's standard sandbox access or user's primary directories (e.g., system-wide paths, other users' folders). For typical user folders (`~/Documents`, `~/Desktop`, `~/Downloads`), this is usually not required.
*   **Automation (for Safari URL Capture - Experimental):** (System Settings > Privacy & Security > Automation)
    *   If `enableBrowserURLCapture` for `appActivationMonitor` is enabled, RedEye will need permission to control Safari. This permission has proven problematic to grant reliably on some systems during development.

## Troubleshooting & Logs

*   **Logs:** RedEye uses the macOS Unified Logging system. You can view its logs using the **Console.app**.
    *   Open Console.app (from Applications > Utilities).
    *   In the search bar, you can filter by RedEye's subsystem identifier (usually `com.vic.RedEye` or similar, check `RedEyeLogger.subsystem` in the source if unsure) or by specific categories used in the logs (e.g., "ConfigurationManager", "KeyboardMonitorManager").
    *   Ensure "Info" and "Debug" messages are enabled in Console's Action menu if you need more detailed output (especially if you've set a `debug` or `trace` `logLevel` in `config.json`).
*   **Configuration Reset:** If RedEye behaves unexpectedly, you can try resetting its configuration:
    1.  Quit RedEye.
    2.  Delete the `~/Library/Application Support/RedEye/config.json` file.
    3.  Relaunch RedEye. It will create a new default configuration file.
    *   Alternatively, send the `resetConfigToDefaults` IPC command if an Agent is connected.

## Development & Contribution

For information on building RedEye, contributing, or understanding its architecture and IPC protocol in detail, please refer to the documents in the `/docs` directory of the project repository, particularly:
*   `/docs/developer_guide/Architecture.md`
*   `/docs/api_reference/IPC_Reference.md`

---
This project is currently under active development.