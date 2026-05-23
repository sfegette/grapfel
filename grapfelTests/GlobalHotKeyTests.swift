import Carbon
import XCTest

final class GlobalHotKeyTests: XCTestCase {
    func testDisplayStringUsesModifierGlyphs() {
        let hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        )

        XCTAssertEqual(hotKey.displayString, "⇧⌘Space")
    }

    func testStoredFallsBackToDefaultForInvalidValues() {
        let defaults = makeTestUserDefaults()
        defaults.set(0, forKey: UserDefaultsKey.globalHotKeyKeyCode)
        defaults.set(0, forKey: UserDefaultsKey.globalHotKeyModifiers)

        XCTAssertEqual(GlobalHotKey.stored(in: defaults), .default)
    }

    func testStoredReadsPersistedShortcut() {
        let defaults = makeTestUserDefaults()
        let savedHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )
        savedHotKey.persist(in: defaults)

        XCTAssertEqual(GlobalHotKey.stored(in: defaults), savedHotKey)
    }
}
