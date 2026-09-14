import Metal
import Testing
import Satin
@testable import Fabric

/// Exercises the real Metal kernel behind JointBilateralFilterNode (not the
/// Node wrapper -- same pattern as RTMPoseInputPreprocessorTests) against a
/// hand-derivable 3x3 neighborhood, comparing GPU output to an independently
/// written CPU reference of the same formula (Gaussian spatial weight x
/// Gaussian range weight on guide luma, normalized). This is the check that
/// would catch a wrong exponent sign, a swapped spatial/range role, or a
/// forgotten weight normalization -- the kind of bug a screenshot won't.
@Suite("Joint Bilateral Filter")
struct JointBilateralFilterTests
{
    /// Independent transcription of JointBilateralFilter.metal's own
    /// formula -- deliberately re-derived from the algorithm, not copied
    /// from the shader source, so a shared bug wouldn't hide in both.
    /// Reproduces the shader's `address::clamp_to_edge` sampling at the
    /// texture border.
    private func referenceValue(
        signal: [[Float]], guideLuma: [[Float]],
        centerX: Int, centerY: Int, radius: Int,
        spatialSigma: Float, rangeSigma: Float
    ) -> Float
    {
        let height = signal.count, width = signal[0].count
        let twoSpatialSigmaSq = 2 * spatialSigma * spatialSigma
        let twoRangeSigmaSq = 2 * rangeSigma * rangeSigma
        let centerLuma = guideLuma[centerY][centerX]

        var accumulatedSignal: Float = 0
        var accumulatedWeight: Float = 0
        for dy in -radius...radius
        {
            for dx in -radius...radius
            {
                let sampleX = min(max(centerX + dx, 0), width - 1)
                let sampleY = min(max(centerY + dy, 0), height - 1)

                let spatialDistanceSq = Float(dx * dx + dy * dy)
                let spatialWeight = exp(-spatialDistanceSq / twoSpatialSigmaSq)

                let rangeDelta = guideLuma[sampleY][sampleX] - centerLuma
                let rangeWeight = exp(-(rangeDelta * rangeDelta) / twoRangeSigmaSq)

                let weight = spatialWeight * rangeWeight
                accumulatedSignal += signal[sampleY][sampleX] * weight
                accumulatedWeight += weight
            }
        }
        return accumulatedWeight > 0 ? accumulatedSignal / accumulatedWeight : signal[centerY][centerX]
    }

    /// Runs the actual bundled JointBilateralFilter.metal kernel (same
    /// Bundle.module lookup JointBilateralFilterNode.setupComputePipeline()
    /// uses) against `signal`/`guideLuma` (row-major, uniform across RGB),
    /// returning every output pixel's red channel (== its other channels,
    /// since input channels are all equal).
    private func runKernel(
        signal: [[Float]], guideLuma: [[Float]],
        radius: Int, spatialSigma: Float, rangeSigma: Float
    ) throws -> [[Float]]?
    {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }

        guard
            let shaderURL = Bundle.module.url(forResource: "JointBilateralFilter", withExtension: "metal", subdirectory: "Compute/Mask"),
            let source = try? MetalFileCompiler(watch: false).parse(shaderURL),
            let library = try? device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: "jointBilateralFilter")
        else { return nil }

        let pipeline = try device.makeComputePipelineState(function: function)

        let height = signal.count, width = signal[0].count

        func makeTexture(_ values: [[Float]]) throws -> MTLTexture
        {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else
            {
                throw GraphExecutionTestFailure("Failed to create test texture")
            }
            var pixels = [Float](repeating: 0, count: width * height * 4)
            for y in 0..<height
            {
                for x in 0..<width
                {
                    let base = (y * width + x) * 4
                    pixels[base + 0] = values[y][x]
                    pixels[base + 1] = values[y][x]
                    pixels[base + 2] = values[y][x]
                    pixels[base + 3] = 1
                }
            }
            pixels.withUnsafeBytes { rawBuffer in
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: rawBuffer.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride)
            }
            return texture
        }

        let signalTexture = try makeTexture(signal)
        let guideTexture = try makeTexture(guideLuma)
        let outputTexture = try makeTexture(signal.map { $0.map { _ in Float(0) } })

        struct FilterUniforms
        {
            var radius: Int32
            var spatialSigma: Float
            var rangeSigma: Float
        }
        var uniforms = FilterUniforms(radius: Int32(radius), spatialSigma: spatialSigma, rangeSigma: rangeSigma)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(signalTexture, index: 0)
        encoder.setTexture(guideTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<FilterUniforms>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var readback = [Float](repeating: 0, count: width * height * 4)
        readback.withUnsafeMutableBytes { rawBuffer in
            outputTexture.getBytes(rawBuffer.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }

        var result = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)
        for y in 0..<height
        {
            for x in 0..<width
            {
                result[y][x] = readback[(y * width + x) * 4]
            }
        }
        return result
    }

    @Test("A flat guide reduces to a plain Gaussian-weighted spatial blur")
    func flatGuideMatchesSpatialGaussian() throws
    {
        let signal: [[Float]] = [
            [0.0, 1.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 1.0, 0.0],
        ]
        let guideLuma: [[Float]] = Array(repeating: Array(repeating: 0.5, count: 3), count: 3)
        let radius = 1, spatialSigma: Float = 1.0, rangeSigma: Float = 1.0

        guard let output = try runKernel(signal: signal, guideLuma: guideLuma, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma) else { return }

        let expected = referenceValue(signal: signal, guideLuma: guideLuma, centerX: 1, centerY: 1, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma)
        #expect(abs(output[1][1] - expected) < 0.001)
        // Sanity: the peak column pulls the center above a naive unweighted
        // average (1/9 = 0.111) but not all the way to 1.0.
        #expect(output[1][1] > 0.3 && output[1][1] < 0.6)
    }

    @Test("A sharp guide edge stops the blend from crossing it")
    func guideEdgePreventsBlending() throws
    {
        let signal: [[Float]] = [
            [0.2, 0.2, 0.8],
            [0.2, 0.2, 0.8],
            [0.2, 0.2, 0.8],
        ]
        let guideLuma: [[Float]] = [
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
        ]
        // Large spatial sigma -> spatial weight is ~uniform across the 3x3
        // window, isolating the range term's edge-preserving behavior.
        let radius = 1, spatialSigma: Float = 1000, rangeSigma: Float = 0.05

        guard let output = try runKernel(signal: signal, guideLuma: guideLuma, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma) else { return }

        let expected = referenceValue(signal: signal, guideLuma: guideLuma, centerX: 1, centerY: 1, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma)
        #expect(abs(output[1][1] - expected) < 0.001)
        // The center column sits on the 0.2 side of the guide's edge -- a
        // correct edge-aware filter must not pull it toward the 0.8 column.
        #expect(output[1][1] < 0.21)
    }

    @Test("A large range sigma degenerates to ignoring the guide entirely")
    func largeRangeSigmaIgnoresGuide() throws
    {
        let signal: [[Float]] = [
            [0.2, 0.2, 0.8],
            [0.2, 0.2, 0.8],
            [0.2, 0.2, 0.8],
        ]
        let guideLuma: [[Float]] = [
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
            [0.0, 0.0, 1.0],
        ]
        let radius = 1, spatialSigma: Float = 1000, rangeSigma: Float = 1000

        guard let output = try runKernel(signal: signal, guideLuma: guideLuma, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma) else { return }

        let expected = referenceValue(signal: signal, guideLuma: guideLuma, centerX: 1, centerY: 1, radius: radius, spatialSigma: spatialSigma, rangeSigma: rangeSigma)
        #expect(abs(output[1][1] - expected) < 0.001)
        // With the guide effectively ignored and near-uniform spatial
        // weight, this degenerates to the plain 3x3 average: (0.2*6+0.8*3)/9.
        #expect(abs(output[1][1] - 0.4444) < 0.01)
    }

    @Test("Radius zero is a pure passthrough")
    func radiusZeroPassesThrough() throws
    {
        let signal: [[Float]] = [
            [0.1, 0.9, 0.3],
            [0.7, 0.4, 0.2],
            [0.6, 0.5, 0.8],
        ]
        let guideLuma: [[Float]] = [
            [0.9, 0.1, 0.4],
            [0.2, 0.8, 0.3],
            [0.5, 0.6, 0.1],
        ]

        guard let output = try runKernel(signal: signal, guideLuma: guideLuma, radius: 0, spatialSigma: 1.0, rangeSigma: 1.0) else { return }

        for y in 0..<3
        {
            for x in 0..<3
            {
                #expect(abs(output[y][x] - signal[y][x]) < 0.001)
            }
        }
    }
}
