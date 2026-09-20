import Metal
import MPSZipDepth
import Satin

public final class ZipDepthNode: Node
{
    override public class var name: String { "MPS Zip Depth" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Estimates relative depth at Zip Depth's native model resolution using Metal Performance Shaders Graph. Upsample to presentation resolution downstream, e.g. with a guided/joint bilateral filter."
    }

    /// Preset short-side resolutions the model may run at -- every value is
    /// an exact multiple of 32 (ZipDepthMPSGraph requires this for both
    /// dimensions), spanning the original hardcoded default (384) up through
    /// resolutions expensive enough that they should be an explicit,
    /// deliberate choice rather than a free-form field.
    private static let shortSideOptions = ["384", "512", "768", "1024", "1088", "1984"]

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(
                name: "Image",
                kind: .Inlet,
                description: "Image from which to estimate relative depth"
            )),
            ("inputShortSide", ParameterPort(parameter: StringParameter(
                "Model Resolution",
                Self.shortSideOptions[0],
                Self.shortSideOptions,
                .dropdown,
                "Short-side resolution the depth model runs at -- the long side is scaled to the nearest multiple of 32 to preserve aspect ratio. Higher values cost significantly more GPU time."
            ))),
            ("outputDepthImage", NodePort<FabricImage>(
                name: "Depth Image",
                kind: .Outlet,
                description: "Single-channel Float32 relative depth image at Zip Depth's native model resolution (see Model Resolution), not presentation resolution -- upsample downstream, e.g. with a Joint Bilateral Filter guided by the original color image"
            )),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var inputShortSide: ParameterPort<String> { port(named: "inputShortSide") }
    public var outputDepthImage: NodePort<FabricImage> { port(named: "outputDepthImage") }

    private var preprocessor: ZipDepthPreprocessor?
    private var model: ZipDepthMPSGraph?
    private var modelInputBuffer: MTLBuffer?
    private var modelOutputBuffer: MTLBuffer?
    private var modelWidth = 0
    private var modelHeight = 0

    public required init(context: Context)
    {
        super.init(context: context)
        self.setupComputeKernels()
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
        self.setupComputeKernels()
    }

    override public func stopExecution(renderer: GraphRenderer) throws
    {
        self.model = nil
        self.modelInputBuffer = nil
        self.modelOutputBuffer = nil
        self.modelWidth = 0
        self.modelHeight = 0
    }

    override public func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        guard self.inputImage.valueDidChange || self.isDirty else { return }
        guard let inputImage = self.inputImage.value else
        {
            self.outputDepthImage.send(nil)
            return
        }
        guard let preprocessor else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Zip Depth compute kernels are unavailable"
            )
        }

        let presentationWidth = max(1, Int(inputImage.presentationSize.width.rounded()))
        let presentationHeight = max(1, Int(inputImage.presentationSize.height.rounded()))
        let shortSide = self.inputShortSide.value.flatMap(Double.init) ?? 384.0
        let modelSize = Self.modelInputSize(
            presentationWidth: presentationWidth,
            presentationHeight: presentationHeight,
            shortSide: shortSide
        )
        try self.prepareModel(width: modelSize.width, height: modelSize.height)

        guard let model, let modelInputBuffer, let modelOutputBuffer else
        {
            throw FabricError(
                .execution(.outOfMemory),
                severity: .recoverable,
                message: "Zip Depth model buffers are unavailable"
            )
        }

        // Native model resolution, not presentation resolution -- upsampling
        // to presentation size (plain bilinear, guided/joint bilateral, or
        // otherwise) is a downstream node's job now, not baked in here. See
        // outputDepthImage's port description.
        let outputImage = try renderer.newImage(
            withWidth: modelSize.width,
            height: modelSize.height,
            format: .r32Float
        )
        outputImage.texture.label = "Zip Depth Relative Depth (\(modelSize.width)×\(modelSize.height))"

        // Preprocess, model inference, and the output blit are all encoded
        // onto Fabric's shared per-frame `commandBuffer` -- no second
        // command buffer. Neither the crop kernel nor model.encode() ever
        // commits anything (MPSGraphExecutable.encode(to:) doesn't commit on
        // its own -- that's always an explicit, caller-owned decision), so
        // all three steps just sit encoded here, in order, like any other
        // node's work, until whoever owns `commandBuffer` (Fabric's render
        // loop) commits it at the end of the frame. That ordering is also
        // what makes the blit below safe to read modelOutputBuffer with no
        // CPU wait: everything on one buffer executes in encode order.
        commandBuffer.pushDebugGroup("Zip Depth \(modelSize.width)×\(modelSize.height)")
        defer { commandBuffer.popDebugGroup() }

        try preprocessor.encode(
            inputTexture: inputImage.texture,
            textureTransform: inputImage.textureTransform,
            outputBuffer: modelInputBuffer,
            outputWidth: modelSize.width,
            outputHeight: modelSize.height,
            commandBuffer: commandBuffer
        )

        // Drops this frame's depth output (never calls outputDepthImage.send(),
        // so downstream nodes keep whatever was last sent) instead of blocking
        // if all maxFramesInFlight slots are already in flight on the GPU --
        // matches every MediaPipe node's own no-backlog semantics.
        guard try model.encode(
            inputBuffer: modelInputBuffer,
            outputBuffer: modelOutputBuffer,
            commandBuffer: commandBuffer,
            commit: false
        ) else
        {
            return
        }

        // modelOutputBuffer is already exactly modelSize.width ×
        // modelSize.height, row-major float32 -- a straight copy into a
        // same-size texture, not a resample, so a blit is the right tool:
        // no compute kernel, no threadgroup dispatch, GPU does a plain
        // memory copy. .storageModePrivate is fine as a blit source --
        // blits run entirely on the GPU, no CPU access required.
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create the Zip Depth output blit encoder"
            )
        }
        blitEncoder.label = "Zip Depth Output Blit"
        blitEncoder.copy(
            from: modelOutputBuffer,
            sourceOffset: 0,
            sourceBytesPerRow: modelSize.width * MemoryLayout<Float>.stride,
            // Apple's documented contract for this overload: sourceBytesPerImage
            // must be 0 unless the destination is a 3D or array texture.
            // outputImage.texture is a plain 2D texture.
            sourceBytesPerImage: 0,
            sourceSize: MTLSize(width: modelSize.width, height: modelSize.height, depth: 1),
            to: outputImage.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        // `commandBuffer` is Fabric's shared per-frame buffer -- this node
        // never waits on it, so it's still in flight when execute() returns.
        // GraphRendererTextureCache recycles a managed FabricImage's texture
        // the instant its last Swift reference drops, with no regard for
        // whether the GPU is still using it, so inputImage/outputImage need
        // to stay alive until this buffer's GPU work actually completes.
        // model/modelInputBuffer/modelOutputBuffer need the same treatment:
        // with no CPU wait, prepareModel() can reassign
        // self.model/self.modelInputBuffer/self.modelOutputBuffer on a later
        // frame (input aspect ratio change) while this frame's GPU work is
        // still in flight against these specific instances.
        commandBuffer.addCompletedHandler { [inputImage, outputImage, model, modelInputBuffer, modelOutputBuffer] _ in
            withExtendedLifetime((inputImage, outputImage, model, modelInputBuffer, modelOutputBuffer)) {}
        }

        self.outputDepthImage.send(outputImage)
    }

    private func setupComputeKernels()
    {
        self.preprocessor = try? ZipDepthPreprocessor(device: self.context.device)
    }

    private func prepareModel(width: Int, height: Int) throws
    {
        guard self.model == nil || width != self.modelWidth || height != self.modelHeight else { return }

        // Shared with every other Zip Depth node at this resolution: one compile
        // and one copy of the weights however many nodes ask. Held weakly by the
        // cache, so this node's own reference (`self.model`) is what keeps it
        // alive, and it is released when the last node stops or changes size.
        let model = try ZipDepthSharedModels.model(
            width: width,
            height: height,
            commandQueue: self.context.commandQueue
        )
        guard let inputBuffer = self.context.device.makeBuffer(
            length: model.inputBufferLength,
            options: .storageModePrivate
        ), let outputBuffer = self.context.device.makeBuffer(
            length: model.outputBufferLength,
            options: .storageModePrivate
        ) else
        {
            throw FabricError(
                .execution(.outOfMemory),
                severity: .recoverable,
                message: "Could not allocate Zip Depth model buffers"
            )
        }

        inputBuffer.label = "Zip Depth RGB Input"
        // Private, not shared: model.encode() writes and the output blit
        // reads this entirely on the GPU, with no CPU-side copy.
        outputBuffer.label = "Zip Depth Model Output"
        self.model = model
        self.modelInputBuffer = inputBuffer
        self.modelOutputBuffer = outputBuffer
        self.modelWidth = width
        self.modelHeight = height
    }

    private static func modelInputSize(
        presentationWidth: Int,
        presentationHeight: Int,
        shortSide: Double
    ) -> (width: Int, height: Int)
    {
        if presentationWidth <= presentationHeight
        {
            let scaledHeight = shortSide * Double(presentationHeight) / Double(presentationWidth)
            return (Self.nearestMultipleOf32(shortSide), Self.nearestMultipleOf32(scaledHeight))
        }

        let scaledWidth = shortSide * Double(presentationWidth) / Double(presentationHeight)
        return (Self.nearestMultipleOf32(scaledWidth), Self.nearestMultipleOf32(shortSide))
    }

    private static func nearestMultipleOf32(_ value: Double) -> Int
    {
        max(32, Int((value / 32.0).rounded()) * 32)
    }
}
