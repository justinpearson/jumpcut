//
//  JumpcutTests.swift
//  JumpcutTests
//
//  Characterization tests for the domain core (Clipping, ClippingStack, and the
//  JCEngine persistence format). These pin *current* behavior — including a few
//  quirks, noted inline — so that the upcoming dependency-removal work has a
//  safety net. They touch no third-party library and never write to disk.
//

import XCTest
@testable import Jumpcut

// MARK: - Clipping: display shortening

final class ClippingTests: XCTestCase {

    func testShortStringIsUnchanged() {
        let c = Clipping(string: "hello world")
        XCTAssertEqual(c.fullText, "hello world")
        XCTAssertEqual(c.shortenedText, "hello world")
    }

    func testWhitespaceTrimmedForDisplayButFullTextPreserved() {
        let c = Clipping(string: "   padded \n")
        XCTAssertEqual(c.shortenedText, "padded")
        // fullText keeps the original, untrimmed value (it is what gets pasted).
        XCTAssertEqual(c.fullText, "   padded \n")
    }

    func testOnlyFirstLineUsedForDisplay() {
        let c = Clipping(string: "first line\nsecond line\nthird")
        XCTAssertEqual(c.shortenedText, "first line")
        XCTAssertEqual(c.fullText, "first line\nsecond line\nthird")
    }

    func testLongStringTruncatedToFortyPlusEllipsis() {
        let c = Clipping(string: String(repeating: "a", count: 50))
        XCTAssertTrue(c.shortenedText.hasSuffix("\u{2026}"))
        // 40 characters plus the single ellipsis character.
        XCTAssertEqual(c.shortenedText.count, 41)
        XCTAssertEqual(c.shortenedText, String(repeating: "a", count: 40) + "\u{2026}")
    }

    func testExactlyFortyCharactersNotTruncated() {
        let forty = String(repeating: "b", count: 40)
        let c = Clipping(string: forty)
        XCTAssertEqual(c.shortenedText, forty)
        XCTAssertFalse(c.shortenedText.hasSuffix("\u{2026}"))
    }
}

// MARK: - ClippingStack: the position cursor and stack operations

final class ClippingStackTests: XCTestCase {

    private let keys = [
        SettingsPath.skipSave.rawValue,
        SettingsPath.wraparoundBezel.rawValue,
        SettingsPath.rememberNum.rawValue
    ]
    private var saved: [String: Any] = [:]

    override func setUpWithError() throws {
        // Preserve any real values for the defaults this suite manipulates.
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
        }
        // skipSave = true guarantees ClippingStore never loads from or writes to
        // the real JCEngine.save plist during these tests.
        UserDefaults.standard.set(true, forKey: SettingsPath.skipSave.rawValue)
        UserDefaults.standard.removeObject(forKey: SettingsPath.wraparoundBezel.rawValue)
    }

    override func tearDownWithError() throws {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        saved = [:]
    }

    /// rememberNum is read in ClippingStack.init, so it must be set before construction.
    private func makeStack(remember: Int = 99, items: [String] = []) -> ClippingStack {
        UserDefaults.standard.set(remember, forKey: SettingsPath.rememberNum.rawValue)
        let stack = ClippingStack()
        for item in items { stack.add(item: item) }
        return stack
    }

    func testNewStackIsEmpty() {
        let stack = makeStack()
        XCTAssertTrue(stack.isEmpty())
        XCTAssertEqual(stack.count, 0)
        XCTAssertEqual(stack.position, 0)
        XCTAssertNil(stack.itemAt(position: 0))
    }

    func testAddInsertsNewestFirst() {
        let stack = makeStack(items: ["a", "b", "c"]) // added a, then b, then c
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.itemAt(position: 0)?.fullText, "c") // newest on top
        XCTAssertEqual(stack.itemAt(position: 1)?.fullText, "b")
        XCTAssertEqual(stack.itemAt(position: 2)?.fullText, "a")
    }

    func testMaxLengthTrimsOldest() {
        let stack = makeStack(remember: 10)
        for i in 0..<15 { stack.add(item: "item\(i)") }
        XCTAssertEqual(stack.count, 10)                          // capped at maxLength
        XCTAssertEqual(stack.itemAt(position: 0)?.fullText, "item14") // newest kept
        XCTAssertEqual(stack.itemAt(position: 9)?.fullText, "item5")  // item0...4 dropped
    }

    func testRememberNumIsFlooredAtTen() {
        let stack = makeStack(remember: 3) // below the hard floor of 10
        for i in 0..<20 { stack.add(item: "x\(i)") }
        XCTAssertEqual(stack.count, 10)
    }

    func testDownAndUpClampWithoutWraparound() {
        let stack = makeStack(items: ["a", "b", "c"]) // positions 0...2
        XCTAssertEqual(stack.position, 0)
        stack.down(); XCTAssertEqual(stack.position, 1)
        stack.down(); XCTAssertEqual(stack.position, 2)
        stack.down(); XCTAssertEqual(stack.position, 2) // clamps at the bottom
        stack.up();   XCTAssertEqual(stack.position, 1)
        stack.up();   XCTAssertEqual(stack.position, 0)
        stack.up();   XCTAssertEqual(stack.position, 0) // clamps at the top
    }

    func testDownAndUpWrapWhenEnabled() {
        UserDefaults.standard.set(true, forKey: SettingsPath.wraparoundBezel.rawValue)
        let stack = makeStack(items: ["a", "b", "c"])
        stack.position = 2
        stack.down(); XCTAssertEqual(stack.position, 0) // wraps to top
        stack.up();   XCTAssertEqual(stack.position, 2) // wraps to bottom
    }

    func testMoveClampsAndIgnoresEmptyStack() {
        let empty = makeStack()
        empty.move(steps: 5)
        XCTAssertEqual(empty.position, 0) // no-op, no crash

        let stack = makeStack(items: ["a", "b", "c", "d"]) // 0...3
        stack.move(steps: 10);  XCTAssertEqual(stack.position, 3) // clamp high
        stack.move(steps: -10); XCTAssertEqual(stack.position, 0) // clamp low
        stack.move(steps: 2);   XCTAssertEqual(stack.position, 2)
    }

    func testDeleteAtOrAboveCursorDecrementsCursor() {
        let stack = makeStack(items: ["a", "b", "c", "d"]) // top->bottom: d,c,b,a
        stack.position = 2 // pointing at "b"
        stack.deleteAt(position: 1) // removes "c"
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.position, 1) // cursor follows, still on "b"
        XCTAssertEqual(stack.itemAt(position: stack.position)?.fullText, "b")
        XCTAssertEqual(stack.itemAt(position: 0)?.fullText, "d")
        XCTAssertEqual(stack.itemAt(position: 2)?.fullText, "a")
    }

    func testDeleteBelowCursorLeavesCursor() {
        let stack = makeStack(items: ["a", "b", "c", "d"]) // d,c,b,a
        stack.position = 1 // "c"
        stack.deleteAt(position: 3) // removes "a" (deeper in the stack)
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.position, 1) // unchanged
        XCTAssertEqual(stack.itemAt(position: 1)?.fullText, "c")
    }

    func testDeleteOnlyItemResetsCursor() {
        let stack = makeStack(items: ["only"])
        stack.delete() // deletes at the current position (0)
        XCTAssertTrue(stack.isEmpty())
        XCTAssertEqual(stack.position, 0)
    }

    func testMoveItemToTopReordersAndPositionZeroIsNoop() {
        let stack = makeStack(items: ["a", "b", "c"]) // idx 0,1,2 = c,b,a
        stack.moveItemToTop(position: 2) // move "a" to the top
        XCTAssertEqual(stack.itemAt(position: 0)?.fullText, "a")
        XCTAssertEqual(stack.itemAt(position: 1)?.fullText, "c")
        XCTAssertEqual(stack.itemAt(position: 2)?.fullText, "b")
        stack.moveItemToTop(position: 0) // already on top: no-op
        XCTAssertEqual(stack.itemAt(position: 0)?.fullText, "a")
    }

    func testClearEmptiesStackButLeavesCursorStale() {
        let stack = makeStack(items: ["a", "b"])
        stack.position = 1
        stack.clear()
        XCTAssertTrue(stack.isEmpty())
        XCTAssertEqual(stack.count, 0)
        // CHARACTERIZATION: clear() empties the store but does NOT reset the
        // cursor. The stale position is currently masked because itemAt/display
        // guard on isEmpty. Pinned so a future "fix" is a conscious decision.
        XCTAssertEqual(stack.position, 1)
    }

    func testFirstItemsReturnsNewestSlice() {
        let stack = makeStack(items: ["a", "b", "c", "d", "e"]) // e,d,c,b,a
        XCTAssertEqual(Array(stack.firstItems(n: 2)).map { $0.fullText }, ["e", "d"])
        // n greater than count returns the whole stack.
        XCTAssertEqual(Array(stack.firstItems(n: 99)).map { $0.fullText }, ["e", "d", "c", "b", "a"])
    }
}

// MARK: - JCEngine: the on-disk persistence format

final class JCEnginePersistenceTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let items = [
            JCListItem(Contents: "first", Position: 0, Type: "NSStringPboardType"),
            JCListItem(Contents: "second\nline", Position: 1, Type: "NSStringPboardType")
        ]
        let engine = JCEngine(displayLen: nil, displayNum: 10, jcList: items, rememberNum: 99, version: "0.84")

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(engine)
        let decoded = try PropertyListDecoder().decode(JCEngine.self, from: data)

        XCTAssertEqual(decoded.jcList.count, 2)
        XCTAssertEqual(decoded.jcList[0].Contents, "first")
        XCTAssertEqual(decoded.jcList[1].Contents, "second\nline")
        XCTAssertEqual(decoded.jcList[1].Position, 1)
        XCTAssertEqual(decoded.version, "0.84")
    }

    func testDecodesLegacyOnDiskFormat() throws {
        // Pins the inherited Objective-C plist schema: capitalized keys
        // (Contents/Position/Type) and an optional displayLen that is absent on
        // disk. Any future storage migration must keep decoding this shape.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>displayNum</key><integer>10</integer>
            <key>jcList</key>
            <array>
                <dict>
                    <key>Contents</key><string>hello</string>
                    <key>Position</key><integer>0</integer>
                    <key>Type</key><string>NSStringPboardType</string>
                </dict>
            </array>
            <key>rememberNum</key><integer>99</integer>
            <key>version</key><string>0.83</string>
        </dict>
        </plist>
        """
        let decoded = try PropertyListDecoder().decode(JCEngine.self, from: Data(xml.utf8))

        XCTAssertNil(decoded.displayLen) // optional, absent on disk
        XCTAssertEqual(decoded.jcList.count, 1)
        XCTAssertEqual(decoded.jcList[0].Contents, "hello")
        XCTAssertEqual(decoded.jcList[0].Type, "NSStringPboardType")
        XCTAssertEqual(decoded.version, "0.83")
    }
}
