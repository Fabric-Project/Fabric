//
//  RenderInfoNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin
import Metal
import simd

public class ImageDimensions : Node
{
    public override class var name:String { "Image Dimensions" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Utility }
    public override class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    public override class var nodeTimeMode: Node.TimeMode { .None }
    public override class var nodeDescription: String { "Returns Image Dimensions in Pixels"}

    // Ports
    public let inputTexture:NodePort<FabricImage>
    public let outputResolution:NodePort<simd_float2>
    public override var ports: [Port] { [ self.inputTexture, self.outputResolution] + super.ports}
    
        
    public required init(context: Context)
    {
        self.inputTexture =  NodePort<FabricImage>(name: "Image" , kind: .Inlet)
        self.outputResolution =  NodePort<simd_float2>(name: "Resolution" , kind: .Outlet)

        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputTexturePort
        case outputResolutionPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputTexture, forKey: .inputTexturePort)
        try container.encode(self.outputResolution, forKey: .outputResolutionPort)

        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputTexture = try container.decode(NodePort<FabricImage>.self, forKey: .inputTexturePort)
        self.outputResolution =  try container.decode(NodePort<simd_float2>.self, forKey: .outputResolutionPort)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if self.inputTexture.valueDidChange
        {
            if let texture = self.inputTexture.value
            {
                let size = simd_float2(x:Float(texture.texture.width), y:Float(texture.texture.height))
                self.outputResolution.send(size)
            }
            else
            {
                self.outputResolution.send(nil)
            }
        }
        
    }
}
