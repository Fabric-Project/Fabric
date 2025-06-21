//
//  ModelMeshNode.swift
//  Fabric
//
//  Created by Anton Marini on 5/25/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class ModelMeshNode : MeshNode
{
    public override class var name:String { "Model Mesh" }

    public let inputModelPath:StringParameter
    public override var inputParameters: [any Parameter] { super.inputParameters + [self.inputModelPath]}

    
    // Ports - Skip Geom and Material
    public override var ports: [any NodePortProtocol] { [
                                         outputMesh] }

    private var mesh: Object? = nil
    private var textureLoader:MTKTextureLoader

    public required init(context: Context)
    {
        self.inputModelPath = StringParameter("Model Path", "", [], .filepicker)
        self.textureLoader = MTKTextureLoader(device: context.device)

        self.mesh = loadAsset(url: URL(fileURLWithPath: "/Users/vade/Downloads/chair_swan.usdz"), textureLoader: self.textureLoader)
        
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputModelPathParameter
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.inputModelPath, forKey: .inputModelPathParameter)
        try super.encode(to: encoder)

    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputModelPath = try container.decode(StringParameter.self, forKey:.inputModelPathParameter)
        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from: decoder)
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let mesh = mesh
        {
            self.evaluate(object: mesh, atTime: context.timing.time)

            self.outputMesh.send(mesh)
        }
        else
        {
            self.outputMesh.send(nil)
        }
    }
}

