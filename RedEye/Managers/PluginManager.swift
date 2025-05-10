//
//  PluginManager.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/10/25.
//

// PluginManager.swift

import Foundation

class PluginManager {

    private var discoveredPluginURLs: [URL] = []

    // Computed property for the plugin directory URL
    private var pluginDirectoryURL: URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            RedEyeLogger.error("Could not find Application Support directory.", category: "PluginManager")
            return nil
        }
        let redEyeAppSupportURL = appSupportURL.appendingPathComponent("RedEye", isDirectory: true)
        return redEyeAppSupportURL.appendingPathComponent("Plugins", isDirectory: true)
    }

    init() {
        discoverPlugins()
    }

    private func discoverPlugins() {
        guard let dirURL = pluginDirectoryURL else {
            RedEyeLogger.error("Plugin directory URL is nil. Cannot discover plugins.", category: "PluginManager")
            return
        }

        let fileManager = FileManager.default
        
        // Create the plugin directory if it doesn't exist
        // This is good practice, though for this step we manually created it.
        do {
            if !fileManager.fileExists(atPath: dirURL.path) {
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                RedEyeLogger.info("Created plugin directory at \(dirURL.path)", category: "PluginManager")
            }
        } catch {
            RedEyeLogger.error("Could not create plugin directory at \(dirURL.path)", category: "PluginManager", error: error)
            return // If we can't create/access it, no point proceeding
        }

        // Scan for files in the plugin directory
        do {
            let items = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            // For this stub, we'll consider any executable file a plugin,
            // or specifically look for our echo_plugin.sh
            self.discoveredPluginURLs = items.filter { itemURL in
                // Basic check: does it look like our echo plugin?
                // More robust checks would involve checking if it's executable,
                // or looking for a manifest file, etc.
                return itemURL.lastPathComponent == "echo_plugin.sh" && fileManager.isExecutableFile(atPath: itemURL.path)
            }

            if discoveredPluginURLs.isEmpty {
                RedEyeLogger.error("No plugins found (specifically 'echo_plugin.sh') in \(dirURL.path)", category: "PluginManager")
            } else {
                RedEyeLogger.info("Discovered plugins: \(discoveredPluginURLs.map { $0.lastPathComponent })", category: "PluginManager")
            }
        } catch {
            RedEyeLogger.error("Could not read contents of plugin directory \(dirURL.path): \(error.localizedDescription)", category: "PluginManager")
        }
    }

    func invokePlugins(withText text: String) {
        if discoveredPluginURLs.isEmpty {
            RedEyeLogger.info("No plugins to invoke.", category: "PluginManager")
            return
        }

        RedEyeLogger.info("Invoking plugins with text: \"\(text)\"", category: "PluginManager")

        for pluginURL in discoveredPluginURLs {
            RedEyeLogger.info("Attempting to run plugin: \(pluginURL.path)", category: "PluginManager")
            
            let process = Process()
            process.executableURL = pluginURL // The script itself is the executable

            // For shell scripts, it's often better to launch them via /bin/sh or /bin/bash
            // process.executableURL = URL(fileURLWithPath: "/bin/bash")
            // process.arguments = [pluginURL.path] // Pass the script as an argument to bash

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run() // Launch the process
                RedEyeLogger.info("Launched \(pluginURL.lastPathComponent).", category:"PluginManager")

                // Send the input text to the plugin's stdin
                if let inputData = text.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                    inputPipe.fileHandleForWriting.closeFile() // Close stdin to signal end of input
                } else {
                    RedEyeLogger.error("Could not convert input text to data for plugin \(pluginURL.lastPathComponent).", category:"PluginManager")
                }

                // Read output and error
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                if let outputString = String(data: outputData, encoding: .utf8), !outputString.isEmpty {
                    RedEyeLogger.info("Plugin \(pluginURL.lastPathComponent) STDOUT:\n\(outputString.trimmingCharacters(in: .whitespacesAndNewlines))", category:"PluginManager")
                }
                if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                    RedEyeLogger.error("Plugin \(pluginURL.lastPathComponent) STDERR:\n\(errorString.trimmingCharacters(in: .whitespacesAndNewlines))", category:"PluginManager")
                }
                
                process.waitUntilExit() // Wait for the process to complete
                let exitStatus = process.terminationStatus
                RedEyeLogger.info("\(pluginURL.lastPathComponent) finished with status \(exitStatus).", category:"PluginManager")

            } catch {
                RedEyeLogger.error("Failed to run plugin \(pluginURL.lastPathComponent)", category:"PluginManager", error:error)
            }
        }
    }
}
