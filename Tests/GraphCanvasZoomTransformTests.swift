import Testing
import Foundation
@testable import Fabric

struct GraphCanvasZoomTransformTests
{
    private let limits: ClosedRange<CGFloat> = 0.25...2

    private func expectEqual(_ actual: CGPoint, _ expected: CGPoint,
                             sourceLocation: SourceLocation = #_sourceLocation)
    {
        #expect(abs(actual.x - expected.x) < 0.000001, sourceLocation: sourceLocation)
        #expect(abs(actual.y - expected.y) < 0.000001, sourceLocation: sourceLocation)
    }

    @Test func coordinateRoundTrip()
    {
        let transform = GraphCanvasZoomTransform(scale: 0.25,
                                                translation: CGSize(width: -1234, height: 5678))
        let canvasPosition = CGPoint(x: -20000, y: 30000)
        expectEqual(transform.canvasPosition(at: transform.position(forCanvasPosition: canvasPosition)),
                    canvasPosition)
    }

    @Test func successivePinchesPreserveTheirOwnAnchor()
    {
        var transform = GraphCanvasZoomTransform()
        let anchors = [CGPoint(x: 4700, y: 5200), CGPoint(x: 5500, y: 4800),
                       CGPoint(x: 1200, y: 8100)]

        for (anchor, magnification) in zip(anchors, [CGFloat(1.8), 0.3, 2.4])
        {
            let anchoredCanvasPosition = transform.canvasPosition(at: anchor)
            let unchanged = transform.magnified(by: 1, around: anchor, limits: limits)
            expectEqual(unchanged.position(forCanvasPosition: anchoredCanvasPosition), anchor)
            #expect(unchanged.scale == transform.scale)

            transform = transform.magnified(by: magnification, around: anchor, limits: limits)
            expectEqual(transform.position(forCanvasPosition: anchoredCanvasPosition), anchor)
        }
    }

    @Test func relativeMagnificationIsNotClampedIndependently()
    {
        let initial = GraphCanvasZoomTransform(scale: 0.25)
        let anchor = CGPoint(x: 6000, y: 4500)
        let result = initial.magnified(by: 3, around: anchor, limits: limits)

        #expect(result.scale == 0.75)
        expectEqual(result.position(forCanvasPosition: initial.canvasPosition(at: anchor)), anchor)
    }

    @Test func bothLimitsPreserveAnchorAndAllowReversal()
    {
        let initial = GraphCanvasZoomTransform(scale: 0.8,
                                              translation: CGSize(width: 2300, height: -700))
        let anchor = CGPoint(x: 5100, y: 3900)
        let anchoredCanvasPosition = initial.canvasPosition(at: anchor)

        for (magnification, expectedScale) in [(CGFloat(0.01), CGFloat(0.25)), (100, 2), (1.5, 1.2)]
        {
            // Each event uses the same gesture-start snapshot, including when
            // reversing back into range after overshooting a limit.
            let result = initial.magnified(by: magnification, around: anchor, limits: limits)
            #expect(abs(result.scale - expectedScale) < 0.000001)
            expectEqual(result.position(forCanvasPosition: anchoredCanvasPosition), anchor)
        }
    }

    @Test func zoomingOutAndBackAtSameAnchorRestoresTransform()
    {
        let initial = GraphCanvasZoomTransform(scale: 1.5,
                                              translation: CGSize(width: -1200, height: 800))
        let anchor = CGPoint(x: 4800, y: 5100)
        let zoomedOut = initial.magnified(by: 0.5, around: anchor, limits: limits)
        let restored = zoomedOut.magnified(by: 2, around: anchor, limits: limits)

        #expect(restored.scale == initial.scale)
        expectEqual(restored.position(forCanvasPosition: .zero),
                    initial.position(forCanvasPosition: .zero))
    }
}
