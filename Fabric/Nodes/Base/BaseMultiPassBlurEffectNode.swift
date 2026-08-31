import Foundation
import Metal
import Satin
import simd

public class BaseMultiPassBlurEffectNode: BaseImageNode
{
    override public class var defaultImageInputCountHint: Int? { 1 }
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
    private var hasLoggedInputCountMismatch = false
    private var textureTransformBuffers: [StructBuffer<simd_float4x4>] = []


    public func floatParameterValue(named name: String, default defaultValue: Float = 0.0) -> Float
    {
        self.postMaterial.parameters.get(name, as: FloatParameter.self)?.value ?? defaultValue
    }

    public func validatedSingleInputImage() -> FabricImage? {
        let inputs = self.imageInputPorts()
        if inputs.count != 1 {
            if self.hasLoggedInputCountMismatch == false {
                print("\(self) expected exactly 1 input image, but got \(inputs.count).")
                self.hasLoggedInputCountMismatch = true
            }
            return nil
        }

        self.hasLoggedInputCountMismatch = false
        return inputs[0].value
    }

    private func textureTransformBuffer(forStepIndex index: Int) -> StructBuffer<simd_float4x4> {
        while self.textureTransformBuffers.count <= index {
            let buffer = StructBuffer<simd_float4x4>(
                device: self.context.device,
                count: 1,
                label: "Multi-Pass Blur Texture Transform \(self.textureTransformBuffers.count)"
            )
            self.textureTransformBuffers.append(buffer)
        }

        return self.textureTransformBuffers[index]
    }

    public func scaledPassSize(baseWidth: Int, baseHeight: Int, amount: Float, passRatio: Float) -> (width: Int, height: Int)
    {
        let normalizedAmount = max(amount / Self.maxBlur, 0.0001)
        let passAmount = min(1.0, passRatio / normalizedAmount)

        let width = max(1, Int(Float(baseWidth) * passAmount))
        let height = max(1, Int(Float(baseHeight) * passAmount))

        return (width, height)
    }

    public func runPassChain(renderer:GraphRenderer,
                             executionInfo: GraphExecutionInfo,
                             commandBuffer: MTLCommandBuffer,
                             inputImage: FabricImage,
                             steps: [MultiPassStep],
                             prepareStep: (Int, MultiPassStep) -> Void ) -> FabricImage? {

        guard !steps.isEmpty else {
            return nil
        }

        var currentTexture = inputImage.texture
        var currentImage: FabricImage? = nil

        for (index, step) in steps.enumerated() {
            guard let nextImage = try? renderer.newImage(withWidth: step.width, height: step.height) else {
                currentImage?.release()
                return nil
            }

            commandBuffer.pushDebugGroup("\(self.debugDescription) - pass \(index)")

            prepareStep(index, step)

            let textureTransform = index == 0
                ? inputImage.textureTransform
                : matrix_identity_float4x4
            let textureTransformBuffer = self.textureTransformBuffer(forStepIndex: index)
            textureTransformBuffer.update(data: [textureTransform])
            self.postMaterial.set(textureTransformBuffer, index: FragmentBufferIndex.Custom10)

            self.postProcessor.mesh.preDraw = { renderEncoder in
                renderEncoder.setFragmentTexture(currentTexture, index: FragmentTextureIndex.Custom0.rawValue)
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
