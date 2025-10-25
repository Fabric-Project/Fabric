//
//  BaseMaterialNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal

public class BaseMaterialNode : Node
{
    override public class var name:String {  "Material" }
    override public class var nodeType:Node.NodeType { .Material }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }

    // Port Registration
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputReceivesLighting", ParameterPort(parameter:BoolParameter("Receives Lighting", true, .button) ) ),
            ("inputWriteDepth", ParameterPort(parameter:BoolParameter("Write Depth", true, .button) ) ),
            ("inputDepthTest", ParameterPort(parameter:BoolParameter("Depth Test", true, .button) ) ),
            ("inputBlending", ParameterPort(parameter:StringParameter("Blending Mode", "Disabled", ["Disabled", "Alpha", "Additive", "Subtractive"], .dropdown) ) ),
            ("outputMaterial",  NodePort<Material>(name: "Material", kind: .Outlet)),
        ]
    }
    
    // Port Proxy
    public var inputReceivesLighting:ParameterPort<Bool>    { port(named: "inputReceivesLighting") }
    public var inputWriteDepth:ParameterPort<Bool>          { port(named: "inputWriteDepth") }
    public var inputDepthTest:ParameterPort<Bool>           { port(named: "inputDepthTest") }
    public var inputBlending:ParameterPort<String>          { port(named: "inputBlending") }
    public var outputMaterial:NodePort<Material>            { port(named: "outputMaterial") }
    
    open var material: Material {
        fatalError("Subclasses must override material")
    }
    
    override public func startExecution(context: GraphExecutionContext)
    {
        self.material.context = context.graphRenderer?.context
    }
    
    public func evaluate(material:Material, atTime:TimeInterval) -> Bool
    {
        var shouldOutput = false
        
        if self.inputBlending.valueDidChange
        {
            material.blending = self.blendingMode()
            shouldOutput = true
        }
        
        if self.inputReceivesLighting.valueDidChange,
           let lighting = self.inputReceivesLighting.value
        {
            material.lighting = lighting
            shouldOutput = true
        }
        
        if  self.inputWriteDepth.valueDidChange,
            let depthWrite = self.inputWriteDepth.value
        {
            material.depthWriteEnabled = depthWrite
            shouldOutput = true
        }
        
        if self.inputDepthTest.valueDidChange,
           let depthTest = self.inputDepthTest.value
        {
            material.depthCompareFunction = (depthTest) ? .greaterEqual : .always
            shouldOutput = true
        }
        
        if self.isDirty
        {
            shouldOutput = true
        }
        
        return shouldOutput
    }
    
    public override func execute(context:GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    {
        let shouldOutput = self.evaluate(material: self.material, atTime: context.timing.time)

        if shouldOutput
        {
            // force since object id is the same
            self.outputMaterial.send(self.material)
        }
     }
    
    private func blendingMode() -> Blending
    {
        switch self.inputBlending.value
        {
        case "Disabled":
            return .disabled
            
        case "Alpha":
            return .alpha

        case "Additive":
            return .additive
            
        case "Subtractive":
            return .subtract

        default: return .subtract
        }
    }
}
