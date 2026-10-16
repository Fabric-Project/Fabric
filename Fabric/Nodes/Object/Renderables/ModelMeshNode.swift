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
import ModelIO

public class ModelMeshNode : MeshNode
{
    public override class var name:String { "Model Mesh" }
    public override class var nodeType:Node.NodeType { .Object(objectType: .Loader) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load a 3D model file from disk, rendering it to the scene. An animated model (skeletons or moving parts) poses at Time."}

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

    /// Why the named file gave no model. An error is worded once, in
    /// failLoad(), which throws this same message.
    override public func deriveStatuses() -> [NodeStatus] { loadStatus.map { [$0] } ?? [] }
    private var loadStatus: NodeStatus?
    {
        didSet
        {
            guard loadStatus != oldValue else { return }
            self.subtitleSubject.send()
        }
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

        if self.inputTime.valueDidChange || self.inputFilePathParam.valueDidChange
        {
            self.poseAnimation()
        }

        if let model = self.model
        {
            let _ = self.evaluate(object: model, atTime: executionInfo.timing.time)
        }
    }
    
    internal func loadModelFromInputValue() throws
    {
        guard let path = self.inputFilePathParam.value,
              path.isEmpty == false
        else
        {
            self.loadStatus = nil
            return
        }

        guard let url = self.graph?.resolveFileReference(path)
            ?? DocumentFileReference.resolve(path, relativeTo: nil) else
        {
            try self.failLoad(.fileNotFound, message: "Model file path is invalid: \(path)")
        }

        guard self.url != url else { return }

        guard FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) else
        {
            try self.failLoad(.fileNotFound, message: "Model file not found: \(url.path)")
        }

        guard MDLAsset.canImportFileExtension(url.pathExtension) else
        {
            try self.failLoad(.failed, message: "Model files of type .\(url.pathExtension) cannot be imported: \(url.path)")
        }

        // An animated model keeps its hierarchy, since animated objects and skeleton
        // anchors move the meshes within it; a still one is flattened. Either is
        // empty when ModelIO could read nothing from the file.
        let loadedAsset = loadAnimatedAsset(url: url, context: self.context, textureLoader: self.textureLoader)
        let root = loadedAsset.animation == nil ? Object.flatten(loadedAsset.root) : loadedAsset.root

        guard root.getChildren(true).contains(where: { $0 is Mesh }) else
        {
            self.unload(reporting: .warning("No mesh found in model file: \(url.path)"))
            return
        }

        self.url = url
        self.loadStatus = nil
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

        self.markDirty()

        let _ = self.evaluate(object: model, atTime: 0)
    }

    private func failLoad(_ kind: FabricErrorKind.Execution, message: String) throws -> Never
    {
        self.unload(reporting: .error(message))
        throw FabricError(.execution(kind), severity: .recoverable, message: message)
    }

    /// Clears the url so naming the same file again retries the load.
    private func unload(reporting status: NodeStatus)
    {
        self.url = nil
        self.animation = nil
        self.model = nil
        self.loadStatus = status
    }

    /// Poses the model at `inputTime`, measured from the start of its animation.
    internal func poseAnimation()
    {
        guard let animation = self.animation else { return }
        let start = animation.timeRange?.lowerBound ?? 0
        animation.setTime(start + Double(self.inputTime.value ?? 0))
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
