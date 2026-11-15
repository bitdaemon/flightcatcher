import XCTest
import CoreGraphics
@testable import SimCore

final class TagPlacementTests: XCTestCase {
    private func item(_ name: String, _ x: CGFloat, _ y: CGFloat) -> TagItem {
        TagItem(callsign: name, symbol: CGPoint(x: x, y: y), size: TagPlacement.size(lines: [name, "250 090"]))
    }

    private func rects(_ items: [TagItem], _ offsets: [String: CGPoint]) -> [CGRect] {
        items.map { TagPlacement.rect(for: $0, offset: offsets[$0.callsign] ?? TagPlacement.defaultOffset) }
    }

    private func overlaps(_ rs: [CGRect]) -> Bool {
        for i in rs.indices { for j in rs.indices where j > i && rs[i].intersects(rs[j]) { return true } }
        return false
    }

    func testSizeGrowsWithTheLongestLineAndTheLineCount() {
        let small = TagPlacement.size(lines: ["EIN1", "250 090"])
        let wide = TagPlacement.size(lines: ["EIN12345", "250 090"])
        let tall = TagPlacement.size(lines: ["EIN1", "250 090", "ALT 5000"])
        XCTAssertGreaterThan(wide.width, small.width)
        XCTAssertGreaterThan(tall.height, small.height)
    }

    func testStackedAircraftGetNonOverlappingTags() {
        let items = (0..<4).map { item("AC\($0)", 200 + CGFloat($0) * 3, 200) }
        let placed = TagPlacement.place(items: items, offsets: [:], fixed: [], keepIfClear: false)
        XCTAssertEqual(placed.count, 4)
        XCTAssertFalse(overlaps(rects(items, placed)))
    }

    func testClearTagsStayWhereTheyAre() {
        let items = [item("A", 100, 100), item("B", 400, 300)]
        let offsets = ["A": CGPoint(x: 15, y: -30), "B": CGPoint(x: -80, y: 5)]
        let placed = TagPlacement.place(items: items, offsets: offsets, fixed: [], keepIfClear: true)
        XCTAssertEqual(placed, offsets)
    }

    func testManualTagsAreKeptAndOthersAvoidThem() {
        let items = [item("A", 100, 100), item("B", 100, 100)]
        let manual = ["A": TagPlacement.defaultOffset]
        let placed = TagPlacement.place(items: items, offsets: manual, fixed: ["A"], keepIfClear: true)
        XCTAssertNil(placed["A"])
        let all = manual.merging(placed) { a, _ in a }
        XCTAssertFalse(overlaps(rects(items, all)))
    }

    func testTagAvoidsOtherAircraftSymbols() {
        let a = item("A", 100, 100)
        let blocker = item("Z", 112, 90) // sits where A's default tag would be
        let placed = TagPlacement.place(items: [a, blocker], offsets: [:], fixed: [], keepIfClear: false)
        let box = TagPlacement.rect(for: a, offset: placed["A"]!)
        XCTAssertFalse(box.contains(blocker.symbol))
    }
}
