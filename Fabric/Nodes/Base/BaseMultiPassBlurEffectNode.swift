import Foundation
import Metal
import Satin
import simd

public class BaseMultiPassBlurEffectNode: BaseEffectNode
{
    static let maxBlur:Float = 50.0
    
    public struct MultiPassStep
    {
        public let width: Int
        public let height: Int
        public let amountScale: Float
        public let vector: simd_float2

        public init(width: Int, height: Int, amountScale: Float, vector: simd_float2 = .zero)
        {
            self.width = max(1, width)
            self.height = max(1, height)
            self.amountScale = amountScale
            self.vector = vector
        }
    }

    public static let lowAmountThreshold: Float = 0.0


    public func floatParameterValue(named name: String, default defaultValue: Float = 0.0) -> Float
    {
        self.postMaterial.parameters.get(name, as: FloatParameter.self)?.value ?? defaultValue
    }

    public func scaledPassSize(baseWidth: Int, baseHeight: Int, amount: Float, passRatio: Float) -> (width: Int, height: Int)
    {
        let normalizedAmount = max(amount / Self.maxBlur, 0.0001)
        let passAmount = min(1.0, passRatio / normalizedAmount)

        let width = max(1, Int(Float(baseWidth) * passAmount))
        let height = max(1, Int(Float(baseHeight) * passAmount))

        return (width, height)
    }

    public func runPassChain(context: GraphExecutionContext,
                             commandBuffer: MTLCommandBuffer,
                             inputTexture: MTLTexture,
                             steps: [MultiPassStep],
                             prepareStep: (Int, MultiPassStep) -> Void ) -> FabricImage? {
        guard let graphRenderer = context.graphRenderer else {
            return nil
        }

        guard !steps.isEmpty else {
            return nil
        }

        var currentTexture: MTLTexture = inputTexture
        var currentImage: FabricImage? = nil

        for (index, step) in steps.enumerated() {
            guard let nextImage = graphRenderer.newImage(withWidth: step.width, height: step.height) else {
                currentImage?.release()
                return nil
            }

            commandBuffer.pushDebugGroup("\(self.name) - pass \(index)")

            prepareStep(index, step)

            self.postProcessor.mesh.preDraw = { renderEncoder in
                renderEncoder.setFragmentTexture(currentTexture, index: FragmentTextureIndex.Custom0.rawValue)
            }

            self.postProcessor.renderer.size.width = Float(step.width)
            self.postProcessor.renderer.size.height = Float(step.height)

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
