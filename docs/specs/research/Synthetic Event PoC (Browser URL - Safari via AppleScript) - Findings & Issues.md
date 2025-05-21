**Objective:** Assess feasibility of capturing browser URL/Title from Safari using AppleScript, understand Automation permission workflow, and implement event emission.

**Implementation Approach:**
*   Defined `RedEyeEventType.browserNavigation`.
*   Added `NSAppleEventsUsageDescription` to target's Info properties.
*   Developed AppleScript to retrieve URL and title from Safari's frontmost tab.
*   Integrated script execution into `AppActivationMonitor`, triggered when Safari activates, with a dedicated `isEnabledBrowserURLCapture` flag.
*   Used `NSAppleScript` class in Swift for script execution.

**Observed TCC (Transparency, Consent, and Control) / Permissions Issues:**
During testing on macOS Sequoia (upgraded from Sonoma) with Xcode 16.2, significant and inconsistent issues were encountered regarding AppleEvent Automation permissions:

1.  **Initial Problem:** RedEye consistently received error -1743 (`errAEEventNotPermitted` - "Not authorized to send Apple events to Safari") when attempting to execute AppleScript targeting Safari. Crucially, **no system permission prompt for Automation appeared**, and RedEye was **not listed in System Settings > Privacy & Security > Automation**, preventing manual authorization.
2.  **Troubleshooting Steps Taken:**
    *   Verified `NSAppleEventsUsageDescription` in `Info.plist`.
    *   Cleaned build folders.
    *   Performed `tccutil reset AppleEvents` followed by Mac restarts.
    *   Upgraded macOS from Sonoma to Sequoia.
    *   Tested with progressively simpler AppleScripts.
3.  **Minimal Test App Success (Inconsistent for RedEye):**
    *   A brand-new, minimal macOS application (`SafariTestApp` / `EdgeTestApp`) **was able to successfully execute a simple AppleScript** (`return version`) targeting Safari (and subsequently Microsoft Edge when it was not running, resulting in an expected -600 error "Application isn't running").
    *   **Critically, even after these successful executions by the minimal test app, the Automation list in System Settings remained empty.** This indicates a potential systemic issue with TCC not durably recording permissions or reliably prompting on this specific test environment.
4.  **RedEye Inconsistency:**
    *   At one point, RedEye *also* managed to successfully execute the minimal "get version" script against Safari. However, this success was not consistently reproducible, and RedEye still did not appear in the Automation settings.
    *   Attempts to run more complex scripts (getting URL/Title) or scripts targeting Edge (when not running, expecting -600) from RedEye mostly reverted to the -1743 error without a prompt.

**Conclusion for PoC Step 4:**
*   The Swift code for initializing `NSAppleScript`, executing it, and parsing results (or errors) has been implemented.
*   The `RedEyeEventType.browserNavigation` and associated metadata structure are defined.
*   **Blocker:** The PoC cannot be validated end-to-end *at this time* due to persistent and unusual behavior of the macOS TCC framework regarding AppleEvent Automation permissions on the development system. The system is not reliably prompting for, nor allowing manual configuration of, the necessary permissions for the RedEye application, despite working intermittently for a minimal test app and once briefly for RedEye itself.
*   **Assumption for Proceeding:** For the purpose of completing other v0.3 goals (like refactoring), we will proceed with the *assumption* that on a stable and correctly functioning macOS environment, the implemented AppleScript interaction *would* either prompt for permission or respect a manually granted one. The code for script execution and event emission will be retained but the feature will remain disabled by default (`isEnabledBrowserURLCapture = false`).
*   **Future:** This issue needs to be revisited. It might be specific to the current macOS/Xcode beta combination or an environmental factor on the test machine. Further investigation into TCC diagnostics would be needed if this feature is to be enabled in the future.

**Recommendation:** The current implementation for Safari URL capture within `AppActivationMonitor` should be considered "experimental" and disabled by default. The primary learning about the mechanics of `NSAppleScript` and Automation permissions (and their potential for being problematic) has been achieved.


## test 01

```AppleScript
use AppleScript version "2.4" -- Yosemite (10.10) or later
use scripting additions

tell application "Safari"
		return version
end tell
```
### MinimalSafariApp: 

- Permission prompt: NO
- Result: 18.5
- Console:
```
Button pressed. Attempting AppleScript...
Attempting to execute MINIMAL Safari AppleScript...
MINIMAL AppleScript Result: 18.5
```

### ScriptDebugger:

- Permission prompt: NO
- Result: 18.5

## Test 02:

```
use AppleScript version "2.4" -- Yosemite (10.10) or later
use scripting additions

tell application "Safari"
		if not (exists front window) then return "error: No front window in Safari"
		try
				set currentTab to current tab of front window
				set theURL to URL of currentTab
				set theName to name of currentTab -- This is the page title
				
				if theURL is missing value then
						-- If URL is missing, page is likely not a standard web page (e.g. new tab, favorites)
						-- Return title if available, otherwise a generic error.
						if theName is not missing value and theName is not "" then
								return "error: URL is missing value. Title: " & theName
						else
								return "error: URL is missing value. No title available."
						end if
				else
						if theName is missing value then set theName to "" -- Ensure title is not missing value for concatenation
						return "URL: " & theURL & " --- Title: " & theName
				end if
		on error errMsg number errNum
				return "error: AppleScript execution error in Safari - " & errMsg & " (Number: " & errNum & ")"
		end try
end tell
```

### MinimalSafariApp

- Permission prompt: NO
- Result: N/A
- Console:
```
Button pressed. Attempting AppleScript...
Attempting to execute MINIMAL Safari AppleScript...
MINIMAL AppleScript System Error: Safari got an error: Application isn’t running. (Code: -600)
```

### ScriptDebugger:

- Permission prompt: YES
- Result: URL: https://www.youtube.com/ --- Title: YouTube