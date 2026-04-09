import AppKit
import Carbon
import SwiftUI

// Borderless NSPanel returns canBecomeKey=false by default — override so text input works.
private final class GrapfelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: GrapfelPanel!
    private var hotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        setupGlobalHotKey()
        Task { try? await ApfelServerManager.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let handler = carbonEventHandler { RemoveEventHandler(handler) }
        if let hotKey = hotKeyRef { UnregisterEventHotKey(hotKey) }
        Task { await ApfelServerManager.shared.stop() }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "grapfel")
            button.image?.isTemplate = true
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    private func setupPanel() {
        panel = GrapfelPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // NSHostingView must be the direct contentView so SwiftUI's responder chain works
        let hv = NSHostingView(rootView: ContentView())
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hv
    }

    // MARK: - Global hot key (⌘⇧Space — configurable in Phase 7 Settings)
    // Uses Carbon RegisterEventHotKey — no Input Monitoring permission required.

    private func setupGlobalHotKey() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.togglePopover(nil) }
                return noErr
            },
            1, &eventSpec, selfPtr, &carbonEventHandler
        )
        let hotKeyID = EventHotKeyID(signature: 0x4752504C /* GRPL */, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Actions

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Grapfel", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func togglePopover(_ sender: AnyObject? = nil) {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let origin: NSPoint
        if let button = statusItem.button, let buttonWindow = button.window {
            // Normal path: position flush below the status item
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            origin = NSPoint(x: screenRect.midX - 210, y: screenRect.minY - 580)
        } else if let screen = NSScreen.main {
            // Fallback for first-launch timing: top-right of main screen (menu bar area)
            origin = NSPoint(x: screen.frame.maxX - 440, y: screen.frame.maxY - 606)
        } else {
            return
        }
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Dismiss when the panel loses key focus (user clicked elsewhere)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    private func hidePanel() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        panel.orderOut(nil)
    }

    @objc private func panelDidResignKey() {
        hidePanel()
    }
}
