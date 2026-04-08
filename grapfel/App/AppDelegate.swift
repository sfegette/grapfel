import AppKit
import SwiftUI

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var globalHotKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupGlobalHotKey()
        Task { try? await ApfelServerManager.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        Task { await ApfelServerManager.shared.stop() }
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

    // MARK: - Global hot key (⌘⇧Space — configurable in Phase 7 Settings)

    private func setupGlobalHotKey() {
        globalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // keyCode 49 = Space; require ⌘⇧, no other modifiers
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 49, flags == [.command, .shift] else { return }
            Task { @MainActor in self?.togglePopover(nil) }
        }
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
