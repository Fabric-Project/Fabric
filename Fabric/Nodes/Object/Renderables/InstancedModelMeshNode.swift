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
            ("outputDuration", NodePort<Float>(name: "Duration", kind: .Outlet, description: "Length of the model's animation in seconds; 0 when it doesn't move, no value without a model")),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }
    public var inputTime:ParameterPort<Float>  { port(named: "inputTime") }
    public var outputDuration:NodePort<Float>  { port(named: "outputDuration") }
    
    private let modelLoader = ModelFileLoader(instanced: true)

    override public func getObject() -> Object? {
        return model
    }
    
    override public func deriveStatuses() -> [NodeStatus] { modelLoader.status.map { [$0] } ?? [] }

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
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        if self.inputCastsShadow.valueDidChange
            || self.inputCullingMode.valueDidChange
            || self.inputDoubleSided.valueDidChange
        {
            object?.setModelMeshState(castsShadow: self.inputCastsShadow.value ?? true,
                                      cullMode: self.cullMode(),
                                      doubleSided: self.inputDoubleSided.value ?? false)
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

            let timeChanged = self.inputTime.valueDidChange
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
    
    internal func loadModelFromInputValue() throws
    {
        switch self.modelLoader.load(path: self.inputFilePathParam.value, for: self)
        {
        case .unchanged:
            break

        case .loaded(let object, let animation):
            self.animation = animation
            self.model = object
            self.outputDuration.send(animation?.timeRange.map { Float($0.upperBound - $0.lowerBound) } ?? 0)

            // As in ModelMeshNode: every inlet applies to a new model,
            // Transforms included.
            for port in self.ports where port.kind == .Inlet
            {
                port.valueDidChange = true
            }

            self.markDirty()

        case .noModel(let error):
            self.animation = nil
            self.model = nil
            self.outputDuration.send(nil)
            if let error { throw error }
        }
    }
}
