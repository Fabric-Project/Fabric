import Foundation
import Metal
import Satin
import simd

public final class GaussianBlurChannelsNode: BaseMultiPassBlurEffectTwoChannelNode {
    override public class var name: String { "Gaussian Blur Channels" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Blur) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Separable Gaussian-style blur with independent red, green, and blue channel amounts." }

    override public class var sourceShaderName: String { "GaussianBlurChannelsShader" }

    private struct GaussianPassUniforms {
        var direction: simd_float2
        var amountScale: Float
        var padding: Float
    }

    private var passUniformsBuffers: [StructBuffer<GaussianPassUniforms>] = []

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }

    private func passUniformsBuffer(forStepIndex index: Int) -> StructBuffer<GaussianPassUniforms> {
        while self.passUniformsBuffers.count <= index {
            let bufferLabel = "Gaussian Blur Channels Pass Uniforms \(self.passUniformsBuffers.count)"
            let buffer = StructBuffer<GaussianPassUniforms>(device: self.context.device, count: 1, label: bufferLabel)
            self.passUniformsBuffers.append(buffer)
        }

        return self.passUniformsBuffers[index]
    }

    override public func scaledPassSize(baseWidth: Int, baseHeight: Int, amount: Float, passRatio: Float) -> (width: Int, height: Int) {
        let normalizedAmount = max(amount / BaseMultiPassBlurEffectNode.maxBlur, 0.0001)
        let passAmount = min(1.0, passRatio / normalizedAmount)

        let width = max(1, Int(Float(baseWidth) * passAmount))
        let height = max(1, Int(Float(baseHeight) * passAmount))

        return (width, height)
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) throws
    {
        let inputs = self.imageInputPorts()
        guard inputs.count >= 1,
              let inputTexture = inputs[0].value?.texture else {
            self.outputTexturePort.send(nil)
            return
        }
        let originalTexture = inputs.indices.contains(1) ? (inputs[1].value?.texture ?? inputTexture) : inputTexture

        let redAmount = self.floatParameterValue(named: "Red Amount")
        let greenAmount = self.floatParameterValue(named: "Green Amount")
        let blueAmount = self.floatParameterValue(named: "Blue Amount")
        let amount = max(redAmount, max(greenAmount, blueAmount))

        var steps: [MultiPassStep] = []
        if amount <= Self.lowAmountThreshold {
            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 0.0, vector: simd_float2(1.0, 0.0)))
            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 0.0, vector: simd_float2(0.0, 1.0)))
        } else {
            let stageRatios: [(ratio: Float, multiplier: Float)] = [
                (0.1, 0.111),
                (0.2, 0.3333),
                (0.4, 0.666),
                (0.6, 1.0),
                (0.8, 0.666),
            ]

            for stage in stageRatios {
                let stageSize = self.scaledPassSize(baseWidth: inputTexture.width,
                                                    baseHeight: inputTexture.height,
                                                    amount: amount,
                                                    passRatio: stage.ratio)

                steps.append(MultiPassStep(width: stageSize.width,
                                           height: stageSize.height,
                                           amountScale: stage.multiplier,
                                           vector: simd_float2(1.0, 0.0)))
                steps.append(MultiPassStep(width: stageSize.width,
                                           height: stageSize.height,
                                           amountScale: stage.multiplier,
                                           vector: simd_float2(0.0, 1.0)))
            }

            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 0.333, vector: simd_float2(1.0, 0.0)))
            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 0.333, vector: simd_float2(0.0, 1.0)))
        }

        let outputImage = self.runChannelPassChain(renderer: renderer,
                                                   commandBuffer: commandBuffer,
                                                   inputTexture: inputTexture,
                                                   originalTexture: originalTexture,
                                                   steps: steps)

        if let outputImage {
            self.outputTexturePort.send(outputImage)
        } else {
            self.outputTexturePort.send(nil)
        }
    }

    private func runChannelPassChain(renderer: GraphRenderer,
                                     commandBuffer: MTLCommandBuffer,
                                     inputTexture: MTLTexture,
                                     originalTexture: MTLTexture,
                                     steps: [MultiPassStep]) -> FabricImage? {
        guard !steps.isEmpty else {
            return nil
        }

        var currentTexture: MTLTexture = inputTexture
        var currentImage: FabricImage? = nil

        for (index, step) in steps.enumerated() {
            guard let nextImage = try? renderer.newImage(withWidth: step.width, height: step.height) else {
                currentImage?.release()
                return nil
            }

            commandBuffer.pushDebugGroup("\(self.name) - pass \(index)")

            let passUniforms = GaussianPassUniforms(direction: step.vector,
                                                    amountScale: step.amountScale,
                                                    padding: 0.0)
            let passBuffer = self.passUniformsBuffer(forStepIndex: index)
            passBuffer.update(data: [passUniforms])
            self.postMaterial.set(passBuffer, index: FragmentBufferIndex.Custom0)

            self.postProcessor.mesh.preDraw = { renderEncoder in
                renderEncoder.setFragmentTexture(currentTexture, index: FragmentTextureIndex.Custom0.rawValue)
                renderEncoder.setFragmentTexture(originalTexture, index: FragmentTextureIndex.Custom1.rawValue)
            }

            self.postProcessor.resize(size: (width: Float(step.width), height: Float(step.height)), scaleFactor: 1)

            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = nextImage.texture

            self.postProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)

            currentImage?.release()
            currentImage = nextImage
            currentTexture = nextImage.texture

            commandBuffer.popDebugGroup()
        }

        return currentImage
    }
}
