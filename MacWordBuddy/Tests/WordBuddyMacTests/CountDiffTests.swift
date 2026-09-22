import XCTest
@testable import WordBuddyMac

final class CountDiffTests: XCTestCase {
    func testSimpleInsert() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "abc", current: "abc你好"), 2)
    }

    func testInsertMiddle() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "ab", current: "a你b"), 1)
    }

    func testPureDelete() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "abc", current: "ab"), 0)
    }

    func testReplaceMarkedTextWithChinese() {
        // 组字：基线为空，marked "nihao" 被替换为 "你好"（Windows/AX 典型提交形态）
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "你好"), 2)
    }

    func testEnglishSession() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "hello ", current: "hello world"), 5)
    }

    func testWhitespaceNotCounted() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "a b c"), 3)
    }

    func testEmojiAsOne() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "👍👍"), 2)
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "👨‍👩‍👧"), 1)
    }

    func testSurrogatePair() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "𠮷"), 1)
    }

    func testFullWidthPunctuation() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "", current: "，。！"), 3)
    }

    func testNoChange() {
        XCTAssertEqual(CountDiff.countInserted(baseline: "abc", current: "abc"), 0)
    }

    func testShrinkThenGrow() {
        // 删除后重打：净增为 0 则不计
        XCTAssertEqual(CountDiff.countInserted(baseline: "abc", current: "abx"), 1)
    }
}
