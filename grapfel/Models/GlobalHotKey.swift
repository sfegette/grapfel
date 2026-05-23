import AppKit
import Carbon
import Foundation

struct GlobalHotKey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = GlobalHotKey(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Function),
    ]

    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Escape): "Escape",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_Grave): "`",
    ]

    var isValid: Bool {
        carbonModifiers != 0 && !Self.modifierKeyCodes.contains(UInt16(keyCode))
    }

    var displayString: String {
        modifierGlyphs + keyDisplayName
    }

    var keyDisplayName: String {
        Self.keyNames[UInt16(keyCode)] ?? "Key \(keyCode)"
    }

    private var modifierGlyphs: String {
        var glyphs = ""
        if carbonModifiers & UInt32(controlKey) != 0 { glyphs += "^" }
        if carbonModifiers & UInt32(optionKey) != 0 { glyphs += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { glyphs += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { glyphs += "⌘" }
        return glyphs
    }

    static func stored(in defaults: UserDefaults = .standard) -> GlobalHotKey {
        let keyCode = (defaults.object(forKey: UserDefaultsKey.globalHotKeyKeyCode) as? NSNumber)?
            .uint32Value ?? UInt32(defaults.integer(forKey: UserDefaultsKey.globalHotKeyKeyCode))
        let modifiers = (defaults.object(forKey: UserDefaultsKey.globalHotKeyModifiers) as? NSNumber)?
            .uint32Value ?? UInt32(defaults.integer(forKey: UserDefaultsKey.globalHotKeyModifiers))
        let hotKey = GlobalHotKey(keyCode: keyCode, carbonModifiers: modifiers)
        return hotKey.isValid ? hotKey : .default
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: UserDefaultsKey.globalHotKeyKeyCode)
        defaults.set(Int(carbonModifiers), forKey: UserDefaultsKey.globalHotKeyModifiers)
    }

    static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> GlobalHotKey {
        GlobalHotKey(
            keyCode: UInt32(keyCode),
            carbonModifiers: modifiers.carbonHotKeyModifiers
        )
    }

    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }
}

extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}

enum GlobalHotKeyError: LocalizedError {
    case missingModifier
    case modifierOnly
    case alreadyInUse
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingModifier:
            return "Choose a shortcut with at least one modifier key."
        case .modifierOnly:
            return "Choose a non-modifier key for the shortcut."
        case .alreadyInUse:
            return "That shortcut is already in use by another hotkey."
        case .registrationFailed(let status):
            return "The shortcut could not be registered. Carbon returned \(status)."
        }
    }
}
