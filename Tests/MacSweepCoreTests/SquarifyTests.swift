import CoreGraphics
import Testing
@testable import MacSweepCore

@Suite struct SquarifyTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func emptyInputGivesNoRects() {
        #expect(Squarify.layout([], in: bounds).isEmpty)
    }

    @Test func zeroAndNegativeValuesGetZeroRects() {
        let rects = Squarify.layout([0, -5, 10], in: bounds)
        #expect(rects[0] == .zero)
        #expect(rects[1] == .zero)
        #expect(abs(rects[2].width * rects[2].height - 240_000) < 0.5)
    }

    @Test func allZeroValuesProduceZeroRects() {
        #expect(Squarify.layout([0, 0], in: bounds).allSatisfy { $0 == .zero })
    }

    @Test func degenerateRectProducesZeroRects() {
        #expect(Squarify.layout([1, 2], in: CGRect(x: 0, y: 0, width: 0, height: 100)).allSatisfy { $0 == .zero })
    }

    @Test(arguments: [
        [6.0, 6, 4, 3, 2, 2, 1],
        [100.0],
        [1.0, 1, 1, 1],
        [500.0, 1, 1, 1, 0.5],
        [3.0, 9, 1, 27, 4],
    ])
    func areasAreProportionalAndTilesStayInBounds(values: [Double]) {
        let rects = Squarify.layout(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = value / total * Double(bounds.width * bounds.height)
            #expect(abs(Double(rect.width * rect.height) - expected) < 1)
            #expect(rect.minX >= -0.01 && rect.minY >= -0.01)
            #expect(rect.maxX <= bounds.maxX + 0.01 && rect.maxY <= bounds.maxY + 0.01)
        }
    }

    @Test func tilesDoNotOverlap() {
        let rects = Squarify.layout([6, 6, 4, 3, 2, 2, 1], in: bounds)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].insetBy(dx: 0.01, dy: 0.01).intersection(rects[j].insetBy(dx: 0.01, dy: 0.01))
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func respectsRectOrigin() {
        let offset = CGRect(x: 50, y: 70, width: 100, height: 100)
        let rects = Squarify.layout([1, 1], in: offset)
        #expect(rects.allSatisfy { offset.insetBy(dx: -0.01, dy: -0.01).contains($0) })
    }
}
