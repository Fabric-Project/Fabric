import Metal
import simd
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

        let signalTexture = try makeTexture(device: device, signal)
        let guideTexture = try makeTexture(device: device, guideLuma)
        let outputTexture = try makeTexture(device: device, signal.map { $0.map { _ in Float(0) } })

        struct FilterUniforms
        {
            var radius: Int32
            var spatialSigma: Float
            var rangeSigma: Float
            var guideTransform: simd_float4x4
            var signalTransform: simd_float4x4
            var signalTransformInverse: simd_float4x4
        }
        var uniforms = FilterUniforms(
            radius: Int32(radius), spatialSigma: spatialSigma, rangeSigma: rangeSigma,
            guideTransform: matrix_identity_float4x4,
            signalTransform: matrix_identity_float4x4,
            signalTransformInverse: matrix_identity_float4x4
        )

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

    private func makeTexture(device: MTLDevice, _ values: [[Float]]) throws -> MTLTexture
    {
        guard let firstRow = values.first, !firstRow.isEmpty, values.allSatisfy({ $0.count == firstRow.count }) else
        {
            throw GraphExecutionTestFailure("Test texture values must be a non-empty rectangle")
        }
        let width = firstRow.count
        let height = values.count
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

    /// Runs the kernel with a signal and guide of DIFFERENT sizes, the guide
    /// optionally stored with a transform. The output is the guide's size,
    /// canonical orientation, like JointBilateralFilterNode's.
    private func runResamplingKernel(
        signal: [[Float]], guideLuma: [[Float]], guideTransform: simd_float4x4,
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

        let outputHeight = guideLuma.count, outputWidth = guideLuma[0].count
        let signalTexture = try makeTexture(device: device, signal)
        let guideTexture = try makeTexture(device: device, guideLuma)
        let outputTexture = try makeTexture(device: device, guideLuma.map { $0.map { _ in Float(0) } })

        struct FilterUniforms
        {
            var radius: Int32
            var spatialSigma: Float
            var rangeSigma: Float
            var guideTransform: simd_float4x4
            var signalTransform: simd_float4x4
            var signalTransformInverse: simd_float4x4
        }
        var uniforms = FilterUniforms(
            radius: Int32(radius), spatialSigma: spatialSigma, rangeSigma: rangeSigma,
            guideTransform: guideTransform,
            signalTransform: matrix_identity_float4x4,
            signalTransformInverse: matrix_identity_float4x4
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(signalTexture, index: 0)
        encoder.setTexture(guideTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<FilterUniforms>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: outputWidth, height: outputHeight, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var readback = [Float](repeating: 0, count: outputWidth * outputHeight * 4)
        readback.withUnsafeMutableBytes { rawBuffer in
            outputTexture.getBytes(rawBuffer.baseAddress!, bytesPerRow: outputWidth * 4 * MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0)
        }
        return (0..<outputHeight).map { y in (0..<outputWidth).map { x in readback[(y * outputWidth + x) * 4] } }
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

    @Test("A small signal is upsampled to the guide's size and snapped to the guide's edge")
    func smallSignalIsUpsampledToTheGuide() throws
    {
        // A 2x2 mask whose only boundary is between its two columns, against a
        // 4x4 guide whose sharp edge sits at the same place. Plain bilinear
        // upsampling would leave a soft ramp across the middle two columns.
        let signal: [[Float]] = [[0, 1], [0, 1]]
        let guideLuma: [[Float]] = Array(repeating: [0, 0, 1, 1], count: 4)

        guard let output = try runResamplingKernel(
            signal: signal, guideLuma: guideLuma, guideTransform: matrix_identity_float4x4,
            radius: 1, spatialSigma: 1000, rangeSigma: 0.05
        ) else { return }

        // The output has the guide's dimensions, not the signal's.
        #expect(output.count == 4)
        #expect(output.allSatisfy { $0.count == 4 })
        for y in 0..<4
        {
            #expect(output[y][0] < 0.01, "left of the edge stays 0 (row \(y))")
            #expect(output[y][1] < 0.01, "left of the edge stays 0 (row \(y))")
            #expect(output[y][2] > 0.99, "right of the edge stays 1 (row \(y))")
            #expect(output[y][3] > 0.99, "right of the edge stays 1 (row \(y))")
        }
    }

    @Test("The guide is read through its own texture transform")
    func guideIsSampledThroughItsTransform() throws
    {
        // Signal is 0 on its top row and 1 on its bottom row. The guide has
        // the matching edge, but its texture is stored upside down, so only
        // sampling through the guide's vertical-flip transform lines them up.
        let signal: [[Float]] = [[0, 0], [1, 1]]
        let guideStoredUpsideDown: [[Float]] = [[1, 1, 1, 1], [1, 1, 1, 1], [0, 0, 0, 0], [0, 0, 0, 0]]
        let verticalFlip = simd_float4x4(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, -1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 1, 0, 1)
        ))

        guard let output = try runResamplingKernel(
            signal: signal, guideLuma: guideStoredUpsideDown, guideTransform: verticalFlip,
            radius: 1, spatialSigma: 1000, rangeSigma: 0.05
        ) else { return }

        for x in 0..<4
        {
            #expect(output[0][x] < 0.01 && output[1][x] < 0.01, "canonical top half stays 0 (column \(x))")
            #expect(output[2][x] > 0.99 && output[3][x] > 0.99, "canonical bottom half stays 1 (column \(x))")
        }
    }
}
