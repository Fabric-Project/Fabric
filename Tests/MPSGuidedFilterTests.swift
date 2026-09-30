import Metal
import MetalPerformanceShaders
import Testing

@Test("Scalar RGB guided regression reconstructs at Guide resolution")
func scalarRGBGuidedRegressionReconstructsAtGuideResolution() throws
{
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue()
    else
    {
        return
    }

    let regressionWidth = 64
    let regressionHeight = 64
    let outputWidth = 256
    let outputHeight = 128

    let signal = try makeSingleChannelTexture(
        device: device,
        width: regressionWidth,
        height: regressionHeight,
        values: (0..<(regressionWidth * regressionHeight)).map
        {
            $0 % regressionWidth < regressionWidth / 2 ? 0 : 1
        }
    )
    let regressionGuide = try makeGreenEdgeTexture(
        device: device,
        width: regressionWidth,
        height: regressionHeight
    )
    let reconstructionGuide = try makeGreenEdgeTexture(
        device: device,
        width: outputWidth,
        height: outputHeight
    )
    let coefficients = try makeTexture(
        device: device,
        pixelFormat: .rgba32Float,
        width: regressionWidth,
        height: regressionHeight,
        storageMode: .private
    )
    let output = try makeTexture(
        device: device,
        pixelFormat: .r32Float,
        width: outputWidth,
        height: outputHeight,
        storageMode: .shared
    )

    let filter = MPSImageGuidedFilter(device: device, kernelDiameter: 11)
    filter.epsilon = 0.0001
    let commandBuffer = try #require(commandQueue.makeCommandBuffer())
    filter.encodeRegression(
        to: commandBuffer,
        sourceTexture: signal,
        guidanceTexture: regressionGuide,
        weightsTexture: nil,
        destinationCoefficientsTexture: coefficients
    )
    filter.encodeReconstruction(
        to: commandBuffer,
        guidanceTexture: reconstructionGuide,
        coefficientsTexture: coefficients,
        destinationTexture: output
    )
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.status == .completed)

    var values = [Float](repeating: 0, count: outputWidth * outputHeight)
    output.getBytes(
        &values,
        bytesPerRow: outputWidth * MemoryLayout<Float>.stride,
        from: MTLRegionMake2D(0, 0, outputWidth, outputHeight),
        mipmapLevel: 0
    )
    let middleRow = outputHeight / 2
    #expect(values[middleRow * outputWidth + outputWidth / 4] < 0.01)
    #expect(values[middleRow * outputWidth + outputWidth * 3 / 4] > 0.99)
    #expect(values[middleRow * outputWidth + outputWidth / 2 - 2] < 0.1)
    #expect(values[middleRow * outputWidth + outputWidth / 2 + 2] > 0.9)
}

private func makeSingleChannelTexture(
    device: MTLDevice,
    width: Int,
    height: Int,
    values: [Float]
) throws -> MTLTexture
{
    let texture = try makeTexture(
        device: device,
        pixelFormat: .r32Float,
        width: width,
        height: height,
        storageMode: .shared
    )
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: values,
        bytesPerRow: width * MemoryLayout<Float>.stride
    )
    return texture
}

private func makeGreenEdgeTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture
{
    let texture = try makeTexture(
        device: device,
        pixelFormat: .rgba32Float,
        width: width,
        height: height,
        storageMode: .shared
    )
    var values = [Float](repeating: 0, count: width * height * 4)
    for row in 0..<height
    {
        for column in 0..<width
        {
            let offset = (row * width + column) * 4
            values[offset] = 0.25
            values[offset + 1] = column < width / 2 ? 0 : 1
            values[offset + 2] = 0.75
            values[offset + 3] = 1
        }
    }
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: values,
        bytesPerRow: width * 4 * MemoryLayout<Float>.stride
    )
    return texture
}

private func makeTexture(
    device: MTLDevice,
    pixelFormat: MTLPixelFormat,
    width: Int,
    height: Int,
    storageMode: MTLStorageMode
) throws -> MTLTexture
{
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = storageMode
    return try #require(device.makeTexture(descriptor: descriptor))
}
