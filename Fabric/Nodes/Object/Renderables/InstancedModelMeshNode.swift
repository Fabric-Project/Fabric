//
//  InstancedModelMeshNode.swift
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
    override public class var nodeDescription: String { "Load a 3D model file from disk, rendering it to the scene multiple times via instances. An animated model (skeletons or moving parts) poses at Time, every instance alike."}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {

        // We prune Geom and Material since we dont really let you fuck with them for now
        let ports = super.registerPorts(context: context).filter({ (name: String, port: Port) in
            !(port.name == "Geometry" || port.name == "Material")
        })

        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker, "Path to the 3D model file to load"))),
            ("inputTime", ParameterPort(parameter: FloatParameter("Time", 0.0, .inputfield, "Seconds from the start of the model's animation; held at the first or last pose outside it"))),
            ("outputDuration", NodePort<Float>(name: "Duration", kind: .Outlet, description: "Length of the model's animation in seconds; 0 when it has none")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var inputTime:ParameterPort<Float>  { port(named: "inputTime") }
    public var outputDuration:NodePort<Float>  { port(named: "outputDuration") }
    
    private var textureLoader:MTKTextureLoader
    private var url: URL? = nil

    override public func getObject() -> Object? {
        return model
    }
    
    /// The loaded model's skeletons and animated objects; nil when nothing in it moves.
    private var animation: AssetAnimation? = nil

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

        // External resource availability is runtime state. The hydrated port
        // remains changed so the first execution attempts the load.
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

            let timeChanged = self.inputTime.valueDidChange || self.inputFilePathParam.valueDidChange
            if timeChanged, let animation = self.animation
            {
                let start = animation.timeRange?.lowerBound ?? 0
                animation.setTime(start + Double(self.inputTime.value ?? 0))
            }

            // Animated objects move parts within the model; skinned parts sit with their
            // skeletons, which only animated objects move.
            if self.inputTransforms.valueDidChange || (timeChanged && self.animation?.objectAnimation != nil)
            {
                self.placeInstances()
            }
        }
    }

    /// Each instance transform applies in the model's space, so it draws the whole model with
    /// its parts in place. Satin applies a mesh's instances in the mesh's own space, so each
    /// part takes inverse(P) × instance × P, P being the part within the model.
    private func placeInstances()
    {
        guard let model = self.model else { return }

        // Without transforms yet, one instance shows the model where it was loaded.
        let transforms = self.inputTransforms.value ?? [matrix_identity_float4x4]

        for case let part as InstancedMesh in model.getChildren(true)
        {
            let partInModel = model.worldMatrixInverse * part.worldMatrix
            let modelToPart = partInModel.inverse
            part.setInstanceMatrices(transforms.map { modelToPart * $0 * partInModel })
            part.drawCount = transforms.count
        }
    }
    
    private func loadModelFromInputValue() throws
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false
        {
            guard let url = self.graph?.resolveFileReference(path)
                ?? DocumentFileReference.resolve(path, relativeTo: nil) else
            {
                self.animation = nil
                self.model = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Model file path is invalid: \(path)")
            }

            guard self.url != url else { return }

            self.url = url

            if FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false))
            {
                // An animated model keeps its hierarchy, since animated objects and skeleton
                // anchors move the meshes within it; a still one is flattened.
                let loadedAsset = loadAnimatedAsset(url: url, context: self.context, textureLoader: self.textureLoader, instanced: true)
                let root = loadedAsset.animation == nil ? Object.flatten(loadedAsset.root) : loadedAsset.root

                if root.getChildren(true).contains(where: { $0 is InstancedMesh })
                {
                    self.animation = loadedAsset.animation
                    self.model = root

                    if let timeRange = loadedAsset.animation?.timeRange
                    {
                        self.outputDuration.send(Float(timeRange.upperBound - timeRange.lowerBound))
                    }
                    else
                    {
                        self.outputDuration.send(0)
                    }

                    self.placeInstances()
                }
                else
                {
                    self.animation = nil
                    self.model = nil
                    throw FabricError(.execution(.failed),
                                      severity: .recoverable,
                                      message: "Could not load instanced model file: \(url.path)")
                }
                
                
                self.updateLightingOnSubmeshes()
                self.updateCullingOnSubmeshes()
                self.updateDoubleSidedOnSubmeshes()
            }
            else
            {
                self.animation = nil
                self.model = nil
                throw FabricError(.execution(.fileNotFound),
                                  severity: .recoverable,
                                  message: "Model file not found: \(url.path)")
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

    private func updateDoubleSidedOnSubmeshes()
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
