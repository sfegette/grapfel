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
    static weak var shared: AppDelegate?

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
    // Timestamp of when the panel was last shown. The outside-click monitor ignores events
    // within 0.25 s of this so that synthetic activation events from NSApp.activate() cannot
    // immediately close the panel (first-launch / background-app scenario).
    private var shownAt: Date = .distantPast
    // Set ONLY when the panel is dismissed because the user clicked the status-bar button
    // itself (not any other outside click). togglePopover checks this to avoid immediately
    // re-opening the panel via the button's mouse-up action after the monitor already hid it.
    private var hiddenByOutsideClickAt: Date = .distantPast
    private let hotKeyID = EventHotKeyID(signature: 0x4752504C /* GRPL */, id: 1)
    private var currentHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        UserDefaults.standard.register(defaults: [UserDefaultsKey.apfelPermissive: true])
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
        unregisterGlobalHotKey()
        // Known timing edge: if apfel crashes exactly at quit time, handleCrash (1 s sleep) +
        // start (500 ms + health) + killProcessOnPort (up to 3 s) ≈ 4.7 s > 4 s limit.
        // Probability is very low; if it fires, the OS reclaims apfel with no data loss.
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await ApfelServerManager.shared.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 4)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarIcon")
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
        installCarbonEventHandler()
        do {
            let storedHotKey = GlobalHotKey.stored()
            try activateGlobalHotKey(storedHotKey, persist: false)
            ServerState.shared.hotKeyRegistrationMessage = nil
        } catch {
            do {
                try activateGlobalHotKey(.default, persist: true)
                ServerState.shared.hotKeyRegistrationMessage = "The saved global shortcut was unavailable, so grapfel restored the default \(GlobalHotKey.default.displayString)."
            } catch {
                currentHotKey = nil
                hotKeyRef = nil
                ServerState.shared.hotKeyRegistrationMessage = "grapfel could not register a global shortcut. Open Settings to choose a different key combination."
            }
        }
    }

    private func installCarbonEventHandler() {
        guard carbonEventHandler == nil else { return }
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
    }

    func applyGlobalHotKey(_ hotKey: GlobalHotKey) throws {
        let previousHotKey = currentHotKey ?? GlobalHotKey.stored()
        if hotKey == previousHotKey {
            return
        }

        do {
            try activateGlobalHotKey(hotKey, persist: true)
            ServerState.shared.hotKeyRegistrationMessage = nil
        } catch {
            // activateGlobalHotKey only mutates currentHotKey on success, so the previous
            // hotkey registration is still active — no rollback step is needed.
            throw error
        }
    }

    private func activateGlobalHotKey(_ hotKey: GlobalHotKey, persist: Bool) throws {
        guard hotKey.carbonModifiers != 0 else {
            throw GlobalHotKeyError.missingModifier
        }
        guard !GlobalHotKey.isModifierKey(UInt16(hotKey.keyCode)) else {
            throw GlobalHotKeyError.modifierOnly
        }

        let newHotKeyRef = try registerGlobalHotKey(hotKey)
        let previousRef = hotKeyRef
        hotKeyRef = newHotKeyRef
        currentHotKey = hotKey

        if let previousRef, previousRef != newHotKeyRef {
            _ = UnregisterEventHotKey(previousRef)
        }

        if persist {
            hotKey.persist()
        }
    }

    private func registerGlobalHotKey(_ hotKey: GlobalHotKey) throws -> EventHotKeyRef {
        var registeredHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKeyRef
        )

        guard status == noErr, let registeredHotKeyRef else {
            if status == eventHotKeyExistsErr {
                throw GlobalHotKeyError.alreadyInUse
            }
            throw GlobalHotKeyError.registrationFailed(status)
        }
        return registeredHotKeyRef
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            _ = UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentHotKey = nil
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
        shownAt = Date()
        activateAppForPanelPresentation()

        // Dismiss when the user clicks outside the panel.  A global event monitor fires
        // before AppKit delivers the click to the target window, so this approach has no
        // first-launch timing race (unlike NSWindow.didResignKeyNotification).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            guard !self.panel.frame.contains(loc) else { return }
            // Ignore events within 0.25 s of showing — NSApp.activate() can route
            // synthetic activation clicks through the global monitor on first launch
            // and after returning from another app, which would immediately close the panel.
            guard Date().timeIntervalSince(self.shownAt) > 0.25 else { return }
            // Only suppress the next togglePopover call if this click landed on the
            // status-bar button. Any other outside click should not prevent the user
            // from immediately reopening the panel by clicking the button.
            let onStatusBar: Bool
            if let btn = self.statusItem.button, let win = btn.window {
                onStatusBar = win.convertToScreen(btn.convert(btn.bounds, to: nil)).contains(loc)
            } else {
                onStatusBar = false
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel.isVisible else { return }
                guard NSApp.modalWindow == nil else { return }
                if onStatusBar { self.hiddenByOutsideClickAt = Date() }
                self.hidePanel()
            }
        }
    }

    private func hidePanel() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func activateAppForPanelPresentation() {
        // LSUIElement release builds launched from Finder/open can leave the panel
        // non-interactive if this is simplified to plain NSApp.activate().
        NSApp.activate()
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
