//
//  DCTTransformNode.swift
//  Fabric
//

import Foundation
import Metal
import Satin

public class BaseDCTTransformNode: Node
{
    static let maximumBlockSize = 32

    override public class var name: String { "Base DCT Transform" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Transforms linear RGB images between spatial and block-frequency representations."
    }

    class var computeKernelName: String {
        fatalError("DCT transform subclasses must provide a compute kernel name")
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            (
                "inputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Inlet,
                    description: "Linear RGB image to transform"
                )
            ),
            (
                "inputBlockSize",
                ParameterPort(
                    parameter: IntParameter(
                        "Block Size",
                        8,
                        2,
                        maximumBlockSize,
                        .slider,
                        "Width and height of each independently transformed block"
                    )
                )
            ),
            (
                "outputImage",
                NodePort<FabricImage>(
                    name: "Image",
                    kind: .Outlet,
                    description: "Signed RGBA16Float transform result"
                )
            ),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputBlockSize: ParameterPort<Int> { port(named: "inputBlockSize") }
    public var outputImage: NodePort<FabricImage> { port(named: "outputImage") }

    private var computePipeline: MTLComputePipelineState?
    private var basisBuffer: MTLBuffer?

    public required init(context: Context)
    {
        super.init(context: context)
        setupComputeResources()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        setupComputeResources()
    }

    private func setupComputeResources()
    {
        let compiler = MetalFileCompiler(watch: false)

        guard
            let shaderURL = Bundle.module.url(
                forResource: "DCTTransform",
                withExtension: "metal",
                subdirectory: "Compute/DCT"
            ),
            let source = try? compiler.parse(shaderURL),
            let library = try? context.device.makeLibrary(source: source, options: nil),
            let function = library.makeFunction(name: Self.computeKernelName),
            let pipeline = try? context.device.makeComputePipelineState(function: function)
        else {
            return
        }

        let basisValues = Self.makeBasisValues()
        let basisLength = basisValues.count * MemoryLayout<Float>.stride

        self.computePipeline = pipeline
        self.basisBuffer = context.device.makeBuffer(
            bytes: basisValues,
            length: basisLength,
            options: .storageModeShared
        )
        self.basisBuffer?.label = "DCT Orthonormal Basis Values"
    }

    private static func makeBasisValues() -> [Float]
    {
        var values: [Float] = []
        values.reserveCapacity(
            (maximumBlockSize * (maximumBlockSize + 1) * (2 * maximumBlockSize + 1)) / 6
        )

        for dimension in 1...maximumBlockSize {
            let dimensionValue = Float(dimension)

            for frequency in 0..<dimension {
                let normalization = frequency == 0
                    ? (1.0 / dimensionValue).squareRoot()
                    : (2.0 / dimensionValue).squareRoot()

                for sample in 0..<dimension {
                    let angle = Float.pi
                        * (Float(sample) + 0.5)
                        * Float(frequency)
                        / dimensionValue
                    values.append(normalization * cos(angle))
                }
            }
        }

        return values
    }

    private struct DCTUniforms
    {
        var blockSize: UInt32
    }

    override public func execute(renderer: GraphRenderer,
                                 executionInfo: GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard inputImage.valueDidChange || inputBlockSize.valueDidChange else { return }

        guard
            let sourceTexture = inputImage.value?.texture,
            let computePipeline,
            let basisBuffer
        else {
            outputImage.send(nil)
            return
        }

        let maximumSupportedBlockSize = min(
            Self.maximumBlockSize,
            Int(Double(computePipeline.maxTotalThreadsPerThreadgroup).squareRoot())
        )
        let blockSize = min(
            max(inputBlockSize.value ?? 8, 2),
            maximumSupportedBlockSize
        )

        guard
            let transformedImage = renderer.newImage(
                withWidth: sourceTexture.width,
                height: sourceTexture.height,
                format: .rgba16Float
            ),
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            outputImage.send(nil)
            return
        }

        transformedImage.texture.label = "\(name) Output"
        computeEncoder.label = name
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(transformedImage.texture, index: 1)
        computeEncoder.setBuffer(basisBuffer, offset: 0, index: 0)

        var uniforms = DCTUniforms(blockSize: UInt32(blockSize))
        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<DCTUniforms>.stride,
            index: 1
        )

        computeEncoder.dispatchThreadgroups(
            MTLSize(
                width: (sourceTexture.width + blockSize - 1) / blockSize,
                height: (sourceTexture.height + blockSize - 1) / blockSize,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(
                width: blockSize,
                height: blockSize,
                depth: 1
            )
        )
        computeEncoder.endEncoding()

        outputImage.send(transformedImage)
    }
}

public final class DCTNode: BaseDCTTransformNode
{
    override public class var name: String { "DCT" }
    override public class var nodeDescription: String {
        "Computes an orthonormal block-based DCT-II over linear RGB."
    }

    override class var computeKernelName: String { "dctForward" }
}

public final class InverseDCTNode: BaseDCTTransformNode
{
    override public class var name: String { "Inverse DCT" }
    override public class var nodeDescription: String {
        "Reconstructs linear RGB from orthonormal block-based DCT coefficients."
    }

    override class var computeKernelName: String { "dctInverse" }
}
