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
    
    private let modelLoader = ModelFileLoader()

    override public func getObject() -> Object? {
        return model
    }
    
    /// The loaded model's skeletons and animated objects; nil when nothing in it moves.
    private var animation: AssetAnimation? = nil

    override public func deriveStatuses() -> [NodeStatus] { modelLoader.status.map { [$0] } ?? [] }

    private var model: Object? = nil
    {
        didSet
        {
            // Relying on side effects - this triggers
            self.graph?.syncNodesToScene(removingObject:oldValue)
        }
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

        if self.inputTime.valueDidChange
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
        switch self.modelLoader.load(path: self.inputFilePathParam.value, for: self)
        {
        case .unchanged:
            break

        case .loaded(let importedModel, let animation):
            self.animation = animation
            self.model = importedModel
            self.outputDuration.send(animation?.timeRange.map { Float($0.upperBound - $0.lowerBound) } ?? 0)

            // evaluate() applies only the inlets that changed this frame. The
            // inlets may not have changed, but the model is new, so all of
            // them apply to it.
            for port in self.ports where port.kind == .Inlet
            {
                port.valueDidChange = true
            }

            self.markDirty()

        case .noModel(let error):
            self.animation = nil
            self.model = nil
            if let error { throw error }
        }
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
