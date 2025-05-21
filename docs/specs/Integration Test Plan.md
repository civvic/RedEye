## Configuration System (Phase 1.A)

**Goal:** Verify that RedEye correctly loads, applies, modifies (via IPC), and persists configuration settings, and that monitor behavior reflects these settings.

**Prerequisites:**
1.  Ensure you have the latest code with all the configuration system changes merged and built successfully.
2.  Have a WebSocket client tool ready (e.g., Postman, Simple WebSocket Client browser extension, or a custom script) to send IPC commands to RedEye. RedEye's WebSocket server runs on `ws://localhost:8765`.
3.  Be prepared to monitor RedEye's logs (e.g., via Console.app, filtering by your subsystem identifier or categories like "ConfigurationManager", "AppDelegate", and specific monitor managers).

**Test Scenarios:**

**Scenario 1: First Run & Default Configuration Creation**
1.  **Cleanup:**
    *   Navigate to `~/Library/Application Support/`.
    *   **Delete** the `RedEye` directory entirely (if it exists) to simulate a first run.
2.  **Launch RedEye.**
3.  **Verification:**
    *   **V1.1 (Log Check):** Check RedEye logs for messages indicating:
        *   `ConfigurationManager` attempting to load config.
        *   "Failed to load configuration..." (expected on first run).
        *   "Using default configuration and attempting to save."
        *   "Default configuration saved successfully."
        *   `ConfigurationManager` initialized successfully.
    *   **V1.2 (File Check):**
        *   Verify that the `~/Library/Application Support/RedEye/` directory has been created.
        *   Verify that `config.json` exists inside it.
    *   **V1.3 (File Content Check - Basic):**
        *   Open `config.json`.
        *   Confirm it contains valid JSON.
        *   Spot-check a few default values against what's defined in `RedEyeConfig.defaultConfig()`:
            *   `schemaVersion` should be "1.0".
            *   `generalSettings.showPluginPanelOnHotkeyCapture` should be `false`.
            *   `monitorSettings.keyboardMonitorManager.isEnabled` should be `true`.
            *   `monitorSettings.appActivationMonitor.isEnabled` should be `false`.
            *   `monitorSettings.appActivationMonitor.parameters.enableBrowserURLCapture` should be `false`.
            *   `monitorSettings.fsEventMonitorManager.parameters.paths` should be an empty array `[]`.
    *   **V1.4 (Application Behavior - Basic):**
        *   Based on default config:
            *   Keyboard events should be logged by RedEye (as `keyboardMonitorManager` is enabled by default). Type something.
            *   App activation events (other than Safari URL capture) should *not* be logged (as `appActivationMonitor` is disabled by default). Switch apps.
            *   The ⌘⇧C hotkey should capture text, but the plugin UI panel should *not* appear.

**Scenario 2: Loading Existing Configuration & Behavior**
1.  **Preparation:**
    *   Ensure RedEye is **not running**.
    *   Open `~/Library/Application Support/RedEye/config.json`.
    *   **Modify** some settings:
        *   Set `monitorSettings.appActivationMonitor.isEnabled` to `true`.
        *   Set `monitorSettings.appActivationMonitor.parameters.enableBrowserURLCapture` to `true` (if you want to test this, be aware of the existing TCC permission issues).
        *   Set `monitorSettings.keyboardMonitorManager.isEnabled` to `false`.
        *   Set `generalSettings.showPluginPanelOnHotkeyCapture` to `true`.
        *   Set `monitorSettings.fsEventMonitorManager.isEnabled` to `true`.
        *   Modify `monitorSettings.fsEventMonitorManager.parameters.paths` to `["~/Desktop"]` (or another specific, easily testable path).
    *   Save `config.json`.
2.  **Launch RedEye.**
3.  **Verification:**
    *   **V2.1 (Log Check):** Check logs for:
        *   `ConfigurationManager` attempting to load config.
        *   "Configuration loaded successfully." (No "default config" messages).
        *   Messages from monitor managers indicating they are starting/not starting based on *your modified settings*. E.g., "KeyboardMonitorManager: Monitoring is disabled via configuration." and "AppActivationMonitor: Starting application activation monitoring (as configured)."
    *   **V2.2 (Application Behavior):**
        *   Keyboard events should *not* be logged.
        *   App activation events *should* be logged. If `enableBrowserURLCapture` was true and Safari is activated, observe behavior (and potential permission errors in logs).
        *   The ⌘⇧C hotkey should capture text, and the plugin UI panel *should* appear.
        *   Create/modify/delete a file on your Desktop (or the path you configured for `fsEventMonitorManager`). Verify FS events are logged.

**Scenario 3: IPC Command - Getters**

1.  **Preparation:**
    *   Launch RedEye (it can be with default or modified config from Scenario 2).
    *   Connect your WebSocket client to `ws://localhost:8765`.
2.  **Execute IPC Commands & Verify Responses:**
    *   **V3.1 (`getCapabilities`):**
        *   Send: `{ "action": "getCapabilities", "commandId": "cap1" }`
        *   Response: Should be a JSON object with `"status": "success"`, `"commandId": "cap1"`, and a `data` payload containing `appName`, `configSchemaVersion`, `availableEventMonitors` (listing all monitors and their parameter descriptions), `availableEventTypes`. Verify the structure and some key values.
    *   **V3.2 (`getConfig`):**
        *   Send: `{ "action": "getConfig", "commandId": "cfg1" }`
        *   Response: Should contain the full current `RedEyeConfig` object in the `data` field. Compare it with your `config.json` file (or expected defaults).
    *   **V3.3 (`getMonitorSetting`):**
        *   Send: `{ "action": "getMonitorSetting", "commandId": "monSet1", "payload": { "monitorType": "keyboardMonitorManager" } }`
        *   Response: Should contain the `MonitorSpecificConfig` for `keyboardMonitorManager` in the `data` field. Verify its `isEnabled` and `parameters`.
    *   **V3.4 (`getGeneralSettings`):**
        *   Send: `{ "action": "getGeneralSettings", "commandId": "genSet1" }`
        *   Response: Should contain the `GeneralAppSettings` in the `data` field.

**Scenario 4: IPC Command - Setters & Persistence**

1.  **Preparation:**
    *   Launch RedEye. Note the current state of a few monitors (e.g., `keyboardMonitorManager.isEnabled`, `appActivationMonitor.isEnabled`).
    *   Connect your WebSocket client.
2.  **Execute IPC Commands & Verify:**
    *   **V4.1 (`setMonitorEnabled`):**
        *   Command: `{ "action": "setMonitorEnabled", "commandId": "setMon1", "payload": { "monitorType": "keyboardMonitorManager", "isEnabled": false } }` (assuming it was true).
        *   Response: ACK with `"status": "success"`.
        *   Behavior Change: Keyboard events should stop being logged by RedEye (if they were before).
        *   File Check: Open `config.json`. Verify `keyboardMonitorManager.isEnabled` is now `false`.
    *   **V4.2 (`setMonitorParameters` for FSEvents):**
        *   Command: `{ "action": "setMonitorParameters", "commandId": "setFsParam1", "payload": { "monitorType": "fsEventMonitorManager", "parameters": { "paths": [ "~/Documents", "~/Pictures" ] } } }`
        *   Response: ACK.
        *   Behavior Change (Requires `fsEventMonitorManager` to be enabled and to reconfigure its stream based on new params, which our current implementation does on next `start`): For now, verify file. *Self-correction: Our current `setMonitorParameters` in `ConfigurationManager` saves to file but doesn't live-notify managers to reconfigure. So, behavior change might only be visible after restart or if we implement live updates.*
        *   File Check: Open `config.json`. Verify `fsEventMonitorManager.parameters.paths` is updated.
        *   **Restart RedEye.** Verify FS events are now monitored for `~/Documents` and `~/Pictures` (if FS monitor is enabled).
    *   **V4.3 (`setGeneralSettings`):**
        *   Command: `{ "action": "setGeneralSettings", "commandId": "setGen1", "payload": { "showPluginPanelOnHotkeyCapture": true } }` (assuming it was false).
        *   Response: ACK.
        *   Behavior Change: Press ⌘⇧C. The plugin UI panel should now appear.
        *   File Check: Open `config.json`. Verify `generalSettings.showPluginPanelOnHotkeyCapture` is now `true`.
3.  **Restart RedEye.**
4.  **Post-Restart Verification:**
    *   All changes made via IPC in V4.1, V4.2 (paths), V4.3 should persist and be active. Verify associated application behaviors.

**Scenario 5: IPC Command - `resetConfigToDefaults`**

1.  **Preparation:**
    *   Launch RedEye. Make some changes via IPC or by editing `config.json` so it's different from defaults.
    *   Connect WebSocket client.
2.  **Execute Command:**
    *   Send: `{ "action": "resetConfigToDefaults", "commandId": "reset1" }`
3.  **Verification:**
    *   **V5.1 (Response):** Should be an ACK.
    *   **V5.2 (File Check):** `config.json` should now match the content of a freshly created default config.
    *   **V5.3 (Behavior Check - after reset, before restart):** RedEye's behavior *might not* immediately reflect defaults unless managers live-reload (not implemented yet). The critical part is the file persistence.
    *   **V5.4 (Restart & Behavior):** Restart RedEye. Its behavior should now fully align with the default settings (as in V1.4).
