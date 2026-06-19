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
            ("inputGeometry", NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Geometry mesh to render")),
            ("inputMaterial", NodePort<Material>(name: "Material", kind: .Inlet, description: "Material to apply to the geometry")),
            ("inputTransforms", NodePort<ContiguousArray<simd_float4x4>>(name: "Transforms", kind: .Inlet, description: "Array of transforms for each instance")),
            ("inputCastsShadow", ParameterPort(parameter:BoolParameter("Enable Shadows", true, .button, "When enabled, the mesh casts and receives shadows"))),
            ("inputDoubleSided", ParameterPort(parameter:BoolParameter("Double Sided", false, .button, "When enabled, renders both front and back faces"))),
            ("inputCullingMode", ParameterPort(parameter:StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown, "Which faces to cull during rendering"))),
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

        if self.inputDoubleSided.valueDidChange
        {
            mesh.doubleSided = self.inputDoubleSided.value ?? false
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
                    let geometryJustAttached = mesh.geometry !== geometery
                    let materialJustAttached = mesh.material !== material

                    if geometryJustAttached
                    {
                        let windingOrder = mesh.windingOrder
                        mesh.geometry = geometery
                        mesh.windingOrder = windingOrder
                    }

                    if materialJustAttached
                    {
                        mesh.material = material
                    }

                    self.applyCurrentMeshState(mesh,
                                               materialJustAttached: materialJustAttached)
                }
                else
                {
                    let mesh = InstancedMesh(geometry: geometery, material: material, count: self.inputTransforms.value?.count ?? 1)
                    self.applyCurrentMeshState(mesh,
                                               materialJustAttached: true)

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

    private func applyCurrentMeshState(_ mesh: InstancedMesh,
                                       materialJustAttached: Bool)
    {
        mesh.lookAt(target: simd_float3(repeating: 0))
        mesh.visible = self.inputVisible.value ?? true
        mesh.renderOrder = self.inputRenderOrder.value ?? 0
        mesh.renderPass = self.inputRenderPass.value ?? 0
        mesh.position = self.inputPosition.value ?? .zero
        mesh.scale = self.inputScale.value ?? simd_float3(repeating: 1)

        let orientation = self.inputOrientation.value ?? .zero
        mesh.orientation = simd_quatf(vector: orientation).normalized

        let castShadow = self.inputCastsShadow.value ?? true
        mesh.castShadow = castShadow
        mesh.receiveShadow = castShadow
        mesh.cullMode = self.cullMode()
        mesh.doubleSided = self.inputDoubleSided.value ?? false

        if materialJustAttached,
           let material = mesh.material
        {
            material.castShadow = castShadow
            material.receiveShadow = castShadow
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
