//
//  EnvironmentSkyboxNode.swift
//  Fabric
//
//  Created by Anton Marini on 10/15/25.
//

import Foundation
import Satin

class EnvironmentSkyboxNode: MeshNode
{
    override public class var name:String {  "Skybox" }
    override public class var nodeType:Node.NodeType { .Object(objectType: .Mesh) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Add an Environment Background Texture to an Environment Renderer"}
    
    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputEnvironmentIntensity", ParameterPort(parameter: FloatParameter("Environment Intensity", 1.0, 0.0, 1.0, .slider))),
            ("inputBlur", ParameterPort(parameter: FloatParameter("Blur", 0.0, 0.0, 5.0, .slider))),
        ]
    }
    
    // Port Proxy
    public var inputEnvironmentIntensity:ParameterPort<Float> { port(named: "inputEnvironmentIntensity") }
    public var inputBlur:ParameterPort<Float> { port(named: "inputBlur") }
    
    override public var object:Mesh? {
        return self.mesh
    }
    
    private let mesh: Mesh
    private let geometry = SkyboxGeometry(size: 450)
    private let material = SkyboxMaterial()
    
    public required init(context:Context)
    {
        self.mesh = Mesh(geometry: self.geometry, material: self.material)
        
        super.init(context: context)
        
        self.material.setup()
    }
    
    public required init(from decoder: any Decoder) throws
    {
        self.mesh = Mesh(geometry: self.geometry, material: self.material)
        
        try super.init(from: decoder)
        
        self.material.setup()
    }
    
    override public func evaluate(object: Object?, atTime: TimeInterval) -> Bool {
        
        var shouldOutput = super.evaluate(object: self.mesh, atTime: atTime)
        
        if self.inputEnvironmentIntensity.valueDidChange,
           let intensity = self.inputEnvironmentIntensity.value
        {
            self.material.environmentIntensity = intensity
            shouldOutput = true
        }
        
        if  self.inputBlur.valueDidChange,
            let blur = self.inputBlur.value
        {
            self.material.blur = blur
            shouldOutput = true
        }
        
        return shouldOutput
    }
}
