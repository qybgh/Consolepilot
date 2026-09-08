import XCTest

@testable import ConsolepilotCore

@MainActor
final class HotkeyTests: XCTestCase {
    func testEmptyToggleHotkeyDoesNotRegister() {
        let registry = HotkeyRegistry()
        if let spec = HotkeySpec("") { _ = registry.register(name: "toggle", spec: spec) {} }
        XCTAssertTrue(registry.registeredNames.isEmpty)
    }

    func testHotkeySpecRejectsUnknownModifierAndRequiresModifier() {
        XCTAssertNil(HotkeySpec("cmdx+a"))
        XCTAssertNil(HotkeySpec("a"))
        XCTAssertEqual(HotkeySpec("cmd+shift+s")?.key, "s")
        XCTAssertEqual(HotkeySpec("cmd+c*2")?.pressCount, 2)
        XCTAssertNil(HotkeySpec("cmd+c*3"))
    }

    func testReplaceAllUnregistersOldNamesBeforeRegisteringNew() {
        let registry = HotkeyRegistry()
        _ = registry.register(name: "old", spec: HotkeySpec("cmd+o")!) {}
        registry.replaceAll(["new": (HotkeySpec("cmd+n")!, { @MainActor in })])
        XCTAssertEqual(registry.registeredNames, ["new"])
        registry.replaceAll(["new": (HotkeySpec("cmd+n")!, { @MainActor in })])
        registry.trigger(name: "old")
        registry.trigger(name: "new")
        XCTAssertEqual(registry.registeredNames, ["new"])
    }

    func testRemoveAllClearsRegistrations() {
        let registry = HotkeyRegistry()
        _ = registry.register(name: "one", spec: HotkeySpec("cmd+1")!) {}
        _ = registry.register(name: "two", spec: HotkeySpec("ctrl+2")!) {}
        registry.removeAll()
        XCTAssertTrue(registry.registeredNames.isEmpty)
    }

    func testDoublePressHotkeyFiresOnlyAfterSecondPress() {
        let registry = HotkeyRegistry()
        var fireCount = 0
        _ = registry.register(name: "double", spec: HotkeySpec("cmd+c*2")!) { fireCount += 1 }
        registry.trigger(name: "double")
        XCTAssertEqual(fireCount, 0)
        registry.trigger(name: "double")
        XCTAssertEqual(fireCount, 1)
    }

    func testDoublePressSpecUsesCarbonModeWithoutChangingSinglePressParsing() {
        let double = HotkeySpec("cmd+c*2")
        XCTAssertEqual(double?.key, "c")
        XCTAssertEqual(double?.modifiers, ["cmd"])
        XCTAssertEqual(double?.pressCount, 2)
        XCTAssertEqual(HotkeySpec("cmd+c")?.pressCount, 1)
    }
}
