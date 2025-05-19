// RedEye/Managers/InputMonitorManager.swift

import AppKit

// Delegate protocol to notify when a potential selection-ending mouse up occurs
protocol InputMonitorManagerDelegate: AnyObject {
    func mouseUpAfterPotentialSelection(at screenPoint: NSPoint)
}

class InputMonitorManager: BaseMonitorManager {

    weak var delegate: InputMonitorManagerDelegate?

    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?

    // State to help distinguish clicks from drags
    private var isLeftMouseButtonDown: Bool = false
    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownTimestamp: TimeInterval?

    // Heuristics for distinguishing click from drag
    private let dragThresholdDistanceSquared: CGFloat = 25.0 // (5 pixels)^2, distance mouse must move to be considered a drag
    private let clickMaxDuration: TimeInterval = 0.3 // Max duration for a click (seconds)

    override var logCategory: String { "InputMonitorManager" }

    init(configManager: ConfigurationManaging) {
        super.init(monitorType: .inputMonitorManager, eventBus: nil, configManager: configManager)
        RedEyeLogger.info("InputMonitorManager specific initialization complete.", category: logCategory)
    }

    override func startMonitoring() -> Bool {
        guard mouseDownMonitor == nil, mouseUpMonitor == nil else {
            RedEyeLogger.info("Monitors are already active.", category: logCategory)
            return true
        }

        RedEyeLogger.info("Starting global mouse monitors.", category: logCategory)

        var success = true
        // Monitor for leftMouseDown events globally
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] (event: NSEvent) in
            guard let self = self else { return }
            // RedEyeLogger.debug("Global leftMouseDown detected.", category: "InputMonitorManager")
            self.isLeftMouseButtonDown = true
            self.mouseDownScreenPoint = NSEvent.mouseLocation // NSEvent.mouseLocation is already in screen coordinates
            self.mouseDownTimestamp = event.timestamp
        }
        if mouseDownMonitor == nil {
            RedEyeLogger.error("Failed to set up global leftMouseDown monitor.", category: self.logCategory)
            success = false
        }

        // Monitor for leftMouseUp events globally
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] (event: NSEvent) in
            guard let self = self else { return }
            // RedEyeLogger.debug("Global leftMouseUp detected.", category: "InputMonitorManager")

            if self.isLeftMouseButtonDown { // Only process if our monitored mouse down was active
                self.isLeftMouseButtonDown = false // Reset flag

                let upScreenPoint = NSEvent.mouseLocation
                let upTimestamp = event.timestamp

                guard let downPoint = self.mouseDownScreenPoint, let downTimestamp = self.mouseDownTimestamp else {
                    // Should not happen if isLeftMouseButtonDown was true
                    RedEyeLogger.error("Mouse up detected without prior mouse down info.", category: logCategory)
                    return
                }

                let deltaX = upScreenPoint.x - downPoint.x
                let deltaY = upScreenPoint.y - downPoint.y
                let distanceSquared = deltaX * deltaX + deltaY * deltaY
                let duration = upTimestamp - downTimestamp

                // Heuristic: Is it a click or a drag?
                // A click is short duration AND small distance.
                if duration < self.clickMaxDuration && distanceSquared < self.dragThresholdDistanceSquared {
//                    RedEyeLogger.debug("Likely a click detected. Duration: \(String(format: "%.3f", duration))s, DistanceSq: \(String(format: "%.1f", distanceSquared))", category: "InputMonitorManager")
                    // It's a click, so probably not a text selection drag. Do nothing for now.
                } else {
                    // It's likely a drag (or a click that held longer than clickMaxDuration)
                    RedEyeLogger.info("Potential selection drag finished (or long click). Duration: \(String(format: "%.3f", duration))s, DistanceSq: \(String(format: "%.1f", distanceSquared))", category: logCategory)
                    // Notify the delegate that a potential selection might have occurred
                    self.delegate?.mouseUpAfterPotentialSelection(at: upScreenPoint)
                }
                
                // Clear old points
                self.mouseDownScreenPoint = nil
                self.mouseDownTimestamp = nil
            }
        }
        if mouseUpMonitor == nil {
            RedEyeLogger.error("Failed to set up global leftMouseUp monitor.", category: self.logCategory)
            success = false
        }

        if mouseDownMonitor == nil || mouseUpMonitor == nil {
            RedEyeLogger.error("Failed to set up one or both global mouse monitors.", category: "InputMonitorManager")
            // Attempt to stop any that might have started to ensure clean state
            stopMonitoring()
        } else {
            RedEyeLogger.info("Global mouse monitors successfully started.", category: "InputMonitorManager")
        }
        if success {
            RedEyeLogger.info("Global mouse monitors successfully started.", category: self.logCategory)
            return true
        } else {
            RedEyeLogger.error("Failed to start one or both global mouse monitors. Cleaning up.", category: self.logCategory)
            // Clean up any monitor that might have started if the other failed
            if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor); mouseDownMonitor = nil }
            if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor); mouseUpMonitor = nil }
            return false
        }

    }

    override func stopMonitoring() {
        var didStop = false
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
            RedEyeLogger.info("Global leftMouseDown monitor stopped.", category: logCategory)
            didStop = true
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
            RedEyeLogger.info("Global leftMouseUp monitor stopped.", category: logCategory)
            didStop = true
        }
        
        if didStop {
            RedEyeLogger.info("InputMonitorManager mouse monitors stopped.", category: logCategory)
        } else {
            RedEyeLogger.debug("Attempted to stop InputMonitorManager, but no monitors were active.", category: logCategory)
        }
        
        // Clear state
        isLeftMouseButtonDown = false
        mouseDownScreenPoint = nil
        mouseDownTimestamp = nil
    }
}
