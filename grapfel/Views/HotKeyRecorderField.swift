import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var hotKey: GlobalHotKey
    let onCapture: (GlobalHotKey) -> Void
    let onValidationMessage: (String?) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onCapture = onCapture
        view.onValidationMessage = onValidationMessage
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onValidationMessage = onValidationMessage
        nsView.hotKey = hotKey
    }
}

final class HotKeyRecorderNSView: NSView {
    var hotKey: GlobalHotKey = .default {
        didSet { updateAppearance() }
    }
    var onCapture: ((GlobalHotKey) -> Void)?
    var onValidationMessage: ((String?) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet { updateAppearance() }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        onValidationMessage?(nil)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        updateAppearance()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateAppearance()
        return true
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
        return true
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onValidationMessage?(nil)
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            onValidationMessage?(GlobalHotKeyError.missingModifier.errorDescription)
            return
        }

        guard !GlobalHotKey.isModifierKey(event.keyCode) else {
            NSSound.beep()
            onValidationMessage?(GlobalHotKeyError.modifierOnly.errorDescription)
            return
        }

        isRecording = false
        onValidationMessage?(nil)
        onCapture?(GlobalHotKey.from(keyCode: event.keyCode, modifiers: modifiers))
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isRecording ? NSColor.quaternaryLabelColor : NSColor.controlBackgroundColor).cgColor
        layer?.borderColor = (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        label.stringValue = isRecording ? "Type shortcut" : hotKey.displayString
        label.textColor = .labelColor
        toolTip = isRecording ? "Press a shortcut or Escape to cancel." : "Click to record a new shortcut."
    }
}
