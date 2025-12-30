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

public class InstancedModelMeshNode : InstancedMeshNode
{
    public override class var name:String { "Instanced Model Mesh" }
    public override class var nodeType:Node.NodeType { .Object(objectType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load an 3D model file from disk, rendering it to the scene multiple times via instances"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {

        // We prune Geom and Material since we dont really let you fuck with them for now
        let ports = super.registerPorts(context: context).filter({ (name: String, port: Port) in
            !(port.name == "Geometry" || port.name == "Material")
        })

        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker))),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil

    override public func getObject() -> Object? {
        return model
    }
    
    private var model: Object? = nil
    {
        didSet
        {
            // Relying on side effects - this triggers
            self.graph?.syncNodesToScene(removingObject:oldValue)
        }
    }
    
    public required init(context: Context)
    {
        self.textureLoader = MTKTextureLoader(device: context.device)
        super.init(context: context)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }

        self.textureLoader = MTKTextureLoader(device: decodeContext.documentContext.device)

        try super.init(from: decoder)
        
        self.loadModelFromInputValue()
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        if self.inputCastsShadow.valueDidChange
        {
            self.updateLightingOnSubmeshes()
            shouldOutput = true
        }
        
        if self.inputCullingMode.valueDidChange
        {
            self.updateCullingOnSubmeshes()
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
                
        if self.inputFilePathParam.valueDidChange
        {
            self.loadModelFromInputValue()
        }

        if let model = self.model
        {
            let _ = self.evaluate(object: model, atTime: context.timing.time)
            
            if self.inputTransforms.valueDidChange,
                let transforms = self.inputTransforms.value
            {
                
                model.getChildren(true).forEach { child in
                    
                    if let subMesh = child as? InstancedMesh
                    {
                        
                        subMesh.setInstanceMatrices(Array(transforms))
                        subMesh.drawCount = transforms.count
                    }
                }
            }
        }
    }
    
    private func loadModelFromInputValue()
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            self.url = URL(string: path)

            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                let unflattenedModelObject = loadAsset(url:self.url!, textureLoader: self.textureLoader)
                
                if let unflattenedModelObject
                {
                    let object = Object.flatten(unflattenedModelObject)
                    
                    var instancedChildren:[InstancedMesh] = []
                    
                    object.getChildren(true).forEach { child in
                        
                        if let subMesh = child as? Mesh
                        {
                            let material = subMesh.material
                            let geometry = subMesh.geometry
                            
                            let instancedMesh = InstancedMesh(geometry: geometry, material: material, count: 1)
                            
                            subMesh.removeFromParent()
                            
                            instancedChildren.append(instancedMesh)
                        }
                    }
                    
                    object.add(instancedChildren)
                    
                    self.model = object
                }
                
                
                self.updateLightingOnSubmeshes()
                self.updateCullingOnSubmeshes()
            }
            else
            {
                self.model = nil
                print("wtf")
            }
        }
    }
    
    private func updateLightingOnSubmeshes()
    {
        self.model?.getChildren(true).forEach { child in
            
            if let subMesh = child as? Mesh,
               let castShadow = self.inputCastsShadow.value,
               let receiveShadow = self.inputCastsShadow.value
            {
                subMesh.material?.lighting = true
                subMesh.castShadow = castShadow
                subMesh.receiveShadow = receiveShadow
            }
        }
    }
    
    private func updateCullingOnSubmeshes()
    {
        let cullMode = self.cullMode()
        
        self.model?.getChildren(true).forEach { child in
            
            if let subMesh = child as? Mesh
            {
                subMesh.cullMode = cullMode
            }
        }
    }

}

