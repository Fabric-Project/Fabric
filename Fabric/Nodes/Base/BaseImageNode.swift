import Foundation
import Metal
import MetalKit
import Satin
import simd
import UniformTypeIdentifiers

public class BaseImageNode: Node, NodeFileLoadingProtocol
{
    public static var supportedContentTypes: [UTType] { [] }
    
    override public class var name: String { "Base Image" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    override public var name: String {
        if let displayName {
            return displayName
        }

        guard let fileURL = self.url else {
            return Self.name
        }

        return self.fileURLToName(fileURL: fileURL)
    }

    open class var sourceShaderName: String { "" }
    open class var defaultImageInputCountHint: Int? { nil }
    open class var preserveDecodedImageInputPortsOnDecode: Bool { false }

    open class PostMaterial: SourceMaterial {}

    let postMaterial: PostMaterial
    let postProcessor: PostProcessor

    @ObservationIgnored private var url: URL? = nil
    @ObservationIgnored private var lastKnownInputCount: Int = 1
    @ObservationIgnored private var cachedImageInputPorts: [NodePort<FabricImage>] = []

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

    @ObservationIgnored override public var nodeExecutionMode: ExecutionMode {
        self.currentImageInputCount == 0 ? .Provider : .Processor
    }

    public var currentImageInputCount: Int {
        self.cachedImageInputPorts.count
    }

    public required init(context: Context, fileURL: URL) throws {
        self.url = fileURL

        let material = PostMaterial(pipelineURL: fileURL)
        material.context = context

        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)

        self.postProcessor.renderer.depthLoadAction = .dontCare
        self.postProcessor.renderer.depthStoreAction = .dontCare
        self.postProcessor.renderer.stencilLoadAction = .dontCare
        self.postProcessor.renderer.stencilStoreAction = .dontCare

        super.init(context: context)

        self.postSetupSynchronizePorts(allowReplace: true)
    }

    required init(context: Context) {
        let bundle = Bundle.module
        let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")

        let material = PostMaterial(pipelineURL: shaderURL!)
        material.context = context

        self.postMaterial = material
        self.postProcessor = PostProcessor(context: context,
                                           material: material,
                                           frameBufferOnly: false)

        self.postProcessor.renderer.depthLoadAction = .dontCare
        self.postProcessor.renderer.depthStoreAction = .dontCare
        self.postProcessor.renderer.stencilLoadAction = .dontCare
        self.postProcessor.renderer.stencilStoreAction = .dontCare

        super.init(context: context)

        self.postSetupSynchronizePorts(allowReplace: false,
                                       preserveExistingImageInputPorts: Self.preserveDecodedImageInputPortsOnDecode)
    }
    
    public func setFileURL(_ url: URL) {
        // no op in Base Image Node
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let decodeContext = decoder.context else {
            fatalError("Required Decode Context Not set")
        }

        let decodedEffectPath = try container.decodeIfPresent(String.self, forKey: .effectPath)

        if let path = decodedEffectPath {
            let bundle = Bundle.module
            if let shaderURL = bundle.resourceURL?.appendingPathComponent(path) {
                self.url = shaderURL

                let material = PostMaterial(pipelineURL: shaderURL)
                material.context = decodeContext.documentContext

                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
            else {
                let bundle = Bundle.module
                let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")

                let material = PostMaterial(pipelineURL: shaderURL!)
                material.context = decodeContext.documentContext

                self.postMaterial = material
                self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                                   material: material,
                                                   frameBufferOnly: false)
            }
        }
        else {
            let bundle = Bundle.module
            let shaderURL = bundle.url(forResource: Self.sourceShaderName, withExtension: "metal", subdirectory: "Shaders")

            let material = PostMaterial(pipelineURL: shaderURL!)
            material.context = decodeContext.documentContext

            self.postMaterial = material
            self.postProcessor = PostProcessor(context: decodeContext.documentContext,
                                               material: material,
                                               frameBufferOnly: false)
        }

        self.lastKnownInputCount = try container.decodeIfPresent(Int.self, forKey: .lastKnownInputCount)
            ?? Self.defaultImageInputCountHint
            ?? Self.defaultInputCountForPath(decodedEffectPath, fallback: 1)

        self.postProcessor.renderer.depthLoadAction = .dontCare
        self.postProcessor.renderer.depthStoreAction = .dontCare
        self.postProcessor.renderer.stencilLoadAction = .dontCare
        self.postProcessor.renderer.stencilStoreAction = .dontCare

        try super.init(from: decoder)

        self.postSetupSynchronizePorts(allowReplace: false,
                                       preserveExistingImageInputPorts: Self.preserveDecodedImageInputPortsOnDecode)
    }

    override public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let url = self.url {
            let last3 = url.pathComponents.suffix(3)
            let path = last3.joined(separator: "/")
            try container.encode(path, forKey: .effectPath)
        }

        try container.encode(1, forKey: .baseImageNodeVersion)
        try container.encode(self.currentImageInputCount, forKey: .lastKnownInputCount)

        try super.encode(to: encoder)
    }

    open func postSetupSynchronizePorts(allowReplace: Bool, preserveExistingImageInputPorts: Bool = false) {
        self.refreshImageInputPortCache()
        let existingImageInputCount = self.cachedImageInputPorts.count

        let inferredInputCount = self.inferInputCountFromShader() ?? self.lastKnownInputCount
        let resolvedInputCount: Int
        if preserveExistingImageInputPorts && existingImageInputCount > 0 {
            resolvedInputCount = max(existingImageInputCount, inferredInputCount)
        }
        else {
            resolvedInputCount = inferredInputCount
        }

        self.lastKnownInputCount = max(0, resolvedInputCount)

        self.syncImageInputPorts(targetCount: self.lastKnownInputCount, allowReplace: allowReplace)
        self.synchronizeOutputImagePorts()

        self.syncGeneratorResolutionPorts()

        self.syncDynamicParameterPortsFromMaterial()
        self.normalizePortOrderForDisplay()
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

    private func shouldPreferOutputPort(_ port: NodePort<FabricImage>) -> Int {
        if port.connections.isEmpty == false {
            return 0
        }

        if port.name == "outputImage0" {
            return 1
        }

        if port.name == "outputTexturePort" {
            return 2
        }

        if port.name == "outputImage" {
            return 3
        }

        return 10
    }

    private func synchronizeOutputImagePorts() {
        var imageOutputs = self.outputImagePorts()
        guard imageOutputs.count > 1 else { return }

        let canonicalPort = (self.findPort(named: "outputImage0") as? NodePort<FabricImage>)
            ?? imageOutputs.min { lhs, rhs in
                let lhsRank = self.shouldPreferOutputPort(lhs)
                let rhsRank = self.shouldPreferOutputPort(rhs)
                if lhsRank == rhsRank {
                    return lhs.connections.count > rhs.connections.count
                }
                return lhsRank < rhsRank
            }

        guard let canonicalPort else { return }

        for legacyPort in imageOutputs where legacyPort.id != canonicalPort.id {
            if legacyPort.published {
                canonicalPort.published = true
            }

            let inboundConnections = legacyPort.connections.filter { $0.kind == .Inlet }
            for inlet in inboundConnections {
                canonicalPort.connect(to: inlet)
            }
        }

        imageOutputs = self.outputImagePorts()
        for legacyPort in imageOutputs where legacyPort.id != canonicalPort.id {
            if legacyPort.connections.isEmpty {
                self.removePort(legacyPort)
            }
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

    private func makeInputPort(index: Int) -> NodePort<FabricImage> {
        let label = index == 0 ? "Image" : "Image \(index + 1)"
        return NodePort<FabricImage>(name: label,
                                     kind: .Inlet,
                                     description: "Input image \(index + 1)")
    }

    func imageInputPorts() -> [NodePort<FabricImage>] {
        self.cachedImageInputPorts
    }

    private func refreshImageInputPortCache() {
        let ports = self.ports.compactMap { port -> NodePort<FabricImage>? in
            guard port.kind == .Inlet,
                  port.portType == .Image,
                  port.parameter == nil else {
                return nil
            }

            return port as? NodePort<FabricImage>
        }

        self.cachedImageInputPorts = ports.sorted { lhs, rhs in
            self.imagePortSortKey(for: lhs) < self.imagePortSortKey(for: rhs)
        }
    }

    private func imagePortSortKey(for port: Port) -> Int {
        if let index = Self.extractTrailingInteger(from: port.name) {
            return index
        }

        if port.name == "Image" || port.name == "inputTexturePort" {
            return 0
        }

        if port.name == "inputTexture2Port" { return 1 }
        if port.name == "inputTexture3Port" { return 2 }

        return 10_000
    }

    private static func extractTrailingInteger(from text: String) -> Int? {
        let digits = text.reversed().prefix { $0.isNumber }
        guard digits.isEmpty == false else { return nil }
        let value = String(digits.reversed())
        return Int(value).map { max(0, $0 - 1) }
    }

    private func syncImageInputPorts(targetCount: Int, allowReplace: Bool) {
        let clampedCount = max(0, targetCount)
        self.refreshImageInputPortCache()
        let existingPorts = self.cachedImageInputPorts

        if allowReplace == false {
            if existingPorts.count < clampedCount {
                for index in existingPorts.count..<clampedCount {
                    let newPort = self.makeInputPort(index: index)
                    self.addDynamicPort(newPort, name: newPort.name)
                }
            }
            else if existingPorts.count > clampedCount {
                for index in stride(from: existingPorts.count - 1, through: clampedCount, by: -1) {
                    self.removePort(existingPorts[index])
                }
            }
            self.refreshImageInputPortCache()
            return
        }

        for port in existingPorts {
            self.removePort(port)
        }

        for index in 0..<clampedCount {
            let newPort = self.makeInputPort(index: index)
            self.addDynamicPort(newPort, name: newPort.name)
        }
        self.refreshImageInputPortCache()
    }

    private func syncGeneratorResolutionPorts() {
        let shouldHaveResolutionPorts = self.currentImageInputCount == 0
        let widthPort = self.resolutionPort(label: "Width")
        let heightPort = self.resolutionPort(label: "Height")

        if shouldHaveResolutionPorts {
            if widthPort == nil {
                let width = ParameterPort(parameter: IntParameter("Width", 512, 1, 8192, .inputfield, "Output image width in pixels"))
                self.addDynamicPort(width, name: width.name)
            }

            if heightPort == nil {
                let height = ParameterPort(parameter: IntParameter("Height", 512, 1, 8192, .inputfield, "Output image height in pixels"))
                self.addDynamicPort(height, name: height.name)
            }
        }
        else {
            if let widthPort {
                self.removePort(widthPort)
            }

            if let heightPort {
                self.removePort(heightPort)
            }
        }
    }

    private func resolutionPort(label: String) -> ParameterPort<Int>? {
        self.ports.first(where: { $0.parameter?.label == label }) as? ParameterPort<Int>
    }

    func inputImageTexture(at index: Int) -> MTLTexture? {
        let ports = self.imageInputPorts()
        guard index >= 0, index < ports.count else {
            return nil
        }

        return ports[index].value?.texture
    }

    private func syncDynamicParameterPortsFromMaterial() {
        let materialParams = self.postMaterial.parameters.params
        let labels = Set(materialParams.map(\.label))

        let portsToRemove = self.ports.filter { port in
            guard let parameter = port.parameter else {
                return false
            }

            if parameter.label == "Width" || parameter.label == "Height" {
                return false
            }

            return !labels.contains(port.name)
        }

        for port in portsToRemove {
            self.removePort(port)
        }

        for param in materialParams {
            if let port = self.ports.first(where: { $0.name == param.label }) {
                self.replaceParameterOfPort(port, withParam: param)
            }
            else if let dynamicPort = PortType.portForType(from: param) {
                self.addDynamicPort(dynamicPort)
            }
        }
    }

    private func normalizePortOrderForDisplay()
    {
        let currentPorts = self.ports
        let indexByID = Dictionary(uniqueKeysWithValues: currentPorts.enumerated().map { ($1.id, $0) })

        let reordered = currentPorts.sorted { lhs, rhs in
            let lhsKey = self.portSortKey(lhs, indexByID: indexByID)
            let rhsKey = self.portSortKey(rhs, indexByID: indexByID)
            if lhsKey.group == rhsKey.group {
                return lhsKey.position < rhsKey.position
            }
            return lhsKey.group < rhsKey.group
        }

        if zip(currentPorts, reordered).allSatisfy({ $0.id == $1.id }) {
            return
        }

        self.reorderPorts(reordered)
        self.refreshImageInputPortCache()
    }

    private func portSortKey(_ port: Port, indexByID: [UUID: Int]) -> (group: Int, position: Int) {
        let originalIndex = indexByID[port.id] ?? 0

        if port.kind == .Inlet && port.direction == .Horizontal {
            if port.portType == .Image {
                return (0, self.imagePortSortKey(for: port))
            }
            return (1, originalIndex)
        }

        return (2, originalIndex)
    }

    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let anyPortChanged = self.ports.reduce(false) { partialResult, next in
            partialResult || next.valueDidChange
        }

        if self.currentImageInputCount == 0 {
            guard let widthPort = self.resolutionPort(label: "Width"),
                  let heightPort = self.resolutionPort(label: "Height") else {
                self.outputTexturePort.send(nil)
                return
            }

            let width = max(1, widthPort.value ?? 512)
            let height = max(1, heightPort.value ?? 512)

            self.postProcessor.renderer.size.width = Float(width)
            self.postProcessor.renderer.size.height = Float(height)

            guard let outImage = context.graphRenderer?.newImage(withWidth: width, height: height) else {
                self.outputTexturePort.send(nil)
                return
            }

            let renderPassDesc = MTLRenderPassDescriptor()
            renderPassDesc.colorAttachments[0].texture = outImage.texture
            self.postProcessor.mesh.preDraw = nil
            self.postProcessor.draw(renderPassDescriptor: renderPassDesc, commandBuffer: commandBuffer)
            self.outputTexturePort.send(outImage)
            return
        }

        guard anyPortChanged else {
            return
        }

        guard let inputTexture0 = self.inputImageTexture(at: 0) else {
            self.outputTexturePort.send(nil)
            return
        }

        guard let outImage = context.graphRenderer?.newImage(withWidth: inputTexture0.width, height: inputTexture0.height) else {
            self.outputTexturePort.send(nil)
            return
        }

        let textures = self.imageInputPorts().map { $0.value?.texture }

        self.postProcessor.mesh.preDraw = { renderEncoder in
            for (index, texture) in textures.enumerated() {
                let fallbackTexture = texture ?? inputTexture0
                renderEncoder.setFragmentTexture(fallbackTexture, index: FragmentTextureIndex.Custom0.rawValue + index)
            }
        }

        self.postProcessor.renderer.size.width = Float(inputTexture0.width)
        self.postProcessor.renderer.size.height = Float(inputTexture0.height)

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = outImage.texture

        self.postProcessor.draw(renderPassDescriptor: renderPassDesc, commandBuffer: commandBuffer)
        self.outputTexturePort.send(outImage)
    }

    private func fileURLToName(fileURL: URL) -> String {
        let nodeName = fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")
        return nodeName.titleCase
    }
}
