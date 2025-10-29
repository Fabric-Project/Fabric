//
//  BaseComputeNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/29/25.
//

import Satin
import Metal
import simd

public class BaseComputeNode: Node, NodeFileLoadingProtocol
{
    override public class var name: String { "Base Compute" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    
    
    override public var name: String {
        guard let fileURL = self.url else {
            return BaseEffectNode.name
        }
        
        return self.fileURLToName(fileURL: fileURL)
    }
    
    // Satin Compute
    public var system: TextureComputeSystem!
    private var pipelineURL: URL?
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<EquatableTexture>(name: "Image", kind: .Inlet)),
            ("outputImage", NodePort<EquatableTexture>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputImage:NodePort<EquatableTexture>  { port(named: "inputImage") }
    public var outputImage:NodePort<EquatableTexture> { port(named: "outputImage") }
    private var url:URL? = nil

    // MARK: - Init
    required public init(context: Context, fileURL: URL) throws
    {
        self.url = fileURL
        self.pipelineURL = fileURL
        super.init(context: context)
        setupProcessor(context: context)
    }
    
    public required init(context: Context)
    {
        fatalError("init(from:) has not been implemented")
    }
    
    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)
    }

    
    private func setupProcessor(context: Context)
    {
        guard let url = pipelineURL else { return }

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 512
        textureDescriptor.height = 512
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.allowGPUOptimizedContents = true
        
        
        system = TextureComputeSystem(device: context.device,
                                      pipelineURL: url,
                                      textureDescriptors: [textureDescriptor])
        
        
        
//        processor = TextureComputeProcessor(device: context.device,
//                                            pipelineURL: url,
//                                            live: false)
//        
        for param in self.system.parameters.params {

            if let p = PortType.portForType(from:param)
            {
                self.addDynamicPort(p)
            }
        }

        system.setup()
        
//        system.reset()

    }

    // MARK: - Execution
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard let inTex = inputImage.value?.texture,
              let device = context.graphRenderer?.device,
                let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        else { return }
        
        
        // Input Texture to Compute
        system.set(inTex, index: .Custom0)

//        computeEncoder.setTexture(inTex, index: 0)
        
        system.update(computeEncoder)

        computeEncoder.endEncoding()
        
        // If shader wrote into Custom1, output it
        if let outTex = system.computeTextures[.Custom1]
        {
            outputImage.send(EquatableTexture(texture: outTex))
        } else {
            outputImage.send(inputImage.value)
        }
    }
    
    private func fileURLToName(fileURL:URL) -> String {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ImageNode", with: "")

        return nodeName.titleCase
    }
}
