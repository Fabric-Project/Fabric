import Metal
import MPSZipDepth
import Satin

public final class ZipDepthNode: Node
{
    override public class var name: String { "Zip Depth" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .Analysis) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String {
        "Estimates a full-resolution relative depth image using ZipDepth and Metal Performance Shaders Graph."
    }

    override public class func registerPorts(context: Context) -> [(name: String, port: Port)]
    {
        super.registerPorts(context: context) + [
            ("inputImage", NodePort<FabricImage>(
                name: "Image",
                kind: .Inlet,
                description: "Image from which to estimate relative depth"
            )),
            ("outputDepthImage", NodePort<FabricImage>(
                name: "Depth Image",
                kind: .Outlet,
                description: "Single-channel Float32 relative depth image"
            )),
        ]
    }

    public var inputImage: NodePort<FabricImage> { port(named: "inputImage") }
    public var outputDepthImage: NodePort<FabricImage> { port(named: "outputDepthImage") }

    private var preprocessor: ZipDepthPreprocessor?
    private var postprocessor: ZipDepthPostprocessor?
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
        guard let preprocessor, let postprocessor else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Zip Depth compute kernels are unavailable"
            )
        }

        let presentationWidth = max(1, Int(inputImage.presentationSize.width.rounded()))
        let presentationHeight = max(1, Int(inputImage.presentationSize.height.rounded()))
        let modelSize = Self.modelInputSize(
            presentationWidth: presentationWidth,
            presentationHeight: presentationHeight
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

        let outputImage = try renderer.newImage(
            withWidth: presentationWidth,
            height: presentationHeight,
            format: .r32Float
        )
        outputImage.texture.label = "Zip Depth Relative Depth"

        commandBuffer.pushDebugGroup("Zip Depth \(modelSize.width)×\(modelSize.height)")
        defer { commandBuffer.popDebugGroup() }

        // The GPU-resident model.encode(inputBuffer:outputBuffer:commandBuffer:)
        // path has no slot/frame-in-flight protection (unlike run()/submit(),
        // which serialize access through a maxFramesInFlight semaphore) and
        // crashed with Metal heap-purgeability assertions when called once
        // per frame against the same model instance. model.run(inputBuffer:)
        // is the proven path -- the same one MediaPipeHandDetectionNode.
        // detect() and the package's own end-to-end test already exercise
        // successfully -- at the cost of a GPU -> CPU -> GPU round trip for
        // the depth values.
        guard let preprocessCommandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create the Zip Depth preprocess command buffer"
            )
        }
        preprocessCommandBuffer.label = "Zip Depth Preprocess \(modelSize.width)×\(modelSize.height)"

        try preprocessor.encode(
            inputTexture: inputImage.texture,
            textureTransform: inputImage.textureTransform,
            outputBuffer: modelInputBuffer,
            outputWidth: modelSize.width,
            outputHeight: modelSize.height,
            commandBuffer: preprocessCommandBuffer
        )

        preprocessCommandBuffer.commit()
        preprocessCommandBuffer.waitUntilCompleted()
        if let preprocessError = preprocessCommandBuffer.error
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Zip Depth preprocess failed: \(preprocessError.localizedDescription)"
            )
        }

        let depthValues = try model.run(inputBuffer: modelInputBuffer)
        depthValues.withUnsafeBytes { rawDepthValues in
            modelOutputBuffer.contents().copyMemory(
                from: rawDepthValues.baseAddress!,
                byteCount: rawDepthValues.count
            )
        }

        try postprocessor.encode(
            inputBuffer: modelOutputBuffer,
            modelWidth: modelSize.width,
            modelHeight: modelSize.height,
            outputTexture: outputImage.texture,
            outputWidth: presentationWidth,
            outputHeight: presentationHeight,
            commandBuffer: commandBuffer
        )

        // `commandBuffer` is Fabric's shared per-frame buffer -- this node
        // never waits on it, so it's still in flight when execute() returns.
        // GraphRendererTextureCache recycles a managed FabricImage's texture
        // the instant its last Swift reference drops (FabricImage.deinit ->
        // release() -> onRelease), with no regard for whether the GPU is
        // still using it. If nothing downstream keeps inputImage/outputImage
        // alive that long (e.g. this port's value gets replaced next frame
        // before this frame's GPU work retires), their textures can be
        // handed back out while `commandBuffer` is still writing/reading
        // them. Keep both alive until this buffer's GPU work actually
        // completes, matching MediaPipeHandDetectionNode's `[weak self,
        // image]` completion-handler capture on origin/feature/media-pipe-mps.
        commandBuffer.addCompletedHandler { [inputImage, outputImage] _ in
            withExtendedLifetime((inputImage, outputImage)) {}
        }

        self.outputDepthImage.send(outputImage)
    }

    private func setupComputeKernels()
    {
        self.preprocessor = try? ZipDepthPreprocessor(device: self.context.device)
        self.postprocessor = try? ZipDepthPostprocessor(device: self.context.device)
    }

    private func prepareModel(width: Int, height: Int) throws
    {
        guard self.model == nil || width != self.modelWidth || height != self.modelHeight else { return }

        let model = try ZipDepthMPSGraph(
            inputWidth: width,
            inputHeight: height,
            commandQueue: self.context.commandQueue
        )
        guard let inputBuffer = self.context.device.makeBuffer(
            length: model.inputBufferLength,
            options: .storageModePrivate
        ), let outputBuffer = self.context.device.makeBuffer(
            length: model.outputBufferLength,
            options: .storageModeShared
        ) else
        {
            throw FabricError(
                .execution(.outOfMemory),
                severity: .recoverable,
                message: "Could not allocate Zip Depth model buffers"
            )
        }

        inputBuffer.label = "Zip Depth RGB Input"
        // Shared, not private: model.run()'s [Float] result is copied in via
        // .contents() before the postprocess kernel reads it back on the GPU.
        outputBuffer.label = "Zip Depth Model Output"
        self.model = model
        self.modelInputBuffer = inputBuffer
        self.modelOutputBuffer = outputBuffer
        self.modelWidth = width
        self.modelHeight = height
    }

    private static func modelInputSize(
        presentationWidth: Int,
        presentationHeight: Int
    ) -> (width: Int, height: Int)
    {
        let shortSide = 384.0
        if presentationWidth <= presentationHeight
        {
            let scaledHeight = shortSide * Double(presentationHeight) / Double(presentationWidth)
            return (384, Self.nearestMultipleOf32(scaledHeight))
        }

        let scaledWidth = shortSide * Double(presentationWidth) / Double(presentationHeight)
        return (Self.nearestMultipleOf32(scaledWidth), 384)
    }

    private static func nearestMultipleOf32(_ value: Double) -> Int
    {
        max(32, Int((value / 32.0).rounded()) * 32)
    }
}
