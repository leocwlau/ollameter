import AppKit
import XCTest
@testable import Ollameter

final class ApplicationPasteMenuTests: XCTestCase {
    func testEditMenuExposesCommandAndControlPaste() {
        let menu = ApplicationPasteMenu.makeEditMenu()

        XCTAssertEqual(menu.title, "Edit")
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["v", "v"])
        XCTAssertEqual(menu.items.map(\.keyEquivalentModifierMask), [.command, .control])
    }
}
