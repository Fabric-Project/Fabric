//
//  MeshNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/26/25.
//

import Foundation
import Satin
import simd
import Metal

public class InstancedMeshNode : BaseRenderableNode<InstancedMesh>
{
    override public class var name:String { "Instanced Mesh" }
    override public class var nodeType:Node.NodeType  { Node.NodeType.Object(objectType: .Mesh) }
    override public class var nodeDescription: String { "Provides optimized rendering of multiple copies of this Geometry and Material Mesh"}

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return [
            ("inputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet)),
            ("inputMaterial", NodePort<Material>(name: "Material", kind: .Inlet)),
            ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet)),
            ("inputCastsShadow", ParameterPort(parameter:BoolParameter("Enable Shadows", true, .button))),
            ("inputDoubleSided", ParameterPort(parameter:BoolParameter("Double Sided", false, .button))),
            ("inputCullingMode", ParameterPort(parameter:StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown))),
        ] + ports
    }
    // Proxy Ports
    public var inputGeometry:NodePort<SatinGeometry> { port(named: "inputGeometry") }
    public var inputMaterial:NodePort<Material> { port(named: "inputMaterial") }
    public var inputTransforms:NodePort<ContiguousArray<simd_float4x4>> { port(named: "inputTransforms") }
    public var inputCastsShadow:ParameterPort<Bool> { port(named: "inputCastsShadow") }
    public var inputDoubleSided:ParameterPort<Bool> { port(named: "inputDoubleSided") }
    public var inputCullingMode:ParameterPort<String> { port(named: "inputCullingMode") }
  
    override public var object:InstancedMesh? { 
        // This is tricky - we want to output nil if we have no inputGeometry  / inputMaterial from upstream ports
        if let _ = self.inputGeometry.value ,
           let _ = self.inputMaterial.value
        {
            return mesh
        }
        
        return nil
    }
    
    private var mesh: InstancedMesh? = nil
    {
        didSet
        {
            // Relying on side effects - this triggers
            self.graph?.syncNodesToScene(removingObject: oldValue)
        }
    }

    override public func teardown()
    {
        super.teardown()
        self.mesh = nil
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        // If subclass has object that isnt a mesh, but its own scene graph..
        // We need to handle that in the parent :(
        guard let mesh = object as? Mesh else { return shouldOutput }
        
        if self.inputCastsShadow.valueDidChange,
           let castShadow = self.inputCastsShadow.value,
           let receiveShadow = self.inputCastsShadow.value
        {
            mesh.castShadow = castShadow
            mesh.receiveShadow = receiveShadow
            shouldOutput = true
        }
        
        if self.inputCullingMode.valueDidChange
        {
            mesh.cullMode = self.cullMode()
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        if (self.inputGeometry.valueDidChange
            || self.inputMaterial.valueDidChange)
        {
            if let geometery = self.inputGeometry.value,
               let material = self.inputMaterial.value
            {
                if let mesh = mesh
                {
                    mesh.geometry = geometery
                    mesh.material = material
                }
                else
                {
                    let mesh = InstancedMesh(geometry: geometery, material: material, count: self.inputTransforms.value?.count ?? 1)
                    mesh.lookAt(target: simd_float3(repeating: 0))
                    mesh.position = self.inputPosition.value ?? .zero
                    mesh.scale = self.inputScale.value ?? .zero
                    
                    let orientation = self.inputOrientation.value ?? .zero
                    mesh.orientation = simd_quatf(vector:orientation).normalized

                    self.mesh = mesh
                }
            }
            else
            {
                mesh = nil
            }
        }
            
        if let mesh = mesh
        {
            let _ = self.evaluate(object: mesh, atTime: context.timing.time)
            
            if self.inputTransforms.valueDidChange,
                let transforms = self.inputTransforms.value
            {
                mesh.setInstanceMatrices(Array(transforms))
                mesh.drawCount = transforms.count
            }
        }
     }
    
    internal func cullMode() -> MTLCullMode
    {
        switch self.inputCullingMode.value
        {
        case "Front":
            return .front
        case "Back":
            return .back
            
        default: return .none
        }
    }
}
