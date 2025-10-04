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

    public let inputFilePathParam:StringParameter
    public override var inputParameters: [any Parameter] { [self.inputFilePathParam] + super.inputParameters}

    
    // Ports - Skip Geom and Material
    public override var ports: [any NodePortProtocol] { [
                                         outputMesh] + super.ports}

    private var mesh: Object? = nil
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil

    public required init(context: Context)
    {
        self.inputFilePathParam = StringParameter("Model Path", "", [], .filepicker)
        self.textureLoader = MTKTextureLoader(device: context.device)
        
        super.init(context: context)
    }
    
    enum CodingKeys : String, CodingKey
    {
        case inputFilePathParameter
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.inputFilePathParam, forKey: .inputFilePathParameter)
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.inputFilePathParam = try container.decode(StringParameter.self, forKey:.inputFilePathParameter)
        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from: decoder)
        
        self.loadModelFromInputValue()
    }
    
    override public func evaluate(object: Object, atTime: TimeInterval) -> Bool {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        if self.inputFilePathParam.valueDidChange
        {
            self.loadModelFromInputValue()
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if let mesh = self.mesh
        {
            let shouldOuput = self.evaluate(object: mesh, atTime: context.timing.time)

            self.outputMesh.send(mesh)
        }
        else
        {
            self.outputMesh.send(nil)
        }
    }
    
    private func loadModelFromInputValue()
    {
        if  self.inputFilePathParam.value.isEmpty == false && self.url != URL(string: self.inputFilePathParam.value)
        {
            self.url = URL(string: self.inputFilePathParam.value)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                
                self.mesh = loadAsset(url:self.url!, textureLoader: self.textureLoader)
            }
            else
            {
                self.mesh = nil
                print("wtf")
            }
        }
    }

}

