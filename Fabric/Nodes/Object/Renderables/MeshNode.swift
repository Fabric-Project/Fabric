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

public class MeshNode : BaseRenderableNode<Mesh>
{
    override public class var name:String { "Mesh" }
    override public class var nodeType:Node.NodeType { .Object(objectType: .Mesh) }

    // Register ports, in order of appearance
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        
        let ports = super.registerPorts(context: context)
        
        return ports + [
            ("inputGeometry",  NodePort<SatinGeometry>(name: "Geometry", kind: .Inlet, description: "Geometry mesh to render")),
            ("inputMaterial",  NodePort<Material>(name: "Material", kind: .Inlet, description: "Material to apply to the geometry")),
            ("inputCastsShadow",  ParameterPort(parameter: BoolParameter("Enable Shadows", true, .button, "When enabled, the mesh casts and receives shadows") ) ),
            ("inputDoubleSided",  ParameterPort(parameter: BoolParameter("Double Sided", false, .button, "When enabled, renders both front and back faces") ) ),
            ("inputCullingMode",  ParameterPort(parameter: StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown, "Which faces to cull during rendering") ) ),
        ]
    }
        
    // Ergonomic access (no storage assignment needed)
    public var inputGeometry: NodePort<SatinGeometry>   { port(named: "inputGeometry") }
    public var inputMaterial: NodePort<Material>   { port(named: "inputMaterial") }
    public var inputCastsShadow: ParameterPort<Bool>   { port(named: "inputCastsShadow") }
    public var inputDoubleSided: ParameterPort<Bool>   { port(named: "inputDoubleSided") }
    public var inputCullingMode: ParameterPort<String>   { port(named: "inputCullingMode") }

    
    override public var object:Mesh? {
        
        // This is tricky - we want to output nil if we have no inputGeometry  / inputMaterial from upstream ports
        if let _ = self.inputGeometry.value,
           let _ = self.inputMaterial.value
        {
            return mesh
        }
        
        return nil
    }
    
    private var mesh: Mesh? = nil
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
        self.inputGeometry.value = nil
        self.inputMaterial.value = nil
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
        if
            (self.inputGeometry.valueDidChange
             || self.inputMaterial.valueDidChange)
        {
            
            if let geometry = self.inputGeometry.value,
               let material = self.inputMaterial.value

            {
                if let mesh = mesh
                {
                    let geometryJustAttached = mesh.geometry !== geometry
                    let materialJustAttached = mesh.material !== material

                    if geometryJustAttached
                    {
                        let windingOrder = mesh.windingOrder
                        mesh.geometry = geometry
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
                    let mesh = Mesh(geometry: geometry, material: material)
                    self.applyCurrentMeshState(mesh,
                                               materialJustAttached: true)

                    self.mesh = mesh
                }
            }
            else
            {
                self.mesh = nil
            }
        }
         
        if let mesh = mesh
        {
            let _ = self.evaluate(object: mesh, atTime: context.timing.time)
        }
     }

    private func applyCurrentMeshState(_ mesh: Mesh,
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
    
    func cullMode() -> MTLCullMode
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
