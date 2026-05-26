import XCTest
@testable import Zyquo

final class LayoutTests: XCTestCase {
    let engine = LayoutEngine()

    func testSingleFixedChild() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [LayoutConstraint(.fixed(30))]
        )
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].x, 0)
        XCTAssertEqual(regions[0].width, 30)
        XCTAssertEqual(regions[0].height, 50)
    }

    func testTwoFixedChildren() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [
                LayoutConstraint(.fixed(30)),
                LayoutConstraint(.fixed(40)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].x, 0)
        XCTAssertEqual(regions[0].width, 30)
        XCTAssertEqual(regions[1].x, 30)
        XCTAssertEqual(regions[1].width, 40)
    }

    func testGrowChild() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [
                LayoutConstraint(.fixed(20)),
                LayoutConstraint(.grow(1.0)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].width, 20)
        XCTAssertEqual(regions[1].width, 80)
        XCTAssertEqual(regions[1].x, 20)
    }

    func testTwoGrowChildren() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [
                LayoutConstraint(.grow(1.0)),
                LayoutConstraint(.grow(1.0)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].width, 50)
        XCTAssertEqual(regions[1].width, 50)
    }

    func testWeightedGrow() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [
                LayoutConstraint(.grow(1.0)),
                LayoutConstraint(.grow(3.0)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].width, 25)
        XCTAssertEqual(regions[1].width, 75)
    }

    func testColumnLayout() {
        let regions = engine.compute(
            direction: .column,
            available: Region(x: 0, y: 0, width: 80, height: 24),
            children: [
                LayoutConstraint(.fixed(3)),
                LayoutConstraint(.grow(1.0)),
                LayoutConstraint(.fixed(1)),
            ]
        )
        XCTAssertEqual(regions.count, 3)
        XCTAssertEqual(regions[0].y, 0)
        XCTAssertEqual(regions[0].height, 3)
        XCTAssertEqual(regions[0].width, 80)
        XCTAssertEqual(regions[1].y, 3)
        XCTAssertEqual(regions[1].height, 20)
        XCTAssertEqual(regions[2].y, 23)
        XCTAssertEqual(regions[2].height, 1)
    }

    func testLayoutWithOffset() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 10, y: 5, width: 60, height: 20),
            children: [
                LayoutConstraint(.fixed(20)),
                LayoutConstraint(.grow(1.0)),
            ]
        )
        XCTAssertEqual(regions[0].x, 10)
        XCTAssertEqual(regions[0].y, 5)
        XCTAssertEqual(regions[1].x, 30)
        XCTAssertEqual(regions[1].y, 5)
    }

    func testEmptyChildren() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: []
        )
        XCTAssertTrue(regions.isEmpty)
    }

    func testGrowWithMaxConstraint() {
        let regions = engine.compute(
            direction: .row,
            available: Region(x: 0, y: 0, width: 100, height: 50),
            children: [
                LayoutConstraint(.grow(1.0), max: 30),
                LayoutConstraint(.grow(1.0)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertLessThanOrEqual(regions[0].width, 30)
    }

    func testShrinkChild() {
        let regions = engine.compute(
            direction: .column,
            available: Region(x: 0, y: 0, width: 80, height: 24),
            children: [
                LayoutConstraint(.shrink(min: 3)),
                LayoutConstraint(.grow(1.0)),
            ]
        )
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].height, 3)
        XCTAssertEqual(regions[1].height, 21)
    }

    func testMixedFixedAndGrowColumn() {
        let regions = engine.compute(
            direction: .column,
            available: Region(x: 0, y: 0, width: 80, height: 30),
            children: [
                LayoutConstraint(.fixed(4)),
                LayoutConstraint(.fixed(3)),
                LayoutConstraint(.grow(1.0)),
                LayoutConstraint(.fixed(5)),
                LayoutConstraint(.fixed(1)),
            ]
        )
        XCTAssertEqual(regions.count, 5)
        XCTAssertEqual(regions[0].height, 4)
        XCTAssertEqual(regions[1].height, 3)
        XCTAssertEqual(regions[2].height, 17)
        XCTAssertEqual(regions[3].height, 5)
        XCTAssertEqual(regions[4].height, 1)

        XCTAssertEqual(regions[0].y, 0)
        XCTAssertEqual(regions[1].y, 4)
        XCTAssertEqual(regions[2].y, 7)
        XCTAssertEqual(regions[3].y, 24)
        XCTAssertEqual(regions[4].y, 29)
    }
}
