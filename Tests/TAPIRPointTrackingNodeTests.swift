import simd
import Testing
@testable import Fabric

@Suite("TAPIR point tracking")
struct TAPIRPointTrackingNodeTests
{
    @Test("Fabric unit coordinates round-trip through TAPIR raster space")
    func coordinateRoundTrip()
    {
        let aspect: Float = 9 / 16
        let points: [simd_float2] = [
            simd_float2(-0.75, -0.4),
            simd_float2(0, 0),
            simd_float2(0.625, 0.3),
        ]
        for point in points
        {
            let raster = TAPIRPointTrackingNode.rasterPoint(from: point, aspect: aspect)
            let roundTrip = TAPIRPointTrackingNode.unitPoint(from: raster, aspect: aspect)
            #expect(abs(roundTrip.x - point.x) < 1e-6)
            #expect(abs(roundTrip.y - point.y) < 1e-6)
        }
    }

    @Test("Query points are padded without changing active points")
    func fixedCapacityPadding()
    {
        let input: ContiguousArray<simd_float2> = [simd_float2(-0.5, 0.25), simd_float2(0.5, -0.25)]
        let padded = TAPIRPointTrackingNode.paddedRasterPoints(from: input, aspect: 1, capacity: 4)
        #expect(padded.count == 4)
        #expect(padded[0] == simd_float2(64, 96))
        #expect(padded[1] == simd_float2(192, 160))
        #expect(padded[2] == padded[1])
        #expect(padded[3] == padded[1])
    }
}
