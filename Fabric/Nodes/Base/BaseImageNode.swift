import Foundation
import Metal
import MetalKit
import Satin
import simd
import UniformTypeIdentifiers

open class BaseImageNode: Node, NodeFileLoadingProtocol
{
    open class var supportedContentTypes: [UTType] { [] }
    
    override open class var name: String { "Base Image" }
    override open class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override open class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override open class var nodeTimeMode: Node.TimeMode { .None }
    override open class var nodeDescription: String { "Image processing effect" }

    override public func deriveTitle() -> String { self.cachedFileURLName ?? Self.name }

    open class var sourceShaderName: String { "" }

    /// Where the class's shader ships. The default resolves `sourceShaderName`
    /// from Fabric's Shaders directory; a subclass in a plugin overrides this to
    /// its own bundle, which init and decode then resolve against.
    open class var sourceShaderURL: URL? {
        Bundle.module.url(forResource: sourceShaderName, withExtension: "metal", subdirectory: "Shaders")
    }

    open class var defaultImageInputCountHint: Int? { nil }

    /// Overrides shader-reflected image input discovery for nodes that bind
    /// additional textures internally rather than exposing them as ports.
    open class var fixedImageInputCount: Int? { nil }

    open class PostMaterial: SourceMaterial {}

    let postMaterial: PostMaterial
    let postProcessor: PostProcessEncoder

    private var url: URL? = nil
    private var cachedFileURLName: String?
    private var lastKnownInputCount: Int = 1
    private var cachedImageInputPorts: [NodePort<FabricImage>]?

    /// What the shader gives the node: how many images it takes, and the
    /// uniforms that become parameter ports. Nil until the shader has been
    /// read, when the node has its registered ports alone. A shader that stops
    /// compiling leaves the last one standing, ports and wires with it.
    private var shaderInterface: ShaderInterface?

    private struct ShaderInterface
    {
        let imageInputCount: Int
        let materialParameters: [any Parameter]
    }
    private lazy var inputTextureTransformBuffer = StructBuffer<simd_float4x4>(device: self.context.device,
                                                                               count: 25,
                                                                               label: "BaseImageNode Input Texture Transforms")

    enum CodingKeys: String, CodingKey
    {
        case effectPath
        case baseImageNodeVersion
        case lastKnownInputCount
    }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("outputImage0", NodePort<FabricImage>(name: "Image", kind: .Outlet, description: "Output image")),
        ]
    }

    public var outputTexturePort: NodePort<FabricImage> {
        if let connected = self.outputImagePorts().first(where: { $0.connections.isEmpty == false }) {
            return connected
        }

        if let canonical: NodePort<FabricImage> = self.findPort(named: "outputImage0") {
            return canonical
        }

        if let legacy: NodePort<FabricImage> = self.findPort(named: "outputTexturePort") {
            return legacy
        }

        if let fallback = self.outputImagePorts().first {
            return fallback
        }

        fatalError("BaseImageNode requires at least one image outlet")
    }

    override public var nodeExecutionMode: ExecutionMode {
        self.currentImageInputCount == 0 ? .Provider : .Processor
    }

    public var currentImageInputCount: Int {
        self.imageInputPorts().count
    }

    public required init(context: Context, fileURL: URL) throws {
        self.url = fileURL
        self.cachedFileURLName = Self.fileURLToName(fileURL: fileURL)

        let material = PostMaterial(context:context, pipelineURL: fileURL)

        self.postMaterial = material
        self.postProcessor = PostProcessEncoder(context: context,
                                                material: material,
                                                depthPixelFormat: .invalid,
                                                stencilPixelFormat: .invalid,
                                                depthStoreAction: .dontCare,
                                                stencilStoreAction: .dontCare,
                                                frameBufferOnly: false)

        super.init(context: context)

        self.postInit()

        self.postSetupSynchronizePorts()
    }

    public required init(context: Context) {
        let shaderURL = Self.sourceShaderURL

        let material = PostMaterial(context:context, pipelineURL: shaderURL!)

        self.postMaterial = material
        self.postProcessor = PostProcessEncoder(context: context,
                                                material: material,
                                                depthPixelFormat: .invalid,
                                                stencilPixelFormat: .invalid,
                                                depthStoreAction: .dontCare,
                                                stencilStoreAction: .dontCare,
                                                frameBufferOnly: false)

        super.init(context: context)

        self.postInit()

        self.postSetupSynchronizePorts()
    }
    
    public func setFileURL(_ url: URL) {
        let cachedName = Self.fileURLToName(fileURL: url)
        let shouldUpdatePipeline = self.url != url
        guard shouldUpdatePipeline || self.cachedFileURLName != cachedName else { return }

        self.url = url
        self.cachedFileURLName = cachedName
        self.updatePostProcessorLabel()
        self.subtitleSubject.send()

        guard shouldUpdatePipeline else { return }

        if let sourceShader = self.postMaterial.shader as? SourceShader {
            sourceShader.pipelineURL = url
            sourceShader.reloadFromSource()
        }

        // New shader may expose a different set of uniforms.
        self.declareShaderInterface(imageInputCount: self.shaderInterface?.imageInputCount ?? self.lastKnownInputCount)
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let context = decoder.context?.documentContext as? Context else {
            fatalError("Required Decode Context Not set")
        }

        let decodedEffectPath = try container.decodeIfPresent(String.self, forKey: .effectPath)

        if let path = decodedEffectPath {
            if let shaderURL = Self.resolveBundleResource(path: path) {
                self.url = shaderURL
                self.cachedFileURLName = Self.fileURLToName(fileURL: shaderURL)

                let material = PostMaterial(context:context, pipelineURL: shaderURL)

                self.postMaterial = material
                self.postProcessor = PostProcessEncoder(context:context,
                                                        material: material,
                                                        depthPixelFormat: .invalid,
                                                        stencilPixelFormat: .invalid,
                                                        depthStoreAction: .dontCare,
                                                        stencilStoreAction: .dontCare,
                                                        frameBufferOnly: false)
            }
            else {
                self.cachedFileURLName = nil

                let shaderURL = Self.sourceShaderURL

                let material = PostMaterial(context:context,pipelineURL: shaderURL!)

                self.postMaterial = material
                self.postProcessor = PostProcessEncoder(context:context,
                                                        material: material,
                                                        depthPixelFormat: .invalid,
                                                        stencilPixelFormat: .invalid,
                                                        depthStoreAction: .dontCare,
                                                        stencilStoreAction: .dontCare,
                                                        frameBufferOnly: false)
            }
        }
        else {
            self.cachedFileURLName = nil

            let shaderURL = Self.sourceShaderURL

            let material = PostMaterial(context:context,pipelineURL: shaderURL!)

            self.postMaterial = material
            self.postProcessor = PostProcessEncoder(context:context,
                                                    material: material,
                                                    depthPixelFormat: .invalid,
                                                    stencilPixelFormat: .invalid,
                                                    depthStoreAction: .dontCare,
                                                    stencilStoreAction: .dontCare,
                                                    frameBufferOnly: false)
        }

        self.lastKnownInputCount = try container.decodeIfPresent(Int.self, forKey: .lastKnownInputCount)
            ?? Self.defaultImageInputCountHint
            ?? Self.defaultInputCountForPath(decodedEffectPath, fallback: 1)


        try super.init(from: decoder)

        self.postInit()
        
        self.postSetupSynchronizePorts()
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let url = self.url {
            try container.encodeIfPresent(Self.bundleRelativeResourcePath(for: url), forKey: .effectPath)
        }

        try container.encode(1, forKey: .baseImageNodeVersion)
        try container.encode(self.currentImageInputCount, forKey: .lastKnownInputCount)

        try super.encode(to: encoder)
    }

    private func postInit()
    {
        self.updatePostProcessorLabel()
    }

    private func updatePostProcessorLabel()
    {
        self.postProcessor.label = self.title + " Post Processor"
    }
    
    /// Reads the shader's interface and brings the ports to it.
    open func postSetupSynchronizePorts() {
        let inferredInputCount = Self.fixedImageInputCount
            ?? self.inferInputCountFromShader()
            ?? self.lastKnownInputCount
        self.lastKnownInputCount = max(0, inferredInputCount)

        self.declareShaderInterface(imageInputCount: self.lastKnownInputCount)
    }

    private func declareShaderInterface(imageInputCount: Int) {
        let offLimits = self.offLimitsLabels()
        self.shaderInterface = ShaderInterface(imageInputCount: imageInputCount,
                                               materialParameters: self.postMaterial.parameters.params.filter { !offLimits.contains($0.label) })

        // The shader declares the node's ports again; any the document kept
        // while it could not go now.
        self.discardUndeclaredSnapshotPorts()
        self.reconcilePorts()
        self.bindMaterialParameters()
    }

    /// Image inlets first, in input order; then the other inlets, the
    /// generator's Width and Height among them; then the shader's uniforms;
    /// then the outlets.
    override open func declaredPorts() -> [PortDeclaration] {
        let registered = super.declaredPorts()
        guard let shaderInterface else { return registered }

        let isImageInlet: (PortDeclaration) -> Bool = { $0.kind == .Inlet && $0.portType == .Image && $0.isParameterPort != true }
        let imageInlets = (registered.filter(isImageInlet) + (0..<shaderInterface.imageInputCount).map(Self.imageInputDeclaration))
            .enumerated()
            .sorted { lhs, rhs in
                let lhsKey = Self.imagePortSortKey(forName: lhs.element.name)
                let rhsKey = Self.imagePortSortKey(forName: rhs.element.name)
                return lhsKey == rhsKey ? lhs.offset < rhs.offset : lhsKey < rhsKey
            }
            .map(\.element)
        let otherInlets = registered.filter { $0.kind == .Inlet && !isImageInlet($0) }
        let resolution = shaderInterface.imageInputCount == 0 ? Self.generatorResolutionPorts.map { spec in
            PortDeclaration(registryKey: spec.label,
                            port: ParameterPort(parameter: IntParameter(spec.label, spec.defaultValue, 1, 8192, .inputfield, spec.description)))
        } : []
        // A uniform's port made on an id gives the material's parameter that id
        // too, so the two stay one.
        let uniforms = shaderInterface.materialParameters.compactMap { parameter in
            PortType.port(for: parameter).map { port in
                PortDeclaration(registryKey: parameter.label,
                                kind: port.kind,
                                portType: port.portType,
                                name: port.name,
                                description: port.portDescription,
                                isParameterPort: true) { id in PortType.port(for: parameter, id: id) ?? port }
            }
        }
        let outlets = registered.filter { $0.kind == .Outlet }

        return imageInlets + otherInlets + resolution + uniforms + outlets
    }

    /// A uniform's port stands for the material's parameter, which a shader
    /// reload makes anew.
    private func bindMaterialParameters() {
        for parameter in self.shaderInterface?.materialParameters ?? [] {
            guard let port: Port = self.findPort(named: parameter.label),
                  let current = port.parameter,
                  current !== parameter
            else { continue }

            self.replaceParameterOfPort(port, withParam: parameter)
        }
    }

    private func outputImagePorts() -> [NodePort<FabricImage>] {
        self.ports.compactMap { port -> NodePort<FabricImage>? in
            guard port.kind == .Outlet,
                  port.portType == .Image,
                  port.parameter == nil else {
                return nil
            }

            return port as? NodePort<FabricImage>
        }
    }

    private func defaultInputCountForFilePath() -> Int {
        guard let url else {
            return Self.defaultImageInputCountHint ?? 1
        }
        return Self.defaultInputCountForPath(url.path(percentEncoded: false), fallback: Self.defaultImageInputCountHint ?? 1)
    }

    private static func defaultInputCountForPath(_ path: String?, fallback: Int) -> Int {
        guard let path else { return fallback }
        if path.localizedStandardContains("EffectsTwoChannel") {
            return 2
        }
        if path.localizedStandardContains("EffectsThreeChannel") {
            return 3
        }
        if path.localizedStandardContains("Effects/Generator") || path.localizedStandardContains("Effects/ShapeGenerator") {
            return 0
        }
        return fallback
    }

    private func inferInputCountFromShader() -> Int? {
        guard let shader = self.postMaterial.shader as? SourceShader else {
            return nil
        }

        if shader.pipelineError != nil {
            return nil
        }

        let customIndices = shader.fragmentTextureBindingIsUsed
            .map(\.rawValue)
            .filter { $0 >= FragmentTextureIndex.Custom0.rawValue && $0 <= FragmentTextureIndex.Custom24.rawValue }

        guard let maxIndex = customIndices.max() else {
            return 0
        }

        return max(0, maxIndex + 1)
    }

    private static func imageInputDeclaration(index: Int) -> PortDeclaration {
        let label = index == 0 ? "Image" : "Image \(index + 1)"
        return PortDeclaration(registryKey: label,
                               port: NodePort<FabricImage>(name: label,
                                                           kind: .Inlet,
                                                           description: "Input image \(index + 1)"))
    }

    func imageInputPorts() -> [NodePort<FabricImage>] {
        if let cachedImageInputPorts { return cachedImageInputPorts }

        let ports = self.ports.compactMap { port -> NodePort<FabricImage>? in
            guard port.kind == .Inlet,
                  port.portType == .Image,
                  port.parameter == nil else {
                return nil
            }

            return port as? NodePort<FabricImage>
        }

        let sorted = ports.enumerated().sorted { lhs, rhs in
            let lhsKey = Self.imagePortSortKey(forName: lhs.element.name)
            let rhsKey = Self.imagePortSortKey(forName: rhs.element.name)
            return lhsKey == rhsKey ? lhs.offset < rhs.offset : lhsKey < rhsKey
        }.map(\.element)
        self.cachedImageInputPorts = sorted
        return sorted
    }

    override func invalidatePortCaches() {
        super.invalidatePortCaches()
        self.cachedImageInputPorts = nil
    }

    private static func imagePortSortKey(forName name: String) -> Int {
        if let index = Self.extractTrailingInteger(from: name) {
            return index
        }

        if name == "Image" || name == "inputTexturePort" {
            return 0
        }

        if name == "inputTexture2Port" { return 1 }
        if name == "inputTexture3Port" { return 2 }

        return 10_000
    }

    private static func extractTrailingInteger(from text: String) -> Int? {
        let digits = text.reversed().prefix { $0.isNumber }
        guard digits.isEmpty == false else { return nil }
        let value = String(digits.reversed())
        return Int(value).map { max(0, $0 - 1) }
    }

    /// Ports the base class declares for generator nodes (image input count
    /// == 0), whose labels no uniform can take.
    private static let generatorResolutionPorts: [(label: String, defaultValue: Int, description: String)] = [
        ("Width",  512, "Output image width in pixels"),
        ("Height", 512, "Output image height in pixels"),
    ]

    private func resolutionPort(label: String) -> ParameterPort<Int>? {
        self.ports.first(where: { $0.parameter?.label == label }) as? ParameterPort<Int>
    }

    func inputImage(at index: Int) -> FabricImage? {
        let ports = self.imageInputPorts()
        guard index >= 0, index < ports.count else {
            return nil
        }

        return ports[index].value
    }

    /// Labels a uniform cannot take: the registered parameters' and the
    /// generator's Width and Height.
    private func offLimitsLabels() -> Set<String> {
        let declared = Self.registerPorts(context: self.context).compactMap { $0.port.parameter?.label }
        let baseManaged = Self.generatorResolutionPorts.map { $0.label }
        return Set(declared).union(baseManaged)
    }

    public override func execute(renderer:GraphRenderer, executionInfo:GraphExecutionInfo, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws
    {
        let shouldExecute = self.ports.reduce(false) { partialResult, next in
            partialResult || next.valueDidChange
        }

        commandBuffer.pushDebugGroup(self.debugDescription + " Execute")
        defer { commandBuffer.popDebugGroup() }
        
        if self.currentImageInputCount == 0 {
            guard let widthPort = self.resolutionPort(label: "Width"),
                  let heightPort = self.resolutionPort(label: "Height") else {
                self.outputTexturePort.send(nil)
                return
            }

            let width = max(1, widthPort.value ?? 512)
            let height = max(1, heightPort.value ?? 512)

            self.postProcessor.resize(size: (width: Float(width), height: Float(height)), scaleFactor: 1)

            let outImage = try renderer.newImage(withWidth: width, height: height)

            let renderPassDesc = MTLRenderPassDescriptor()
            renderPassDesc.colorAttachments[0].texture = outImage.texture
            
            self.postProcessor.mesh.preDraw = nil
            self.postProcessor.draw(renderPassDescriptor: renderPassDesc, commandBuffer: commandBuffer)
            self.outputTexturePort.send(outImage)
            return
        }

        guard shouldExecute else {
            return
        }

        guard let inputImage = self.inputImage(at: 0)
        else {
            self.outputTexturePort.send(nil)
            return
        }
        
        let inputTexture0 = inputImage.texture
        let inputImages = self.imageInputPorts().map(\.value)
        let textures = inputImages.map { $0?.texture }
        let outputWidth = Int(inputImage.presentationSize.width.rounded())
        let outputHeight = Int(inputImage.presentationSize.height.rounded())

        let outImage = try renderer.newImage(withWidth: outputWidth, height: outputHeight)

        let transforms = inputImages.map { $0?.textureTransform ?? inputImage.textureTransform }
        self.inputTextureTransformBuffer.update(data: transforms)
        self.postMaterial.set(self.inputTextureTransformBuffer, index: FragmentBufferIndex.Custom10)
        outImage.textureTransform = matrix_identity_float4x4

        self.postProcessor.mesh.preDraw = { renderEncoder in
            for (index, texture) in textures.enumerated() {
                let fallbackTexture = texture ?? inputTexture0
                renderEncoder.setFragmentTexture(fallbackTexture, index: FragmentTextureIndex.Custom0.rawValue + index)
            }
        }

        self.postProcessor.resize(size: (width: Float(outputWidth), height: Float(outputHeight)), scaleFactor: 1)

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = outImage.texture

        self.postProcessor.draw(renderPassDescriptor: renderPassDesc, commandBuffer: commandBuffer)
        self.outputTexturePort.send(outImage)
    }

    private static func fileURLToName(fileURL: URL) -> String {
        let nodeName = fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")
        return nodeName.titleCase
    }
}
