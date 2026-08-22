//
//  EnvironmentSkyboxNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin

class EnvironmentSkyboxNode: BaseRenderableNode<Mesh>
{
    override public class var name:String {  "Skybox" }
    override public class var nodeType:Node.NodeType { .Object(objectType: .Mesh) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Add an Environment Background Texture to an Environment Renderer" }
    
    override public var object:Mesh? {
        return self.mesh
    }
    
    private let mesh: Mesh
    private let geometry:SkyboxGeometry
    private let material:SkyboxMaterial
    
    public required init(context:Context)
    {
        self.geometry = SkyboxGeometry(context:context, size: 100)
        self.material = SkyboxMaterial(context:context)
        
        self.mesh = Mesh(context:context, geometry: self.geometry, material: self.material)
        
        super.init(context: context)
        
        self.material.setup()
    }

    public required init(from decoder: any Decoder) throws
    {
        guard let context = decoder.context?.documentContext as? Context else { fatalError("Unable to decode Context") }
        
        self.geometry = SkyboxGeometry(context:context, size: 100)
        self.material = SkyboxMaterial(context:context)
        
        self.mesh = Mesh(context:context, geometry: self.geometry, material: self.material)

        try super.init(from: decoder)
        
        self.material.setup()
    }
}
