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
        
        return [
            ("inputGeometry",  NodePort<Geometry>(name: "Geometry", kind: .Inlet)),
            ("inputMaterial",  NodePort<Material>(name: "Material", kind: .Inlet)),
            ("inputCastsShadow",  ParameterPort(parameter: BoolParameter("Enable Shadows", true, .button) ) ),
            ("inputDoubleSided",  ParameterPort(parameter: BoolParameter("Double Sided", false, .button) ) ),
            ("inputCullingMode",  ParameterPort(parameter: StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown) ) ),
        ] + ports
    }
        
    // Ergonomic access (no storage assignment needed)
    public var inputGeometry: NodePort<Geometry>   { port(named: "inputGeometry") }
    public var inputMaterial: NodePort<Material>   { port(named: "inputMaterial") }
    public var inputCastsShadow: ParameterPort<Bool>   { port(named: "inputCastsShadow") }
    public var inputDoubleSided: ParameterPort<Bool>   { port(named: "inputDoubleSided") }
    public var inputCullingMode: NodePort<String>   { port(named: "inputCullingMode") }

    
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
    
    override public func teardown()
    {
        super.teardown()

        // this ensures any geometry and materials are free'd correctly
        self.mesh = nil
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
                    //                print("Mesh Node - Updating Geometry and Material")
                    //                mesh.cullMode = .none
                    mesh.geometry = geometry
                    mesh.material = material
                }
                else
                {
                    let mesh = Mesh(geometry: geometry, material: material)
                    mesh.lookAt(target: simd_float3(repeating: 0))
                    mesh.position = self.inputPosition.value ?? .zero
                    mesh.scale = self.inputScale.value ?? .zero
                    
                    let orientation = self.inputOrientation.value ?? .zero
                    mesh.orientation = simd_quatf(angle: orientation.w,
                                                  axis: simd_float3(x: orientation.x,
                                                                    y: orientation.y,
                                                                    z: orientation.z) )
                    
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
            
//            self.markDirty()
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
