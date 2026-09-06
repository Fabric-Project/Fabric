import CoreML
import Foundation
import Testing
import simd
@testable import Fabric

@Suite("SimCC Decoder")
struct SimCCDecoderTests
{
    @Test("Clean one-hot peak decodes to that bin with high confidence")
    func cleanPeakDecodesPrecisely()
    {
        let distribution: [Float] = [0, 0, 0, 0, 0, 10, 0, 0, 0, 0]
        let (position, confidence) = SimCCDecoder.decode(simccX: distribution, simccY: distribution, splitRatio: 2.0)

        #expect(abs(position.x - 2.5) < 0.01)
        #expect(abs(position.y - 2.5) < 0.01)
        #expect(confidence > 0.99)
    }

    @Test("Two equal peaks produce lower confidence than a clean single peak")
    func multiModalDistributionLowersConfidence()
    {
        var distribution = [Float](repeating: 0, count: 10)
        distribution[2] = 5
        distribution[7] = 5

        let (_, confidence) = SimCCDecoder.decode(simccX: distribution, simccY: distribution)

        #expect(confidence > 0)
        #expect(confidence < 0.6)
    }

    @Test("All-zero distribution decodes without crashing")
    func allZeroDistributionIsSafe()
    {
        let distribution: [Float] = [0, 0, 0, 0]
        let (position, confidence) = SimCCDecoder.decode(simccX: distribution, simccY: distribution)

        #expect(position.x == 0)
        #expect(position.y == 0)
        #expect(confidence > 0)
    }

    @Test("Empty distribution decodes to a safe default rather than crashing")
    func emptyDistributionIsSafe()
    {
        let (position, confidence) = SimCCDecoder.decode(simccX: [], simccY: [])

        #expect(position == simd_float2(0, 0))
        #expect(confidence == 0)
    }

    @Test("decodeAll unpacks a batch of per-keypoint distributions from MLMultiArray")
    func decodeAllUnpacksBatch() throws
    {
        let keypointCount = 3
        let binCount = 8

        let xArray = try MLMultiArray(shape: [NSNumber(value: keypointCount * binCount)], dataType: .float32)
        let yArray = try MLMultiArray(shape: [NSNumber(value: keypointCount * binCount)], dataType: .float32)

        for keypointIndex in 0..<keypointCount
        {
            for bin in 0..<binCount
            {
                xArray[keypointIndex * binCount + bin] = 0
                yArray[keypointIndex * binCount + bin] = 0
            }

            let peakBin = (keypointIndex + 1) * 2
            xArray[keypointIndex * binCount + peakBin] = 10
            yArray[keypointIndex * binCount + peakBin] = 10
        }

        let decoded = SimCCDecoder.decodeAll(simccX: xArray, simccY: yArray, keypointCount: keypointCount, splitRatio: 2.0)

        #expect(decoded.count == keypointCount)
        for (index, item) in decoded.enumerated()
        {
            let expectedBin = Float((index + 1) * 2)
            #expect(abs(item.position.x - expectedBin / 2.0) < 0.01)
            #expect(abs(item.position.y - expectedBin / 2.0) < 0.01)
            #expect(item.confidence > 0.9)
        }
    }

    @Test("decodeAll returns a safe default when tensor sizes don't divide evenly")
    func decodeAllHandlesMismatchedShape() throws
    {
        let malformedArray = try MLMultiArray(shape: [NSNumber(value: 7)], dataType: .float32)
        let decoded = SimCCDecoder.decodeAll(simccX: malformedArray, simccY: malformedArray, keypointCount: 3)

        #expect(decoded.count == 3)
        for item in decoded
        {
            #expect(item.confidence == 0)
        }
    }
}
