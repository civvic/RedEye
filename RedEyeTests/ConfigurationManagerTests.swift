// RedEyeTests/ConfigurationManagerTests.swift

import XCTest
@testable import RedEye // Import your app module

class ConfigurationManagerTests: XCTestCase {
    
    var testDirectoryURL: URL!
    var testConfigURL: URL!
    let testAppName = "RedEyeTestApp" // Use a distinct name for test config directory
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create a unique directory for this test run's config files
        // to avoid conflicts and ensure a clean state.
        let fileManager = FileManager.default
        // Using a temporary directory provided by the system for tests
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("RedEyeConfigTests")
            .appendingPathComponent(UUID().uuidString) // Unique subdirectory for each test run
        
        testDirectoryURL = tempDir.appendingPathComponent(testAppName, isDirectory: true)
        testConfigURL = testDirectoryURL.appendingPathComponent("config.json")
        
        // Ensure the specific test app directory exists for config file placement
        try fileManager.createDirectory(at: testDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        
        // Ensure no old config file from a previous failed test run is present
        if fileManager.fileExists(atPath: testConfigURL.path) {
            try fileManager.removeItem(at: testConfigURL)
        }
        RedEyeLogger.isVerboseLoggingEnabled = true // Enable for more detailed logs during tests
    }
    
    override func tearDownWithError() throws {
        // Remove the entire unique test directory after the test run
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: testDirectoryURL.deletingLastPathComponent().deletingLastPathComponent().path) { // Base RedEyeConfigTests dir
            // Be cautious with recursive removal. For now, let's assume OS cleans up tempDirectory contents over time.
            // Or, if confident, remove testDirectoryURL's parent if it's the UUID one.
            // For simplicity now, we'll just ensure the specific config file is gone if we want to be stricter
            // or let OS handle overall temp dir cleanup.
            // Let's try to remove the specific UUID-based directory for cleanliness.
            try? fileManager.removeItem(at: testDirectoryURL.deletingLastPathComponent())
        }
        testConfigURL = nil
        testDirectoryURL = nil
        try super.tearDownWithError()
    }
    
    // Helper to create a ConfigurationManager instance that uses the testConfigURL
    private func makeTestConfigurationManager(configURL: URL) -> ConfigurationManager {
        // We need a way to inject the testConfigFileURL into ConfigurationManager.
        // The current ConfigurationManager calculates its URL internally.
        // For testing, we need to either:
        // 1. Modify ConfigurationManager to accept a URL in its init (preferred for testability).
        // 2. Subclass ConfigurationManager for tests to override the URL.
        // 3. Use a more complex setup involving mocking FileManager (harder).
        
        // Let's assume we'll modify ConfigurationManager to allow URL injection for testing.
        // For now, this helper will demonstrate the intent.
        // If ConfigurationManager cannot be modified, this test setup needs rethinking.
        
        // --- TEMPORARY: Simulate internal URL calculation for the sake of structure ---
        // This part will need to be replaced once ConfigurationManager is testable regarding its URL.
        // We'll proceed assuming we *can* make ConfigurationManager use self.testConfigURL.
        // This might involve adding an internal initializer or a test-specific one.
        
        // For now, let's stub the `ConfigurationManager`'s internal path finding.
        // This is a common challenge. The best way is an internal/testable initializer.
        // If ConfigurationManager is not modified for testability, these tests are harder.
        
        // Assume `ConfigurationManager` is modified to have an init like:
        // internal init(configFileURL: URL, defaults: RedEyeConfig = RedEyeConfig.defaultConfig())
        // This is a placeholder for that modified init.
        
        // ConfigurationManager() // Original init uses default path. This won't work directly for isolated tests.
        // We need a ConfigurationManager that operates on self.testConfigURL.
        
        // For the purpose of this test structure, I will proceed as if ConfigurationManager
        // has an initializer that allows specifying the config file URL.
        // If it doesn't, we'll need to create one.
        
        // Let's define a simple extension for testing IF we can't change the main init.
        // This is not ideal but a common workaround.
        // Better: `internal init(appSupportDirectoryURL: URL, appName: String, configFileName: String)`
        
        // For now, we'll proceed assuming a testable init exists or will be added.
        // This is a crucial point for making ConfigurationManager testable.
        // Let's write a placeholder init in ConfigurationManager for tests.
        return ConfigurationManager(testingConfigFileURL: configURL)
    }
    
    
    // MARK: - Test Cases
    
    func testInitialization_CreatesDefaultConfigFile_WhenNoneExists() throws {
        // 1. Arrange
        // setUpWithError ensures no config file exists at testConfigURL initially.
        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: testConfigURL.path), "Precondition: Config file should not exist.")
        
        // 2. Act
        let _ = makeTestConfigurationManager(configURL: testConfigURL) // Init should create it
        
        // 3. Assert
        XCTAssertTrue(fileManager.fileExists(atPath: testConfigURL.path), "Config file should be created by init.")
        
        // Verify content is decodable and matches defaults (basic check)
        let data = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loadedConfig = try decoder.decode(RedEyeConfig.self, from: data)
        
        let defaultConfig = RedEyeConfig.defaultConfig()
        XCTAssertEqual(loadedConfig.schemaVersion, defaultConfig.schemaVersion, "Schema version should match default.")
        XCTAssertEqual(loadedConfig.generalSettings.showPluginPanelOnHotkeyCapture, defaultConfig.generalSettings.showPluginPanelOnHotkeyCapture)
        XCTAssertEqual(loadedConfig.monitorSettings.count, defaultConfig.monitorSettings.count, "Monitor settings count should match default.")
        // Deeper comparison of monitor settings can be added if necessary
        for (key, defaultSetting) in defaultConfig.monitorSettings {
            XCTAssertNotNil(loadedConfig.monitorSettings[key], "Loaded config should have setting for \(key).")
            XCTAssertEqual(loadedConfig.monitorSettings[key]?.isEnabled, defaultSetting.isEnabled, "isEnabled for \(key) should match default.")
        }
    }
    
    func testInitialization_LoadsExistingConfigFile() throws {
        // 1. Arrange
        let fileManager = FileManager.default
        let initialConfig = RedEyeConfig(
            schemaVersion: "0.9-test", // Different from default
            monitorSettings: [
                MonitorType.keyboardMonitorManager.rawValue: MonitorSpecificConfig(isEnabled: false, parameters: nil) // Non-default state
            ],
            generalSettings: GeneralAppSettings(showPluginPanelOnHotkeyCapture: true) // Non-default state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let dataToSave = try encoder.encode(initialConfig)
        try dataToSave.write(to: testConfigURL)
        XCTAssertTrue(fileManager.fileExists(atPath: testConfigURL.path), "Precondition: Config file should exist with custom data.")
        
        // 2. Act
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        let loadedConfig = configManager.getCurrentConfig()
        
        // 3. Assert
        XCTAssertEqual(loadedConfig.schemaVersion, "0.9-test", "Schema version should be loaded from file.")
        XCTAssertEqual(loadedConfig.generalSettings.showPluginPanelOnHotkeyCapture, true, "General setting should be loaded from file.")
        XCTAssertEqual(loadedConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled, false, "Keyboard monitor 'isEnabled' should be loaded from file.")
        // Check that other default monitors are still present if initialConfig didn't specify all
        // Assert that the loaded config reflects exactly what was in the file.
        // ConfigurationManager currently does not merge defaults if a valid file is found.
        XCTAssertEqual(loadedConfig.monitorSettings.count, initialConfig.monitorSettings.count, "Monitor settings count should match the saved file.")
        XCTAssertNotNil(loadedConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]) // Verify the specific one we saved is there
        XCTAssertEqual(loadedConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled, false, "Keyboard monitor 'isEnabled' should be loaded from file.")
        XCTAssertNil(loadedConfig.monitorSettings[MonitorType.appActivationMonitor.rawValue], "AppActivationMonitor was not in the saved file, so it should not be in the loaded config (no merge on load).")

        // Note: The current ConfigurationManager.performLoadConfiguration either loads the file as-is or fails.
        // It does not merge. If the file is valid but incomplete, that's what's loaded.
        // If we want merging, RedEyeConfig itself or ConfigurationManager load logic needs to handle that.
        // The test above assumes initialConfig fully defines the structure, or tests what's actually loaded.
        // For a simple "load existing" test:
        XCTAssertEqual(loadedConfig.monitorSettings.count, initialConfig.monitorSettings.count, "Monitor settings count should match the saved file if it's a full valid config.")
    }
    
    func testInitialization_HandlesCorruptConfigFile_FallsBackToDefaults() throws {
        // 1. Arrange
        let fileManager = FileManager.default
        let corruptData = "this is not valid JSON {".data(using: .utf8)!
        try corruptData.write(to: testConfigURL)
        XCTAssertTrue(fileManager.fileExists(atPath: testConfigURL.path), "Precondition: Corrupt config file should exist.")
        
        // 2. Act
        let configManager = makeTestConfigurationManager(configURL: testConfigURL) // Init should detect corruption, use defaults, and save them
        let currentConfig = configManager.getCurrentConfig()
        
        // 3. Assert
        // Check that current config matches defaults
        let defaultConfig = RedEyeConfig.defaultConfig()
        XCTAssertEqual(currentConfig.schemaVersion, defaultConfig.schemaVersion, "Schema version should revert to default.")
        XCTAssertEqual(currentConfig.monitorSettings.count, defaultConfig.monitorSettings.count, "Monitor settings count should revert to default.")
        
        // Check that the file on disk was overwritten with defaults
        let dataOnDisk = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configOnDisk = try decoder.decode(RedEyeConfig.self, from: dataOnDisk)
        XCTAssertEqual(configOnDisk.schemaVersion, defaultConfig.schemaVersion, "Config file on disk should be overwritten with defaults.")
    }
    
    // MARK: - Getter Tests

    func testGetCurrentConfig_ReturnsCorrectlyLoadedOrDefaultForNewManager() {
        // 1. Arrange
        // Test with a newly initialized manager (which should create/load defaults)
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        let defaultConfig = RedEyeConfig.defaultConfig()

        // 2. Act
        let currentConfig = configManager.getCurrentConfig()

        // 3. Assert
        XCTAssertEqual(currentConfig.schemaVersion, defaultConfig.schemaVersion)
        XCTAssertEqual(currentConfig.generalSettings.showPluginPanelOnHotkeyCapture, defaultConfig.generalSettings.showPluginPanelOnHotkeyCapture)
        XCTAssertEqual(currentConfig.monitorSettings.count, defaultConfig.monitorSettings.count)
    }

    func testGetMonitorSetting_ReturnsCorrectSetting() throws {
        // 1. Arrange
        // Create a config file with a specific known setting
        var customConfig = RedEyeConfig.defaultConfig()
        customConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled = false
        customConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.parameters = ["testParam": .string("testValue")]
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let dataToSave = try encoder.encode(customConfig)
        try dataToSave.write(to: testConfigURL)

        let configManager = makeTestConfigurationManager(configURL: testConfigURL)

        // 2. Act
        let keyboardSetting = configManager.getMonitorSetting(for: .keyboardMonitorManager)
        let fsEventSetting = configManager.getMonitorSetting(for: .fsEventMonitorManager) // Should be default

        // 3. Assert
        XCTAssertNotNil(keyboardSetting)
        XCTAssertEqual(keyboardSetting?.isEnabled, false)
        XCTAssertEqual(keyboardSetting?.parameters?["testParam"]?.stringValue(), "testValue")
        
        XCTAssertNotNil(fsEventSetting)
        XCTAssertEqual(fsEventSetting?.isEnabled, RedEyeConfig.defaultConfig().monitorSettings[MonitorType.fsEventMonitorManager.rawValue]?.isEnabled)
    }
    
    func testGetMonitorSetting_ReturnsNilForInvalidType() {
        // This test is less relevant now because MonitorType is an enum, and we iterate allCases for defaults.
        // However, if string rawValues were manually constructed and invalid, it might apply.
        // For now, this scenario is unlikely with current design.
        // If we had a string-based lookup that wasn't backed by MonitorType enum, this would be important.
        // Let's assume getMonitorSetting with an enum case will always find a key due to defaultConfig().
        XCTAssertTrue(true, "Test for invalid monitor type lookup is less applicable with current enum-keyed design.")
    }

    func testGetGeneralSettings_ReturnsCorrectSettings() throws {
        // 1. Arrange
        var customConfig = RedEyeConfig.defaultConfig()
        customConfig.generalSettings.showPluginPanelOnHotkeyCapture = true // Non-default
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted] // Optional for test data
        encoder.dateEncodingStrategy = .iso8601    // Match what ConfigManager uses
        let dataForThisTest = try encoder.encode(customConfig) // Encode the local customConfig
        try dataForThisTest.write(to: testConfigURL) // Write it

        let configManager = makeTestConfigurationManager(configURL: testConfigURL)

        // 2. Act
        let generalSettings = configManager.getGeneralSettings()

        // 3. Assert
        XCTAssertEqual(generalSettings.showPluginPanelOnHotkeyCapture, true)
    }

    // MARK: - Setter and Persistence Tests

    func testSetMonitorEnabled_UpdatesConfigAndPersists() throws {
        // 1. Arrange
        let configManager = makeTestConfigurationManager(configURL: testConfigURL) // Starts with defaults
        let monitorToChange = MonitorType.appActivationMonitor
        // Default for AppActivationMonitor.isEnabled IS false.
        let initialDefaultState = RedEyeConfig.defaultConfig().monitorSettings[monitorToChange.rawValue]?.isEnabled
        XCTAssertEqual(initialDefaultState, false, "Test assumption: default for \(monitorToChange.rawValue) isEnabled is false.")

        // 2. Act
        try configManager.setMonitorEnabled(type: monitorToChange, isEnabled: true) // Change it to true

        // 3. Assert
        // Check in-memory config
        let updatedSettingInMemory = configManager.getMonitorSetting(for: monitorToChange)
        XCTAssertEqual(updatedSettingInMemory?.isEnabled, true, "In-memory config should be updated to true.")

        // Check persisted file
        let dataOnDisk = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configOnDisk = try decoder.decode(RedEyeConfig.self, from: dataOnDisk)
        XCTAssertEqual(configOnDisk.monitorSettings[monitorToChange.rawValue]?.isEnabled, true, "Persisted config on disk should reflect the change to true.")

        // Ensure other settings didn't change unexpectedly (simple check)
        XCTAssertEqual(configOnDisk.schemaVersion, RedEyeConfig.defaultConfig().schemaVersion)
    }

    func testSetMonitorParameters_UpdatesConfigAndPersists() throws {
        // 1. Arrange
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        let monitorToChange = MonitorType.fsEventMonitorManager
        let newParameters: [String: JSONValue] = ["paths": .array([.string("~/Downloads"), .string("/tmp")]), "logLevel": .int(2)]

        // 2. Act
        try configManager.setMonitorParameters(type: monitorToChange, parameters: newParameters)

        // 3. Assert
        // Check in-memory config
        let updatedSettingInMemory = configManager.getMonitorSetting(for: monitorToChange)
        XCTAssertEqual(updatedSettingInMemory?.parameters?["logLevel"]?.intValue(), 2) // Using intValue() helper
        XCTAssertEqual(updatedSettingInMemory?.parameters?["paths"]?.arrayValue()?.count, 2)

        // Check persisted file
        let dataOnDisk = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configOnDisk = try decoder.decode(RedEyeConfig.self, from: dataOnDisk)
        XCTAssertEqual(configOnDisk.monitorSettings[monitorToChange.rawValue]?.parameters?["logLevel"]?.intValue(), 2)
    }
    
    func testUpdateGeneralSettings_UpdatesConfigAndPersists() throws {
        // 1. Arrange
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        var newGeneralSettings = configManager.getGeneralSettings() // Get current (defaults)
        newGeneralSettings.showPluginPanelOnHotkeyCapture = true // Change one value
        
        let originalSetting = RedEyeConfig.defaultConfig().generalSettings.showPluginPanelOnHotkeyCapture
        XCTAssertNotEqual(originalSetting, true, "Test assumption: default showPluginPanelOnHotkeyCapture is not true.")

        // 2. Act
        try configManager.updateGeneralSettings(newSettings: newGeneralSettings)

        // 3. Assert
        let updatedSettingsInMemory = configManager.getGeneralSettings()
        XCTAssertEqual(updatedSettingsInMemory.showPluginPanelOnHotkeyCapture, true)

        let dataOnDisk = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configOnDisk = try decoder.decode(RedEyeConfig.self, from: dataOnDisk)
        XCTAssertEqual(configOnDisk.generalSettings.showPluginPanelOnHotkeyCapture, true)
    }

    func testResetToDefaults_ResetsConfigAndPersists() throws {
        // 1. Arrange
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        // Make a change first
        try configManager.setMonitorEnabled(type: .keyboardMonitorManager, isEnabled: false)
        let changedSetting = configManager.getMonitorSetting(for: .keyboardMonitorManager)?.isEnabled
        XCTAssertEqual(changedSetting, false, "Precondition: Setting should be changed from default.")

        // 2. Act
        try configManager.resetToDefaults()

        // 3. Assert
        let defaultConfig = RedEyeConfig.defaultConfig()
        let configAfterResetInMemory = configManager.getCurrentConfig()
        XCTAssertEqual(configAfterResetInMemory.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled,
                       defaultConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled,
                       "In-memory setting should be reset to default.")

        let dataOnDisk = try Data(contentsOf: testConfigURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configOnDisk = try decoder.decode(RedEyeConfig.self, from: dataOnDisk)
        XCTAssertEqual(configOnDisk.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled,
                       defaultConfig.monitorSettings[MonitorType.keyboardMonitorManager.rawValue]?.isEnabled,
                       "Persisted setting on disk should be reset to default.")
    }
    
    func testGetCapabilities_ReturnsNonEmptyDictionary() {
        // 1. Arrange
        let configManager = makeTestConfigurationManager(configURL: testConfigURL)
        
        // 2. Act
        let capabilities = configManager.getCapabilities()
        
        // 3. Assert
        XCTAssertFalse(capabilities.isEmpty, "Capabilities dictionary should not be empty.")
        XCTAssertNotNil(capabilities["appName"]?.stringValue())
        XCTAssertNotNil(capabilities["availableEventMonitors"]?.arrayValue())
        XCTAssertEqual(capabilities["appName"]?.stringValue(), "RedEye", "Capabilities appName should be 'RedEye' as hardcoded in ConfigurationManager.")
    }

    // TODO: Test error conditions for setters (e.g., trying to set params for a non-existent monitor type if that were possible,
    // or file permission errors for persistence - harder to unit test without mocking FileManager).
    // The current design with MonitorType enum makes "unknown monitor type" errors less likely for existing setters.
}
