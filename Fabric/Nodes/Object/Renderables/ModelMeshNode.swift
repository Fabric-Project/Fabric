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
    public override class var nodeType:Node.NodeType { .Object(objectType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load an 3D model file from disk, rendering it to the scene"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        
        // We prune Geom and Material since we dont really let you fuck with them for now
        let ports = super.registerPorts(context: context).filter({ (name: String, port: Port) in
            !(port.name == "Geometry" || port.name == "Material")
        })

        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker, "Path to the 3D model file to load"))),
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
        
        try self.loadModelFromInputValue()
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

        if self.inputDoubleSided.valueDidChange
        {
            self.updateDoubleSidedOnSubmeshes()
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        
        if self.inputFilePathParam.valueDidChange
        {
            try self.loadModelFromInputValue()
        }

        if let model = self.model
        {
            let _ = self.evaluate(object: model, atTime: executionInfo.timing.time)
        }
    }
    
    internal func loadModelFromInputValue() throws
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            guard let url = URL(string: path) else
            {
                self.model = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Model file path is invalid: \(path)")
            }

            self.url = url

            if FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false))
            {
                let unflattenedModelObject = loadAsset(url: url, context:self.context, textureLoader: self.textureLoader)
                
                if let unflattenedModelObject
                {
                    self.model = Object.flatten(unflattenedModelObject)

                    self.markDirty()

                    let _ = self.evaluate(object: model, atTime: 0)
                }
                else
                {
                    self.model = nil
                    throw FabricError(.execution(.failed),
                                      severity: .recoverable,
                                      message: "Could not load model file: \(url.path)")
                }
            }
            else
            {
                self.model = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Model file not found: \(url.path)")
            }
        }
    }
    
    internal func updateLightingOnSubmeshes()
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
    
    internal func updateCullingOnSubmeshes()
    {
        let cullMode = self.cullMode()
        
        self.model?.getChildren(true).forEach { child in
            
            if let subMesh = child as? Mesh
            {
                subMesh.cullMode = cullMode
            }
        }
    }

    internal func updateDoubleSidedOnSubmeshes()
    {
        let doubleSided = self.inputDoubleSided.value ?? false

        self.model?.getChildren(true).forEach { child in

            if let subMesh = child as? Mesh
            {
                subMesh.doubleSided = doubleSided
            }
        }
    }

}
