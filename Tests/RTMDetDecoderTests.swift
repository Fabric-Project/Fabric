import CoreGraphics
import CoreML
import Foundation
import Testing
@testable import Fabric

@Suite("RTMDet Decoder")
struct RTMDetDecoderTests
{
    private let gridSize = 4
    private let stride = 16
    private var inputSize: CGSize { CGSize(width: gridSize * stride, height: gridSize * stride) }

    private func makeLevelTensors(scoredCells: [(row: Int, column: Int, score: Float, distance: Float)]) throws -> (scores: MLMultiArray, boxDistances: MLMultiArray)
    {
        let planeSize = gridSize * gridSize
        let scores = try MLMultiArray(shape: [1, 1, NSNumber(value: gridSize), NSNumber(value: gridSize)], dataType: .float32)
        let boxDistances = try MLMultiArray(shape: [1, 4, NSNumber(value: gridSize), NSNumber(value: gridSize)], dataType: .float32)

        for index in 0..<planeSize { scores[index] = 0 }
        for index in 0..<(planeSize * 4) { boxDistances[index] = 0 }

        for cell in scoredCells
        {
            let planeIndex = cell.row * gridSize + cell.column
            scores[planeIndex] = NSNumber(value: cell.score)
            for channel in 0..<4
            {
                boxDistances[channel * planeSize + planeIndex] = NSNumber(value: cell.distance)
            }
        }

        return (scores, boxDistances)
    }

    @Test("A single high-confidence cell decodes to the expected normalized rect")
    func singleDetectionDecodesExpectedRect() throws
    {
        let (scores, boxDistances) = try makeLevelTensors(scoredCells: [(row: 1, column: 1, score: 0.9, distance: 1.0)])

        let detections = RTMDetDecoder.decode(
            perLevelScores: [scores],
            perLevelBoxDistances: [boxDistances],
            strides: [stride],
            inputSize: inputSize,
            scoreThreshold: 0.4,
            iouThreshold: 0.5,
            maxDetections: 16
        )

        #expect(detections.count == 1)
        let rect = try #require(detections.first).rect
        #expect(abs(rect.origin.x - 0.125) < 0.01)
        #expect(abs(rect.origin.y - 0.375) < 0.01)
        #expect(abs(rect.width - 0.5) < 0.01)
        #expect(abs(rect.height - 0.5) < 0.01)
    }

    @Test("Cells below the score threshold are discarded")
    func lowScoreCellsAreDiscarded() throws
    {
        let (scores, boxDistances) = try makeLevelTensors(scoredCells: [(row: 0, column: 0, score: 0.1, distance: 1.0)])

        let detections = RTMDetDecoder.decode(
            perLevelScores: [scores],
            perLevelBoxDistances: [boxDistances],
            strides: [stride],
            inputSize: inputSize,
            scoreThreshold: 0.4
        )

        #expect(detections.isEmpty)
    }

    @Test("NMS suppresses a lower-confidence overlapping box, and threshold controls how aggressively")
    func nmsSuppressesOverlappingBoxes() throws
    {
        let (scores, boxDistances) = try makeLevelTensors(scoredCells: [
            (row: 1, column: 1, score: 0.9, distance: 1.0),
            (row: 1, column: 2, score: 0.8, distance: 1.0),
        ])

        // These two boxes overlap with IoU ≈ 0.33 (computed from the fixture
        // geometry: two 32x32-unit boxes on the same row, 16 units apart).
        let looseNMS = RTMDetDecoder.decode(
            perLevelScores: [scores], perLevelBoxDistances: [boxDistances],
            strides: [stride], inputSize: inputSize,
            scoreThreshold: 0.4, iouThreshold: 0.9, maxDetections: 16
        )
        #expect(looseNMS.count == 2)

        let strictNMS = RTMDetDecoder.decode(
            perLevelScores: [scores], perLevelBoxDistances: [boxDistances],
            strides: [stride], inputSize: inputSize,
            scoreThreshold: 0.4, iouThreshold: 0.3, maxDetections: 16
        )
        #expect(strictNMS.count == 1)
        #expect(strictNMS.first?.confidence == 0.9)
    }

    @Test("maxDetections caps the number of returned boxes")
    func maxDetectionsCapsResults() throws
    {
        let (scores, boxDistances) = try makeLevelTensors(scoredCells: [
            (row: 0, column: 0, score: 0.9, distance: 1.0),
            (row: 3, column: 3, score: 0.8, distance: 1.0),
        ])

        let detections = RTMDetDecoder.decode(
            perLevelScores: [scores], perLevelBoxDistances: [boxDistances],
            strides: [stride], inputSize: inputSize,
            scoreThreshold: 0.4, iouThreshold: 0.5, maxDetections: 1
        )

        #expect(detections.count == 1)
        #expect(detections.first?.confidence == 0.9)
    }

    @Test("Mismatched level counts return no detections rather than crashing")
    func mismatchedLevelCountsAreSafe() throws
    {
        let (scores, boxDistances) = try makeLevelTensors(scoredCells: [(row: 0, column: 0, score: 0.9, distance: 1.0)])

        let detections = RTMDetDecoder.decode(
            perLevelScores: [scores, scores],
            perLevelBoxDistances: [boxDistances],
            strides: [stride],
            inputSize: inputSize
        )

        #expect(detections.isEmpty)
    }
}
