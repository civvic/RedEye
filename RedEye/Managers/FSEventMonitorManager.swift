// RedEye/Managers/FSEventMonitorManager.swift

import Foundation
import CoreServices

// Define a protocol for emitting events. This can be implemented by EventManager or the future EventBus.
// protocol FSEventMonitorDelegate: AnyObject {
//     func fsEventMonitor(_ monitor: FSEventMonitorManager, didEmit event: RedEyeEvent)
// }

class FSEventMonitorManager {

    private static let logCategory = "FSEventMonitor"
    private var streamRef: FSEventStreamRef?
    private var pathsToWatch: [String] = []
    private var dispatchQueue: DispatchQueue // Use a dispatch queue instead of RunLoop
    var isEnabled: Bool = true

    private let eventBus: EventBus

    private var callbackContext: FSEventStreamContext

    init(paths: [String] = [], eventBus: EventBus, queueLabel: String = "com.vic.RedEye.FSEventMonitorQueue") {
        self.eventBus = eventBus
        // Create a dedicated serial queue for handling FSEvents callbacks
        // QoS can be adjusted based on performance needs (.userInitiated or .utility often suitable)
        self.dispatchQueue = DispatchQueue(label: queueLabel, qos: .utility)
        self.callbackContext = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        self.callbackContext.info = Unmanaged.passUnretained(self).toOpaque()

        RedEyeLogger.info("FSEventMonitorManager initialized", category: FSEventMonitorManager.logCategory)
        configurePaths(paths: paths.isEmpty ? defaultPaths() : paths)
    }

    deinit {
        stopMonitoring()
        RedEyeLogger.info("FSEventMonitorManager deinitialized", category: FSEventMonitorManager.logCategory)
    }

    private func defaultPaths() -> [String] {
        // Correctly get directory URLs from FileManager.default
        let defaultDirs: [FileManager.SearchPathDirectory] = [.documentDirectory, .downloadsDirectory] // Use .documentDirectory
        let paths = defaultDirs.compactMap { dir in
            // Use .userDomainMask for user-specific directories
            FileManager.default.urls(for: dir, in: .userDomainMask).first?.path
        }
        if paths.count != defaultDirs.count {
             // Use .error as this prevents default setup
             RedEyeLogger.error("Could not resolve all default paths (Documents, Downloads). Check permissions or sandbox configuration.", category: FSEventMonitorManager.logCategory)
        }
        return paths
    }

    func configurePaths(paths: [String]) {
        self.pathsToWatch = paths.map { NSString(string: $0).expandingTildeInPath }
        RedEyeLogger.info("Configured to watch paths: \(self.pathsToWatch)", category: FSEventMonitorManager.logCategory)

        if self.pathsToWatch.contains(where: { !$0.starts(with: NSHomeDirectory()) }) {
            // Use .info for guidance message
            RedEyeLogger.info("Monitoring paths outside the user's home directory (\(NSHomeDirectory())) might require Full Disk Access permission.", category: FSEventMonitorManager.logCategory)
        }

        if streamRef != nil {
            RedEyeLogger.info("Paths changed while monitoring. Restarting stream...", category: FSEventMonitorManager.logCategory)
            stopMonitoring()
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard isEnabled else {
            RedEyeLogger.info("FSEvent monitoring is disabled by toggle.", category: FSEventMonitorManager.logCategory)
            return
        }
        guard streamRef == nil else {
            // Use .error as this indicates unexpected state / logic error
            RedEyeLogger.error("Attempted to start monitoring, but stream already exists.", category: FSEventMonitorManager.logCategory)
            return
        }
        guard !pathsToWatch.isEmpty else {
             // Use .error as monitoring cannot start
             RedEyeLogger.error("Attempted to start monitoring, but no paths are configured.", category: FSEventMonitorManager.logCategory)
             return
         }

        RedEyeLogger.info("Attempting to start FSEvent monitoring for paths: \(self.pathsToWatch)...", category: FSEventMonitorManager.logCategory)

        let fsevent_callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else {
                RedEyeLogger.error("FSEvents callback received nil context info.", category: FSEventMonitorManager.logCategory)
                return
            }
            let managerInstance = Unmanaged<FSEventMonitorManager>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            managerInstance.handleFSEvents(
                numEvents: numEvents,
                eventPaths: eventPaths,
                eventFlags: eventFlags,
                eventIds: eventIds
            )
        }

        // Define combined flags explicitly as FSEventStreamCreateFlags
        let streamFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        streamRef = FSEventStreamCreate(
            nil,
            fsevent_callback,
            &callbackContext,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latency (Double / CFTimeInterval)
            streamFlags // Pass the explicitly typed flags
        )

        if let stream = streamRef {
            // Schedule the stream on our dedicated dispatch queue
            FSEventStreamSetDispatchQueue(stream, self.dispatchQueue)

            // Start the stream
            if !FSEventStreamStart(stream) {
                RedEyeLogger.error("Failed to start FSEvent stream.", category: FSEventMonitorManager.logCategory)
                // Clean up if start fails
                FSEventStreamInvalidate(stream) // Invalidate before releasing
                FSEventStreamRelease(stream)
                streamRef = nil
            } else {
                RedEyeLogger.info("FSEvent stream started successfully on dispatch queue \(self.dispatchQueue.label).", category: FSEventMonitorManager.logCategory)
            }
        } else {
            RedEyeLogger.error("Failed to create FSEvent stream (FSEventStreamCreate returned nil).", category: FSEventMonitorManager.logCategory)
        }
    }

    func stopMonitoring() {
        guard let stream = streamRef else { return }
        RedEyeLogger.info("Stopping FSEvent monitoring...", category: FSEventMonitorManager.logCategory)

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream) // Invalidate to remove from dispatch queue
        FSEventStreamRelease(stream) // Release the stream object

        streamRef = nil
        // No runLoop to clear now
        RedEyeLogger.info("FSEvent monitoring stopped and stream released.", category: FSEventMonitorManager.logCategory)
    }

    private func handleFSEvents(numEvents: Int, eventPaths: UnsafeRawPointer, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIds: UnsafePointer<FSEventStreamEventId>) {
        // This method now executes on self.dispatchQueue

        guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else {
            RedEyeLogger.error("Could not cast eventPaths CFArray to [String].", category: FSEventMonitorManager.logCategory)
            return
        }

        RedEyeLogger.debug("Received \(numEvents) raw FSEvents.", category: FSEventMonitorManager.logCategory)

        for i in 0..<numEvents {
            let path = paths[i]
            let flags = eventFlags[i] // This is FSEventStreamEventFlags (UInt32)
            let eventId = eventIds[i]
            let flagsDict = interpretFSEventFlags(flags)

            // Log event details
            RedEyeLogger.info("""
                FS Event Detected:
                  ID: \(eventId)
                  Path: \(path)
                  Raw Flags: \(String(format: "0x%08X", flags))
                  Interpreted Flags: \(flagsDict)
                """, category: FSEventMonitorManager.logCategory)

            // --- Event Creation ---
            // This still requires RedEyeEventType.fileSystemEvent to be defined
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

            eventBus.publish(event: event)
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
             RedEyeLogger.debug("FSEvent received with flags \(String(format: "0x%08X", flags)) but no specific item flags matched.", category: FSEventMonitorManager.logCategory)
             interpretations["fs_note"] = "No specific item flags detected (might be dir change, volume event, or other)"
         } else if flags == 0 {
             interpretations["fs_note"] = "Flags were zero."
         }

        return interpretations
    }
}
