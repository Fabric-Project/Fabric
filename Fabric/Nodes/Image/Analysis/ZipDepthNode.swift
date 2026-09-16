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
        self.drainCommandQueueBeforeReleasingModel()
        self.model = nil
        self.modelInputBuffer = nil
        self.modelOutputBuffer = nil
        self.modelWidth = 0
        self.modelHeight = 0
    }

    deinit
    {
        // stopExecution(renderer:) above is only invoked for subgraphs
        // (SubgraphNode, IteratorNode, DeferredSubgraphNode) and export
        // rendering -- closing a document window releases this node via
        // plain ARC deallocation (FabricDocument.deinit -> Graph.deinit ->
        // Node.teardown(), none of which have any GPU-completion
        // awareness), never through that method. deinit is the one hook
        // guaranteed to fire either way, so the drain has to happen here
        // too, not just there.
        self.drainCommandQueueBeforeReleasingModel()
    }

    // `model` wraps an MPSGraphExecutable, which owns its own GPU-resident
    // heap for intermediate tensors. Cheap insurance kept from when this
    // node was hitting `-[MTLDebugHeap setPurgeableState:]` crashes caused
    // by ZipDepthMPSGraph.encode() never calling MPSCommandBuffer.commit()
    // (fixed at the package level -- see its doc comment): committing and
    // waiting on one more, empty command buffer on the same queue drains it
    // before `model` gets released, guaranteeing every earlier command
    // buffer on this queue -- and its completion handling -- has finished.
    private func drainCommandQueueBeforeReleasingModel()
    {
        guard self.model != nil,
              let drainCommandBuffer = self.context.commandQueue.makeCommandBuffer() else { return }
        drainCommandBuffer.commit()
        drainCommandBuffer.waitUntilCompleted()
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

        // model.encode() writes modelOutputBuffer entirely on the GPU -- no
        // CPU readback. Root cause of every earlier crash on this path this
        // session: MPS-ZipDepth's encode() was never calling
        // MPSCommandBuffer.commit() on the MPSCommandBuffer wrapper it
        // creates internally (submit() always did; encode() was missing it)
        // -- relying instead on MPSGraphExecutable.encode(to:)'s
        // undocumented, conditional internal commitAndContinue behavior,
        // which is why three different crash mechanisms showed up rather
        // than the same one recurring. Fixed at the package level; see
        // ZipDepthMPSGraph.encode()'s doc comment.
        //
        // Kept on its own dedicated command buffer rather than Fabric's
        // shared per-frame `commandBuffer`: encode() commits whatever
        // MTLCommandBuffer it's given, and Fabric's shared buffer is still
        // being encoded into by other nodes this frame.
        guard let modelCommandBuffer = self.context.commandQueue.makeCommandBuffer() else
        {
            throw FabricError(
                .execution(.gpu),
                severity: .recoverable,
                message: "Could not create the Zip Depth model command buffer"
            )
        }
        modelCommandBuffer.label = "Zip Depth Model \(modelSize.width)×\(modelSize.height)"

        try preprocessor.encode(
            inputTexture: inputImage.texture,
            textureTransform: inputImage.textureTransform,
            outputBuffer: modelInputBuffer,
            outputWidth: modelSize.width,
            outputHeight: modelSize.height,
            commandBuffer: modelCommandBuffer
        )

        // Registered before model.encode(), since that call commits
        // modelCommandBuffer and Metal requires completion handlers to be
        // added before commit. Captures the specific model,
        // modelInputBuffer, and modelOutputBuffer instances used for *this*
        // call: with no CPU wait below, prepareModel() can reassign
        // self.model/self.modelInputBuffer/self.modelOutputBuffer on a
        // later frame (input aspect ratio change) while this frame's GPU
        // work is still in flight against the OLD instances.
        modelCommandBuffer.addCompletedHandler { [model, modelInputBuffer, modelOutputBuffer] commandBuffer in
            withExtendedLifetime((model, modelInputBuffer, modelOutputBuffer)) {}
            if let modelError = commandBuffer.error
            {
                print("Zip Depth model execution failed: \(modelError.localizedDescription)")
            }
        }

        try model.encode(
            inputBuffer: modelInputBuffer,
            outputBuffer: modelOutputBuffer,
            commandBuffer: modelCommandBuffer
        )
        // No explicit commit() here -- model.encode() commits
        // modelCommandBuffer itself. No CPU wait either: postprocessing
        // below is encoded onto Fabric's shared `commandBuffer`, committed
        // to the same MTLCommandQueue after this call returns -- Metal
        // orders command buffers on one queue by commit order and tracks
        // the read-after-write dependency on modelOutputBuffer across that
        // boundary automatically.

        commandBuffer.pushDebugGroup("Zip Depth \(modelSize.width)×\(modelSize.height)")
        defer { commandBuffer.popDebugGroup() }

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
        // the instant its last Swift reference drops, with no regard for
        // whether the GPU is still using it. Keep both alive until this
        // buffer's GPU work actually completes.
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
        // Private, not shared: model.encode() writes and the postprocess
        // kernel reads this entirely on the GPU, with no CPU-side copy.
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
