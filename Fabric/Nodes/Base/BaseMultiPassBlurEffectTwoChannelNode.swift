import Foundation
import Metal
import Satin
import simd

public class BaseMultiPassBlurEffectTwoChannelNode: BaseImageNode
{
    override public class var defaultImageInputCountHint: Int? { 2 }
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
    @ObservationIgnored private var hasLoggedInputCountMismatch = false


    public func floatParameterValue(named name: String, default defaultValue: Float = 0.0) -> Float
    {
        self.postMaterial.parameters.get(name, as: FloatParameter.self)?.value ?? defaultValue
    }

    public func validatedTwoInputTextures() -> (MTLTexture, MTLTexture)? {
        let inputs = self.imageInputPorts()
        if inputs.count != 2 {
            if self.hasLoggedInputCountMismatch == false {
                print("\\(self.name) expected exactly 2 input images, but got \\(inputs.count).")
                self.hasLoggedInputCountMismatch = true
            }
            return nil
        }

        guard let first = inputs[0].value?.texture,
              let second = inputs[1].value?.texture else {
            return nil
        }

        self.hasLoggedInputCountMismatch = false
        return (first, second)
    }

    public func scaledPassSize(baseWidth: Int, baseHeight: Int, amount: Float, passRatio: Float) -> (width: Int, height: Int) {
        let normalizedAmount = max(amount / 5.0, 0.0001)
        let passAmount = min(1.0, passRatio / normalizedAmount)

        let width = max(1, Int(Float(baseWidth) * passAmount))
        let height = max(1, Int(Float(baseHeight) * passAmount))

        return (width, height)
    }

    public func runPassChain(context: GraphExecutionContext,
                             commandBuffer: MTLCommandBuffer,
                             inputATexture: MTLTexture,
                             inputBTexture: MTLTexture,
                             steps: [MultiPassStep],
                             prepareStep: (Int, MultiPassStep) -> Void) -> FabricImage?
    {
        guard let graphRenderer = context.graphRenderer else {
            return nil
        }

        guard !steps.isEmpty else {
            return nil
        }

        var currentTexture: MTLTexture = inputATexture
        var currentImage: FabricImage? = nil

        for (index, step) in steps.enumerated() {
            guard let nextImage = graphRenderer.newImage(withWidth: step.width, height: step.height) else {
                currentImage?.release()
                return nil
            }

            prepareStep(index, step)

            self.postProcessor.mesh.preDraw = { renderEncoder in
                renderEncoder.setFragmentTexture(currentTexture, index: FragmentTextureIndex.Custom0.rawValue)
                renderEncoder.setFragmentTexture(inputBTexture, index: FragmentTextureIndex.Custom1.rawValue)
            }

            self.postProcessor.renderer.size.width = Float(step.width)
            self.postProcessor.renderer.size.height = Float(step.height)

            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = nextImage.texture

            self.postProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)

            currentImage?.release()
            currentImage = nextImage
            currentTexture = nextImage.texture
        }

        return currentImage
    }
}
