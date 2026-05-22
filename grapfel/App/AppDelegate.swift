import AppKit
import Carbon
import Sparkle
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
    private var updaterController: SPUStandardUpdaterController!
    // Global mouse-down monitor used to dismiss the panel when the user clicks outside it.
    // Replaces the old NSWindow.didResignKeyNotification approach, which had a first-launch
    // timing race: on the very first activation of a LSUIElement background process, the
    // focus-handoff events arrive well after the 300 ms guard expired, so the panel would
    // immediately hide. A global event monitor fires before AppKit delivers the event, so
    // there is no timing dependency at all.
    private var outsideClickMonitor: Any?
    // Set when the panel is dismissed by an outside click so togglePopover can detect that
    // the click also landed on the status-bar button and avoid immediately re-opening.
    private var hiddenByOutsideClickAt: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        setupStatusItem()
        setupPanel()
        setupGlobalHotKey()
        Task { await ServerState.shared.retry() }
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
        // Panel is always 621 pt wide. The left 201 pt are transparent (sidebar space);
        // the right 420 pt are the visible chat area. The panel never resizes.
        panel = GrapfelPanel(
            contentRect: NSRect(x: 0, y: 0, width: 621, height: 580),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // sizingOptions = [] prevents the hosting view from auto-resizing the panel.
        let hv = NSHostingView(rootView: ContentView())
        hv.sizingOptions = []
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hv
    }

    // MARK: - Global hot key (⌘⇧Space)
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
            // Defer past the current event so NSApp.activate() in showPanel() fires after
            // AppKit has finished processing the click. Without this, the activation
            // focus-handoff event lands in the outside-click monitor and immediately hides
            // the panel (same mechanism the hotkey path avoids via Task { @MainActor in }).
            DispatchQueue.main.async { [weak self] in self?.togglePopover(nil) }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)
        menu.addItem(NSMenuItem.separator())
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
            guard Date().timeIntervalSince(hiddenByOutsideClickAt) > 0.15 else { return }
            showPanel()
        }
    }

    private func showPanel() {
        removeOutsideClickMonitor()

        // The chat area occupies the right 420 pt of the 621-pt panel.
        // Position so the chat area appears centered below the status bar icon,
        // exactly where the old 420-pt panel used to be.
        let panelWidth = panel.frame.width          // 621
        let chatWidth: CGFloat = 420
        let sidebarSpace = panelWidth - chatWidth   // 201
        let origin: NSPoint
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            origin = NSPoint(x: screenRect.midX - chatWidth / 2 - sidebarSpace, y: screenRect.minY - 580)
        } else if let screen = NSScreen.main {
            // Fallback when the status-item window is not yet available.
            origin = NSPoint(x: screen.frame.maxX - chatWidth - sidebarSpace - 20, y: screen.frame.maxY - 606)
        } else {
            return
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Dismiss when the user clicks outside the panel.  A global event monitor fires
        // before AppKit delivers the click to the target window, so this approach has no
        // first-launch timing race (unlike NSWindow.didResignKeyNotification).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            // Async dispatch so this runs after the current event is fully processed.
            // The isVisible guard prevents a double-hide if the button handler already
            // called hidePanel() synchronously for the same click.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.hiddenByOutsideClickAt = Date()
                self.hidePanel()
            }
        }
    }

    private func hidePanel() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
