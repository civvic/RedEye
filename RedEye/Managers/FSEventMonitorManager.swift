// RedEye/Managers/FSEventMonitorManager.swift

import Foundation
import CoreServices

// << NEW: Define the C callback function at the global scope or as a static function >>
// This C-style callback function does not capture any context.
private func fsEventStreamCallbackTrampoline(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?, // This is our 'self'
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer, // CFArray of CFStringRefs
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    // Check if clientCallBackInfo (context) is valid
    guard let contextInfo = clientCallBackInfo else {
        // This would be a critical error, as context should always be provided.
        // Log directly or find a way to log without an instance if this happens.
        // For now, print to console as a last resort if RedEyeLogger isn't accessible here.
        print("CRITICAL FSEVENTS ERROR: fsEventStreamCallbackTrampoline received nil clientCallBackInfo.")
        return
    }
    
    // Reconstitute the FSEventMonitorManager instance from the opaque pointer
    let managerInstance = Unmanaged<FSEventMonitorManager>.fromOpaque(contextInfo).takeUnretainedValue()
    
    // Call the instance method to handle the events
    managerInstance.handleFSEvents(
        numEvents: numEvents,
        eventPaths: eventPaths, // Pass the raw pointer, handle casting inside
        eventFlags: eventFlags,
        eventIds: eventIds
    )
}

class FSEventMonitorManager: BaseMonitorManager {

    private var streamRef: FSEventStreamRef?
    private var dispatchQueue: DispatchQueue // Use a dispatch queue instead of RunLoop
    private var callbackContext: FSEventStreamContext
    
    override var logCategoryForInstance: String { "FSEventMonitorManager" }

    init(eventBus: EventBus, configManager: ConfigurationManaging, queueLabel: String = "com.vic.RedEye.FSEventMonitorQueue") {
        // Store specific dependencies before super.init if needed by base, or pass them up.
        // Here, dispatchQueue and callbackContext are specific to FSEventMonitorManager.
        self.dispatchQueue = DispatchQueue(label: queueLabel, qos: .utility)
        self.callbackContext = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        
        super.init(monitorType: .fsEventMonitorManager, eventBus: eventBus, configManager: configManager)
        
        self.callbackContext.info = Unmanaged.passUnretained(self).toOpaque()
        info("FSEventMonitorManager specific initialization complete.")
    }

    private func internalDefaultPaths() -> [String] {
        let defaultDirs: [FileManager.SearchPathDirectory] = [.documentDirectory, .downloadsDirectory]
        let paths = defaultDirs.compactMap { dir in
            FileManager.default.urls(for: dir, in: .userDomainMask).first?.path
        }
        if paths.count != defaultDirs.count {
             error("Could not resolve all internal default paths (Documents, Downloads).")
        }
        return paths
    }

    override func startMonitoring() -> Bool {
        guard streamRef == nil else {
            // Use .error as this indicates unexpected state / logic error
            error("Attempted to start monitoring, but stream already exists.")
            return true
        }
        
        var pathsToWatchEffective: [String]
        // Path retrieval logic using currentMonitorConfig.parameters and internalDefaultPaths()
        if let pathsFromConfig = currentMonitorConfig?.parameters?["paths"]?.arrayValue()?.compactMap({ $0.stringValue() }) {
            if pathsFromConfig.isEmpty {
                info("'paths' parameter is empty in config. Using internal default paths.")
                pathsToWatchEffective = internalDefaultPaths()
            } else {
                info("Using 'paths' from configuration: \(pathsFromConfig)")
                pathsToWatchEffective = pathsFromConfig.map { NSString(string: $0).expandingTildeInPath }
            }
        } else {
            info("'paths' parameter not found or invalid in config. Using internal default paths.")
            pathsToWatchEffective = internalDefaultPaths()
        }

        guard !pathsToWatchEffective.isEmpty else {
             error("Attempted to start monitoring, but no paths are configured or resolved.")
             return false
         }

        info("Attempting to start FSEvent monitoring for paths: \(pathsToWatchEffective)... (as configured)")

        // Define combined flags explicitly as FSEventStreamCreateFlags
        let streamFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        streamRef = FSEventStreamCreate(
            nil,
            fsEventStreamCallbackTrampoline,
            &callbackContext,
            pathsToWatchEffective as CFArray, // << Use effective paths
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            streamFlags
        )

        if let stream = streamRef {
            FSEventStreamSetDispatchQueue(stream, self.dispatchQueue)
            if FSEventStreamStart(stream) {
                info("FSEvent stream started successfully on \(self.dispatchQueue.label). Watching: \(pathsToWatchEffective)")
                return true // Successfully started
            } else {
                error("Failed to start FSEvent stream.")
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                streamRef = nil
                return false // Failed to start
            }
        } else {
            error("Failed to create FSEvent stream (FSEventStreamCreate returned nil).")
            return false // Failed to create stream
        }
    }

    override func stopMonitoring() {
        guard let stream = streamRef else {
            debug("Attempted to stop FSEvents, but stream was not active.")
            return
        }
        info("Stopping FSEvent monitoring stream...")
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        info("FSEvent monitoring stream stopped and released.")
    }

    fileprivate func handleFSEvents(numEvents: Int, eventPaths: UnsafeRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIds: UnsafePointer<FSEventStreamEventId>) {
        guard self.isCurrentlyActive else { return } // Check base class active state
        guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else {
            error("Could not cast eventPaths CFArray to [String].")
            return
        }

        debug("Received \(numEvents) raw FSEvents.")

        for i in 0..<numEvents {
            let path = paths[i]
            let flags = eventFlags[i] // This is FSEventStreamEventFlags (UInt32)
            let eventId = eventIds[i]
            let flagsDict = interpretFSEventFlags(flags)

            info("""
                FS Event Detected:
                  ID: \(eventId)
                  Path: \(path)
                  Raw Flags: \(String(format: "0x%08X", flags))
                  Interpreted Flags: \(flagsDict)
                """)

            // --- Event Creation ---
             let event = RedEyeEvent(
                 eventType: .fileSystemEvent, // <<< NEEDS DEFINITION
                 sourceApplicationName: nil,
                 sourceBundleIdentifier: nil,
                 contextText: path,
                 metadata: [
                     "fs_event_id": "\(eventId)",
                     "fs_raw_flags": String(format: "0x%08X", flags)
                 ].merging(flagsDict) { (_, new) in new }
             )
            // --- End Event Creation ---

            eventBus?.publish(event: event)
        }
    }

    // Helper function to convert flags into a human-readable dictionary
    private func interpretFSEventFlags(_ flags: FSEventStreamEventFlags) -> [String: String] {
        var interpretations: [String: String] = [:]

        // Explicitly cast constants to FSEventStreamEventFlags for checks
        // Although these constants *should* already be the correct type,
        // this might resolve compiler issues seen earlier.

        // Root directory change
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 { interpretations["fs_root_changed"] = "true" }

        // Mount/Unmount
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMount) != 0 { interpretations["fs_mount"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount) != 0 { interpretations["fs_unmount"] = "true" }

        // Item-level flags
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 { interpretations["fs_item_created"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 { interpretations["fs_item_removed"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod) != 0 { interpretations["fs_item_inode_meta_mod"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 { interpretations["fs_item_renamed"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 { interpretations["fs_item_modified"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod) != 0 { interpretations["fs_item_finder_info_mod"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner) != 0 { interpretations["fs_item_change_owner"] = "true" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod) != 0 { interpretations["fs_item_xattr_mod"] = "true" }

        // Type checks
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 { interpretations["fs_item_type"] = "file" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 { interpretations["fs_item_type"] = "directory" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsSymlink) != 0 { interpretations["fs_item_type"] = "symlink" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsHardlink) != 0 { interpretations["fs_item_type"] = "hardlink" }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsLastHardlink) != 0 { interpretations["fs_item_last_hardlink"] = "true" }

        // Add note for uninterpreted flags
        if interpretations.isEmpty && flags != 0 {
             debug("FSEvent received with flags \(String(format: "0x%08X", flags)) but no specific item flags matched.")
             interpretations["fs_note"] = "No specific item flags detected (might be dir change, volume event, or other)"
         } else if flags == 0 {
             interpretations["fs_note"] = "Flags were zero."
         }

        return interpretations
    }
}
