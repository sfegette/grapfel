import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // TODO: Phase 2 — stop apfel server process here
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Use SF Symbol as placeholder until Affinity Designer icon is ready
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "grapfel")
            button.image?.isTemplate = true  // adapts to light/dark menubar
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = CGSize(width: 420, height: 580)
        popover.behavior = .transient  // auto-dismiss on click-away
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView())
    }

    // MARK: - Actions

    @objc func togglePopover(_ sender: AnyObject? = nil) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
