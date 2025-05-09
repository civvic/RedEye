//
//  main.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/8/25.
//

import AppKit // Or import Cocoa

// Create an instance of your AppDelegate
let delegate = AppDelegate()

// Get the shared NSApplication instance
let application = NSApplication.shared

// Assign your AppDelegate instance as the delegate of the application
application.delegate = delegate

// Run the application's main event loop.
// This function does not return until the application terminates.
// It also calls applicationDidFinishLaunching on the delegate.
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
