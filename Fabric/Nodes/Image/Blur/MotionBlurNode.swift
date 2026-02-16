import Foundation
import Metal
import Satin

public final class MotionBlurNode: BaseMultiPassBlurEffectNode {
    override public class var name: String { "Motion Blur" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Blur) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Directional blur with progressive downsample passes." }

    override class var sourceShaderName: String { "MotionBlurShader" }

    private struct MotionPassUniforms {
        var amountScale: Float
    }

    @ObservationIgnored private var passUniformsBuffers: [StructBuffer<MotionPassUniforms>] = []

    required init(context: Context, fileURL: URL) throws {
        try super.init(context: context, fileURL: fileURL)
    }

    required init(context: Context) {
        super.init(context: context)
    }

    required init(from decoder: any Decoder) throws {
        try super.init(from: decoder)
    }

    private func passUniformsBuffer(forStepIndex index: Int) -> StructBuffer<MotionPassUniforms> {
        while self.passUniformsBuffers.count <= index {
            let bufferLabel = "Motion Blur Pass Uniforms \(self.passUniformsBuffers.count)"
            let buffer = StructBuffer<MotionPassUniforms>(device: self.context.device, count: 1, label: bufferLabel)
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
                (0.2, 1.0),
                (0.3, 1.5),
                (0.5, 1.5),
                (0.8, 2.0),
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
            passBuffer.update(data: [MotionPassUniforms(amountScale: step.amountScale)])
            self.postMaterial.set(passBuffer, index: FragmentBufferIndex.Custom0)
        }) {
            self.outputTexturePort.send(outputImage)
        } else {
            self.outputTexturePort.send(nil)
        }
    }
}
