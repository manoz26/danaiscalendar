import Foundation
import Testing
@testable import PlannerCore

/// The order of the iPhone's typed lists (prompt 8): as she arranged them, the ticked ones
/// below, and a move that changes only the moved item.
@Suite("Typed lists on the iPhone")
struct TypedListOrderTests {
    private static let start = Date(timeIntervalSince1970: 1_850_000_000)

    private func item(_ text: String, order: Int, done: Bool = false, position: Double? = nil) -> ListItem {
        ListItem(
            text: text, done: done, line: order,
            created: Self.start.addingTimeInterval(TimeInterval(order)), position: position
        )
    }

    @Test func itemsNeverMovedAreInTheOrderTheyWereAdded() {
        let items = [item("Bread", order: 2), item("Milk", order: 1), item("Eggs", order: 3)]
        #expect(TypedLists.arranged(items).map(\.text) == ["Milk", "Bread", "Eggs"])
    }

    @Test func tickedItemsFallBelowTheOpenOnes() {
        let items = [item("Milk", order: 1, done: true), item("Bread", order: 2), item("Eggs", order: 3, done: true), item("Soap", order: 4)]
        let shown = TypedLists.openThenTicked(items)
        #expect(shown.open.map(\.text) == ["Bread", "Soap"])
        #expect(shown.ticked.map(\.text) == ["Milk", "Eggs"])
    }

    @Test(arguments: [0, 1, 2, 3])
    func aMovedItemLandsWhereItWasDropped(index: Int) {
        let others = [item("Milk", order: 1), item("Bread", order: 2), item("Eggs", order: 3)]
        var moved = item("Soap", order: 4)
        moved.position = TypedLists.position(at: index, among: others)
        var expected = others.map(\.text)
        expected.insert("Soap", at: index)
        #expect(TypedLists.arranged(others + [moved]).map(\.text) == expected)
    }

    @Test func movingAgainAndAgainBetweenTheSameTwoKeepsTheOrder() {
        var list = [item("Milk", order: 1), item("Bread", order: 2), item("Eggs", order: 3)]
        // Eggs and Bread swap places twenty times: each move changes only the moved item.
        for round in 0..<20 {
            let ordered = TypedLists.arranged(list)
            let moving = ordered[2]
            let others = ordered.filter { $0.id != moving.id }
            let index = list.firstIndex { $0.id == moving.id }!
            list[index].position = TypedLists.position(at: 1, among: others)
            let after = TypedLists.arranged(list).map(\.text)
            #expect(after.first == "Milk", "round \(round)")
            #expect(after[1] == moving.text, "round \(round)")
        }
    }

    @Test func anEmptyListAndTheEndsHavePositions() {
        #expect(TypedLists.position(at: 0, among: []) == 0)
        let others = [item("Milk", order: 1), item("Bread", order: 2)]
        #expect(TypedLists.position(at: 0, among: others) < others[0].orderKey)
        #expect(TypedLists.position(at: 2, among: others) > others[1].orderKey)
        // Out of range: clamped to the ends.
        #expect(TypedLists.position(at: 9, among: others) > others[1].orderKey)
        #expect(TypedLists.position(at: -3, among: others) < others[0].orderKey)
    }

    @Test func aPositionSurvivesTheListFileAndOldFilesHaveNone() throws {
        var moved = item("Soap", order: 4)
        moved.position = 12.5
        let file = ListFile(items: [item("Milk", order: 1), moved])
        let data = try JSONFileStore<ListFile>.encode(file)
        let decoded = try JSONFileStore<ListFile>.decode(data)
        #expect(decoded.items.map(\.position) == [nil, 12.5])
        // An item never moved writes no position at all (files of older versions look the same).
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.components(separatedBy: "\"position\"").count == 2)
    }

    @Test func aMoveOnOneDeviceReachesTheOtherAsAChangeOfThatItem() {
        let milk = item("Milk", order: 1)
        let bread = item("Bread", order: 2)
        var movedBread = bread
        movedBread.position = TypedLists.position(at: 0, among: [milk])
        movedBread.modified = Self.start.addingTimeInterval(100)
        let merged = ListFile.merged(ListFile(items: [milk, bread]), ListFile(items: [milk, movedBread]), now: Self.start.addingTimeInterval(200))
        #expect(TypedLists.arranged(merged.items).map(\.text) == ["Bread", "Milk"])
        // The printed lines did not change.
        #expect(merged.items.first { $0.text == "Bread" }?.line == 2)
    }
}
