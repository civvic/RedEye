//
//  PluginActionsViewController.swift
//  RedEye
//
//  Created by Vicente Sosa on 5/10/25.
//

import Cocoa

// Delegate protocol for actions triggered from the view controller
protocol PluginActionsViewControllerDelegate: AnyObject {
    func didClickPluginActionButton(sender: NSButton, contextText: String?)
    // We might add more actions here later, e.g., if there are multiple buttons
}

class PluginActionsViewController: NSViewController {

    // Delegate to inform about actions
    weak var delegate: PluginActionsViewControllerDelegate?
    
    // Store the context text that this panel is currently for
    var currentContextText: String?

    // A simple button for our echo plugin
    private var echoButton: NSButton!

    // MARK: - View Lifecycle

    override func loadView() {
        // Create a custom root view for this view controller.
        // This view will be the content view of the PluginActionsPanel.
        // We'll give it a slight background and rounded corners.
        let contentView = NSView()
        contentView.wantsLayer = true // Important for background color, borders, shadows on the view itself
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        contentView.layer?.cornerRadius = 6.0
        contentView.layer?.borderColor = NSColor.gray.withAlphaComponent(0.3).cgColor
        contentView.layer?.borderWidth = 0.5
        
        // Set the frame. The actual size will be determined by the panel when it's created.
        // This is just an initial frame for the view itself.
        // Let's make it wide enough for one or two buttons.
        contentView.frame = NSRect(x: 0, y: 0, width: 100, height: 30) // Initial small size
        
        self.view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupButtons()
    }

    // MARK: - Setup

    private func setupButtons() {
        echoButton = NSButton(title: "Run Echo", target: self, action: #selector(echoButtonAction(_:)))
        echoButton.bezelStyle = .regularSquare // Or other styles like .texturedSquare
        echoButton.translatesAutoresizingMaskIntoConstraints = false // We'll use Auto Layout

        self.view.addSubview(echoButton)

        // Basic Auto Layout constraints for the button to center it.
        // For multiple buttons, we'd use an NSStackView or more complex layout.
        NSLayoutConstraint.activate([
            echoButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            echoButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            echoButton.heightAnchor.constraint(equalToConstant: 22) // Give it a bit of height
            // Width will be intrinsic or you can set it.
        ])
    }

    // MARK: - Actions

    @objc private func echoButtonAction(_ sender: NSButton) {
        print("PluginActionsViewController: Echo button clicked.")
        delegate?.didClickPluginActionButton(sender: sender, contextText: currentContextText)
    }
    
    // Public method to update context if needed, though it might be set once on show
    public func setContext(text: String?) {
        self.currentContextText = text
    }
}
