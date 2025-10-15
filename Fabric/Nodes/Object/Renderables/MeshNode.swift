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
    override public static var name:String { "Mesh" }
    override public static var nodeType:Node.NodeType { .Object(objectType: .Mesh) }

    // Params
    public let inputCastsShadow:BoolParameter
    public let inputDoubleSided:BoolParameter
    public let inputCullingMode:StringParameter
    
    public override var inputParameters: [any Parameter] { [
        self.inputCastsShadow,
        self.inputDoubleSided,
        self.inputCullingMode
    ] + super.inputParameters}

    // Ports
    public let inputGeometry:NodePort<Geometry>
    public let inputMaterial:NodePort<Material>
//    public let outputMesh:NodePort<Object>
    
    public override var ports: [AnyPort] {   [inputGeometry,
                                                           inputMaterial,
//                                                           outputMesh
    ] + super.ports}

    
    override public var object:Mesh? {
        
        // This is tricky - we want to output nil if we have no inputGeometry  / inputMaterial from upstream ports
        if let _ = self.inputGeometry.value ,
           let _ = self.inputMaterial.value
        {
            return mesh
        }
        
        return nil
    }
    
    private var mesh: Mesh? = nil

    public required init(context: Context)
    {
        self.inputCastsShadow = BoolParameter("Enable Shadows", true, .button)
        self.inputDoubleSided = BoolParameter("Double Sided", false, .button)
        self.inputCullingMode = StringParameter("Culling Mode", "Back", ["Back", "Front", "None"], .dropdown)
        
        self.inputGeometry = NodePort<Geometry>(name: "Geometry", kind: .Inlet)
        self.inputMaterial = NodePort<Material>(name: "Material", kind: .Inlet)
//        self.outputMesh = NodePort<Object>(name: MeshNode.name, kind: .Outlet)
        
        super.init(context: context)
    }
    
        
    enum CodingKeys : String, CodingKey
    {
        case inputCastsShadowParameter
        case inputDoubleSidedParemeter
        case inputCullModeParameter
        case inputGeometryPort
        case inputMaterialPort
//        case outputMeshPort
    }
    
    public override func encode(to encoder:Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.inputCastsShadow, forKey: .inputCastsShadowParameter)
        try container.encode(self.inputDoubleSided, forKey: .inputDoubleSidedParemeter)
        try container.encode(self.inputCullingMode, forKey: .inputCullModeParameter)
        try container.encode(self.inputGeometry, forKey: .inputGeometryPort)
        try container.encode(self.inputMaterial, forKey: .inputMaterialPort)
//        try container.encode(self.outputMesh, forKey: .outputMeshPort)
        
        try super.encode(to: encoder)
    }
    
    public required init(from decoder: any Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.inputCastsShadow = try container.decode(BoolParameter.self, forKey: .inputCastsShadowParameter)
        self.inputDoubleSided = try container.decode(BoolParameter.self, forKey: .inputDoubleSidedParemeter)
        self.inputCullingMode = try container.decode(StringParameter.self, forKey: .inputCullModeParameter)
        
        self.inputCullingMode.options = ["Back", "Front", "None"]
        
        self.inputGeometry = try container.decode(NodePort<Geometry>.self, forKey: .inputGeometryPort)
        self.inputMaterial = try container.decode(NodePort<Material>.self, forKey: .inputMaterialPort)
//        self.outputMesh = try container.decode(NodePort<Object>.self, forKey: .outputMeshPort)
        
        try super.init(from: decoder)

    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool
    {
        var shouldOutput = super.evaluate(object: object, atTime: atTime)
        
        // If subclass has object that isnt a mesh, but its own scene graph..
        // We need to handle that in the parent :(
        guard let mesh = object as? Mesh else { return shouldOutput }
        
        if self.inputCastsShadow.valueDidChange
        {
            mesh.castShadow = self.inputCastsShadow.value
            mesh.receiveShadow = self.inputCastsShadow.value
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
        if
            (self.inputGeometry.valueDidChange
             || self.inputMaterial.valueDidChange),
             let geometry = self.inputGeometry.value,
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
                print("Mesh Node - Initializing Mesh with Geometry and Material")

                let mesh = Mesh(geometry: geometry, material: material)
                mesh.lookAt(target: simd_float3(repeating: 0))
                mesh.position = self.inputPosition.value
                mesh.scale = self.inputScale.value

                mesh.orientation = simd_quatf(angle: self.inputOrientation.value.w,
                                                axis: simd_float3(x: self.inputOrientation.value.x,
                                                                  y: self.inputOrientation.value.y,
                                                                  z: self.inputOrientation.value.z) )
                
                self.mesh = mesh
            }
        }
         
        if let mesh = mesh
        {
            let _ = self.evaluate(object: mesh, atTime: context.timing.time)
            
//            if shouldOutput
//            {
//                self.outputMesh.send(mesh)
//            }
        }
        else
        {
//            self.outputMesh.send(nil)
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
