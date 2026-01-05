//
//  BaseComputeNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/29/25.
//

import Satin
import Metal
import simd

public class BaseTextureComputeProcessorNode: Node, NodeFileLoadingProtocol
{
    override public class var name: String { "Base Texture Compute" }
    override public class var nodeType: Node.NodeType { .Image(imageType: .BaseEffect) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    
    override public var name: String {
        guard let fileURL = self.url else {
            return BaseTextureComputeProcessorNode.name
        }
        
        return self.fileURLToName(fileURL: fileURL)
    }
    
    // Satin Compute
    public var compute: TextureComputeProcessor!
    private var pipelineURL: URL?
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputImage", NodePort<FabricImage>(name: "Image", kind: .Inlet)),
            ("outputImage", NodePort<FabricImage>(name: "Image", kind: .Outlet)),
        ]
    }

    public var inputImage:NodePort<FabricImage>  { port(named: "inputImage") }
    public var outputImage:NodePort<FabricImage> { port(named: "outputImage") }
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

        
        self.compute = TextureComputeProcessor(device: context.device,
                                      pipelineURL: url)
//        
        for param in self.compute.parameters.params {

            if let p = PortType.portForType(from:param)
            {
                self.addDynamicPort(p)
            }
        }
    }

    // MARK: - Execution
    override public func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        guard self.inputImage.valueDidChange,
              let inTex = self.inputImage.value?.texture,
              let outImage = context.graphRenderer?.newImage(withWidth: inTex.width, height: inTex.height, commandBuffer: commandBuffer),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder()
                
        else { return }
        
        // Input Texture to Compute
        self.compute.set(inTex, index: .Custom0)
        self.compute.set(outImage.texture, index: .Custom1)
    
        self.compute.update(computeEncoder)
        
        computeEncoder.endEncoding()
        
        self.outputImage.send(outImage)
    }

    private func fileURLToName(fileURL:URL) -> String
    {
        let nodeName =  fileURL.deletingPathExtension().lastPathComponent.replacing("ImageNode", with: "")

        return nodeName.titleCase
    }
}
