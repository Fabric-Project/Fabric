import Foundation
import Metal
import Satin

public final class ZoomBlurNode: BaseMultiPassBlurEffectNode {
    override public class var name: String { "Zoom Blur" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Blur) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Radial blur centered around a controllable origin." }

    override class var sourceShaderName: String { "ZoomBlurShader" }

    private struct ZoomPassUniforms {
        var amountScale: Float
    }

    @ObservationIgnored private var passUniformsBuffers: [StructBuffer<ZoomPassUniforms>] = []

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }

    private func passUniformsBuffer(forStepIndex index: Int) -> StructBuffer<ZoomPassUniforms> {
        while self.passUniformsBuffers.count <= index {
            let bufferLabel = "Zoom Blur Pass Uniforms \(self.passUniformsBuffers.count)"
            let buffer = StructBuffer<ZoomPassUniforms>(device: self.context.device, count: 1, label: bufferLabel)
            self.passUniformsBuffers.append(buffer)
        }

        return self.passUniformsBuffers[index]
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
//        guard self.shouldExecuteThisFrame() else {
//            return
//        }

        guard let inputTexture = self.inputTexturePort.value?.texture else {
            self.outputTexturePort.send(nil)
            return
        }

        let amount = self.floatParameterValue(named: "Amount")

        var steps: [MultiPassStep] = []

        if amount <= Self.lowAmountThreshold {
            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 1.0))
        } else {
            let stageRatios: [(ratio: Float, multiplier: Float)] = [
                (0.3, 1.0),
                (0.4, 1.5),
                (0.6, 1.5),
                (0.9, 2.0),
            ]

            for stage in stageRatios {
                let stageSize = self.scaledPassSize(baseWidth: inputTexture.width,
                                                    baseHeight: inputTexture.height,
                                                    amount: amount,
                                                    passRatio: stage.ratio)

                steps.append(MultiPassStep(width: stageSize.width,
                                           height: stageSize.height,
                                           amountScale: stage.multiplier))
            }

            steps.append(MultiPassStep(width: inputTexture.width, height: inputTexture.height, amountScale: 1.0))
        }

        if let outputImage = self.runPassChain(context: context,
                                               commandBuffer: commandBuffer,
                                               inputTexture: inputTexture,
                                               steps: steps,
                                               prepareStep: { [weak self] stepIndex, step in
            guard let self else { return }

            let passBuffer = self.passUniformsBuffer(forStepIndex: stepIndex)
            passBuffer.update(data: [ZoomPassUniforms(amountScale: step.amountScale)])
            self.postMaterial.set(passBuffer, index: FragmentBufferIndex.Custom0)
        }) {
            self.outputTexturePort.send(outputImage)
        } else {
            self.outputTexturePort.send(nil)
        }
    }
}
